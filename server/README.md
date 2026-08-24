# Picture Word Server

```bash
npm install
cp .env.example .env
npm run db:migrate
npm run dev
```

## 用量保护

`POST /v1/analyze` 接收图片、3–8 的 `maxObjects`，以及 `serious`、`funny` 或 `random` 的 `captionStyle`。成功响应通过 SSE 逐个发送物体，并在 `complete` 事件中返回完整结果、英文描述和实际采用的风格。

`POST /v1/vocabulary/resolve` 接收 JSON `{ "term": "窗户" }` 或 `{ "term": "window" }`，返回英文、简体中文、IPA 和初学者例句；该接口不会接收或重新上传照片。

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
