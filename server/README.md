# Picture Word Server

```bash
npm install
cp .env.example .env
npm run db:migrate
npm run dev
```

## 访问、订阅与额度

App 首次启动调用 `POST /v1/access/bootstrap`，提交随机安装 ID 与 Apple DeviceCheck token，取得匿名访问令牌和权益摘要。之后：

- `GET /v1/access/status` 返回当前方案、订阅状态、已用/预占/剩余次数与重置时间。
- `POST /v1/store/sync` 接收 StoreKit 2 签名交易和可选的签名续订信息，成功时同时返回订阅链最终 `entitlement` 与本次交易的 `syncedTransactionState`（`active`、`grace`、`expired` 或 `revoked`）。客户端会完成已审计的有效、过期或撤销交易；仅在同步未成功时保留未完成交易继续重试。
- `POST /v1/store/notifications` 接收 App Store Server Notifications V2，按 `notificationUUID` 幂等处理续订、到期、退款、撤销和账单宽限期。

`POST /v1/analyze` 必须携带 `Authorization: Bearer ...`、唯一的 UUID v4 `X-Operation-ID`，免费用户还需携带最新 `X-DeviceCheck-Token`。服务端先创建 10 分钟预占；只有生成至少一个有效物体且成功写出 SSE `complete` 后才扣除 1 次。失败、空结果、取消、超时和过期预占都会释放。相同操作 ID 不会重复扣次；额度耗尽返回 `402 QUOTA_EXHAUSTED` 和最新 `entitlement`。

`POST /v1/vocabulary/resolve` 仅会员可用，修改物体名称后重新生成音标、释义和例句，不扣拍照额度；免费用户返回 `403 MEMBERSHIP_REQUIRED`。

`POST /v1/metrics` 只接收经过白名单限制的付费墙、方案选择、购买和恢复结果。服务端还会聚合识别结果、额度耗尽、纠错与订阅通知；数据按日、事件、产品和结果累计，不保存照片、安装标识、交易标识或其他个人身份。

免费额度按设备终身 3 次。会员通过 Apple 的 `originalTransactionId` 跨设备共享订阅月额度，周期以首次购买时间为锚点并按月末截断。统一有限额度由 `MEMBER_QUOTA_DEFAULT` 设置（默认 100）；设置 `MEMBER_QUOTA_UNLIMITED=true` 会让所有会员使用无限额度。活跃订阅与账单宽限期提供权益，退款、撤销或宽限期结束后不再提供会员权益。

生产部署需要在 `.env` 配置：

```env
ACCESS_CONTROL_ENABLED=true
ACCESS_TOKEN_HASH_SECRET=<至少 32 字符且不同于 IP 哈希的随机值>
MEMBER_QUOTA_DEFAULT=100
MEMBER_QUOTA_UNLIMITED=false
APPLE_BUNDLE_ID=com.kakaword.app
APPLE_APP_ID=<App Store Connect 中的数字 Apple ID>
ADMIN_DASHBOARD_KEY=<至少 32 字符的独立随机管理密钥>
APPLE_ROOT_CERTIFICATE_PATHS=/run/secrets/AppleRootCA-G3.cer
APPLE_JWS_ONLINE_CHECKS=true
APPLE_TEAM_ID=<Apple Team ID>
DEVICECHECK_KEY_ID=<DeviceCheck Key ID>
DEVICECHECK_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----
DEVICECHECK_ENVIRONMENT=production
```

Apple Root CA 证书和 DeviceCheck 私钥必须作为部署密钥挂载，不能提交到仓库。本地 Mock 开发可同时设置 `ACCESS_CONTROL_ENABLED=false` 和 `USAGE_LIMIT_ENABLED=false`。生产与 Sandbox 的 Apple 交易按 `environment` 分区保存；DeviceCheck 测试环境使用 `development`。

修改额度环境变量后需要重启服务。`MEMBER_QUOTA_UNLIMITED=true` 的优先级高于 `MEMBER_QUOTA_DEFAULT`；改回 `false` 后恢复有限额度。权益响应通过 `unlimited: true` 明确标识无限额度，同时保留兼容旧客户端的数值 `limit`/`remaining`。

## 统计看板

配置 `ADMIN_DASHBOARD_KEY` 并重启服务后，可访问 `GET /admin/stats`。浏览器会弹出 HTTP Basic Auth 登录框：用户名固定为 `admin`，密码为配置的管理密钥。未配置密钥时，管理路由返回 404；统计页面和 API 均禁止缓存。

看板默认显示最近 30 天，并以 Production 作为订阅环境；可切换今天、7、30、90 天及 Sandbox、Xcode、LocalTesting。每项指标都提供可展开的口径说明。`GET /admin/api/stats` 提供相同数据的 JSON 结果。订阅、交易数据按环境过滤，但已有聚合事件没有环境字段，因此付费墙、购买与识别事件始终是全部客户端事件，页面会明确显示该口径限制。

统计查询只读取现有 PostgreSQL 表，不保存额外用户或交易明细。管理密钥必须独立于访问令牌、IP 哈希和第三方 API 密钥，并应继续配合 HTTPS 与反向代理访问控制使用。

## 全站用量保护

`POST /v1/analyze` 接收图片、3–10 的 `maxObjects`，以及 `serious`、`funny` 或 `random` 的 `captionStyle`。客户端还可以传入 JSON 字符串形式的 `masteredWords`；服务端会规范化、去重并截取最多 100 个英文词，提示模型在准确可靠的前提下优先寻找其他新词。成功响应通过 SSE 逐个发送物体，并在 `complete` 事件中返回完整结果、英文描述和实际采用的风格。

`POST /v1/vocabulary/resolve` 接收 JSON `{ "term": "窗户" }` 或 `{ "term": "window" }`，返回英文、简体中文、IPA 和初学者例句；该接口不会接收或重新上传照片。

## 页面文案

`GET /v1/content/privacy`、`GET /v1/content/terms` 和 `GET /v1/content/about` 返回隐私政策、服务条款和关于页面的结构化中文文案。文案直接维护在 `src/content/documents.ts`，修改后重新部署服务即可生效；该接口不消耗模型调用额度。

两个模型接口默认启用 PostgreSQL 用量保护：每个 IP 平均每分钟 10 次、最多瞬时突发 10 次，全部实例每天共享 500 次模型调用额度。每日额度按北京时间零点重置。限制值可通过 `.env` 的 `ANALYZE_RATE_LIMIT_PER_MINUTE` 和 `ANALYZE_DAILY_LIMIT` 调整。

生产环境必须配置 `DATABASE_URL` 和至少 32 字符的随机 `RATE_LIMIT_IP_HASH_SECRET`，然后在发布新服务前执行 `npm run db:migrate`。服务端只保存 IP 的 HMAC 摘要，不保存原始 IP。数据库不可用时，识别接口返回 503，避免绕过费用保护。本地使用 Mock 且不需要数据库时，可以显式设置 `USAGE_LIMIT_ENABLED=false`。

生产入口假设只有一层可信 Nginx，Node 端口不能直接暴露公网。Nginx 必须覆盖客户端传入的转发头：

```nginx
location / {
    proxy_pass http://picture_word:8787;
    proxy_http_version 1.1;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header Host $host;
    proxy_buffering off;
    proxy_read_timeout 60s;
}
```

此时服务端设置 `TRUST_PROXY=true`。如 Node 直接对外提供服务，应改为 `TRUST_PROXY=false`，服务端将使用 TCP 远端地址。

PostgreSQL 并发集成测试只会使用显式提供的测试数据库，并在独立临时 schema 中运行：

```bash
TEST_DATABASE_URL=postgres://... npm run test:postgres
```

## 目录结构

```text
src/
├── index.ts                   # 进程入口，只负责启动服务
├── app.ts                     # Hono 应用装配
├── config.ts                  # 环境变量与运行配置
├── content/                   # 隐私政策、服务条款、关于页面文案
├── core/access/               # 匿名令牌、DeviceCheck、StoreKit 验证与额度预占
├── routes/                    # HTTP 业务路由
├── core/image-analysis/       # 图片分析核心能力与供应商适配器
└── utils/                     # 日志、图片尺寸解析等通用能力
```

新增视觉模型时，在 `src/core/image-analysis/providers/` 添加适配器，并在 `index.ts` 注册；HTTP 层不需要感知供应商协议。

## 日志

服务端默认输出 JSON 结构化日志，可通过 `.env` 设置日志级别：

```env
LOG_LEVEL=info
```

可选值为 `debug`、`info`、`warn`、`error`。每个请求都会带有 `requestId`，并记录 HTTP 状态、总耗时、图片字节数与尺寸、视觉模型耗时和返回对象数量。日志不会记录图片内容、base64、Authorization 请求头或 API Key。客户端也可以传入 `X-Request-ID`，方便串联客户端和服务端问题。

The default `VISION_PROVIDER=qwen` uses Alibaba Cloud Model Studio through its Beijing OpenAI-compatible endpoint. Configure `QWEN_API_HOST`, `QWEN_API_KEY`, and optionally `QWEN_MODEL` in `.env`.

Set `VISION_PROVIDER=mock` to return deterministic objects for mobile UI development without using model credits. Gemini and Volcengine adapters remain available as optional alternatives.

The server keeps uploaded images in memory only. It does not write image files or store analysis results.

## 引导线可见落点

物体识别结果中的 `box` 继续表示范围，`anchor` 表示物体可见部分上的归一化点。新增可选字段 `anchorSource`（`ai` / `centerFallback` / 客户端保存的 `manual`）和 `anchorNeedsReview`，区分模型落点、中心兜底及待检查结果。坐标必须有限、在图片和自身物体框内；非法或缺失的模型点改为明确标记的中心兜底。

千问在完整物体列表返回后检查小框覆盖大物体落点等可疑情况，最多追加一次批量图片复核，超时为 8 秒。框重叠只触发复核，不直接移动落点。复核失败不丢弃识别结果，保留待检查状态；用户取消会继续向上传递。流式 `object` 为初步结果，最终结果包含复核后的坐标。其他视觉供应商执行相同的坐标校验和可疑标记，不追加复核请求。

客户端对未标记来源的旧记录继续使用框中心；新 AI 点通过校验后用于引导线。长按标签进入编辑后，可独立拖动圆点纠正落点，不改变物体框；手动点允许超出原识别框，但限制在图片内。编辑中的珊瑚色圆点表示待检查。该流程不是像素分割，模型复核仍可能出错。

千问识别请求使用 `response_format: { type: "json_object" }` 和 `enable_thinking: false`，流式内容按完整 JSON 文档解析。若兼容服务返回 `application/json`，按普通 Chat Completions 响应读取。`QwenResponseError` 区分空内容、上游错误、截断、拒绝及无效 JSON，并记录可用的上游请求 ID、结束原因、字符数和 token 数；不会记录模型正文或照片。出现 `finishReason: "length"` 应检查模型输出预算；上游错误按 `code` 和请求 ID 排查。仅凭旧版“Vision provider returned no JSON object”日志无法确定具体原因。

若初次识别返回空内容、非对象 JSON、无效 JSON 或不符合识别结构的 JSON，且尚未发出任何物体事件，自动使用同一图片按原调用模式重试一次（流式调用的重试仍为流式），并强化顶层对象结构要求。沿用原请求的取消信号及超时预算，不递归重试；鉴权、额度、内容过滤、明确的输出长度限制及已发出部分物体的情况不重试。重试会额外产生一次模型调用。`jsonType` 诊断字段仅记录顶层 JSON 类型，不记录正文。
