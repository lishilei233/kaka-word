# 咔咔单词订阅上线清单

以下项目涉及 Apple 账号、密钥和 App Store Connect，不能仅通过代码仓库完成，必须在发布前逐项确认。

## App Store Connect

- [ ] 已接受付费 App 协议，并完成税务与收款账户配置。
- [ ] 在同一订阅组、同一等级创建月会员 `com.kakaword.app.membership.monthly` 与年会员 `com.kakaword.app.membership.annual`。
- [ ] 中国大陆价格配置为 15 元/月、108 元/年；其他店面的价格已检查。
- [ ] 未配置免费试用、介绍性优惠、家庭共享、次数包或无限识别。
- [ ] 已启用 16 天账单宽限期，并同时覆盖生产与 Sandbox。
- [ ] App Store Server Notifications V2 的生产与 Sandbox 地址均配置为 `https://api.kakaword.com/v1/store/notifications`。
- [ ] 两个产品随 App 版本一同提交审核，订阅本地化、审核截图和审核说明已补齐。

## 服务端密钥与部署

- [ ] 已部署 `server/migrations/001_usage_limits.sql` 和 `002_subscriptions.sql`。
- [ ] 已设置独立的 `RATE_LIMIT_IP_HASH_SECRET` 与 `ACCESS_TOKEN_HASH_SECRET`，两者均为至少 32 字符的随机值。
- [ ] 已下载并挂载 Apple Root CA 证书，`APPLE_ROOT_CERTIFICATE_PATHS` 指向实际文件。
- [ ] 已填写 App 的数字 Apple ID、Bundle ID 和两个订阅产品 ID。
- [ ] 已创建 DeviceCheck 私钥，并安全设置 `DEVICECHECK_KEY_ID`、`APPLE_TEAM_ID` 与 `DEVICECHECK_PRIVATE_KEY`。
- [ ] Sandbox 使用 `DEVICECHECK_ENVIRONMENT=development`，生产使用 `production`；生产与 Sandbox 数据通过交易环境字段隔离。
- [ ] 通知入口可从公网通过 HTTPS 访问，不要求 App 访问令牌，并能幂等接收重复通知。

## 测试与审核

- [x] 工程已包含并在共享 Run Scheme 中启用 `ios/KakawordSubscriptions.storekit`；两个产品同组同级，使用中国大陆本地价格与简体中文商品文案。
- [ ] 使用 Xcode StoreKit 配置验证购买成功、取消、待批准、未验证交易、续订、到期、退款、撤销与宽限期。
- [ ] 使用 App Store Sandbox 验证真实产品价格、恢复购买、跨设备共享额度和 Server Notifications V2。
- [ ] 验证免费前三次成功后剩余 2、1、0；失败、空结果、取消不扣次；第四次被客户端与服务端同时拦截。
- [ ] 验证相同 `X-Operation-ID`、并发请求、进程中断和 10 分钟预占过期不会重复扣次或超额。
- [ ] 覆盖 1 月 31 日、闰年、跨年和 UTC 边界的月度额度重置测试。
- [ ] App Store 隐私标签已申报购买记录、设备/用户标识符和诊断/使用数据的实际用途，且未声明收集照片。
- [ ] 审核备注明确说明无需账号、免费额度、订阅入口、恢复购买路径和可测试的普通物品照片。
