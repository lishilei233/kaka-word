### TODO-002：会员开通后权益同步 loading 时间较长，并短暂显示额度耗尽

- 类型：bug
- 优先级：P1
- 状态：已完成
- 需求描述：在开通会员成功后，页面仍会 loading 较长时间；loading 过程中可能短暂出现“本期识别额度已用完”。需要确认 loading 时长是否属于正常的 StoreKit 与服务端同步耗时，并消除错误的中间状态展示。
- 简要分析：
  - 当前购买流程会先刷新一次会员权益，再调用 App Store 购买；购买成功后还要提交交易凭证、等待服务端校验/同步，最后再次读取会员状态，因此总耗时可能包含多段串行网络请求。
  - `server/src/routes/store.ts` 的交易同步涉及服务端订阅校验；客户端 `AccessCredentialStore.syncSubscription` 设置了 45 秒请求超时、最多重试 2 次、总 deadline 60 秒。需要记录各阶段耗时，区分正常的首次同步延迟与异常重试/阻塞。
  - `PaywallView` 当前只按 `membership.isMember` 决定显示 `quotaExhaustedCard`，没有判断 `membership.entitlement?.remaining`。只要同步先发布了会员身份，就可能在额度尚未正确刷新或额度仍有剩余时短暂显示“本期识别额度已用完”。
  - 该问题与现有 BUG-003、BUG-006、BUG-007 属于同一条“购买后交易同步与客户端权益刷新”链路，应联合验证，不要只观察最终页面是否显示会员。
- 影响范围：`ios/Features/Paywall/PaywallView.swift`、`ios/Core/Purchases/MembershipStore.swift`、`server/src/routes/store.ts`；可能涉及购买结果埋点和会员状态展示。
- 验收标准：
  - 明确记录并评估“点击购买 → Apple 购买完成 → 凭证同步完成 → 会员状态刷新完成”的各阶段耗时；正常路径不应出现无解释的长时间 loading。
  - loading 期间不显示“本期识别额度已用完”等基于旧权益或中间权益的结论性文案。
  - “本期识别额度已用完”仅在会员状态已确认且 `remaining <= 0` 时显示；有剩余额度时显示正确的会员状态和剩余次数。
- 购买成功后页面能稳定显示会员已开通，且首页/设置页的 `canStartRecognition` 与服务端最终权益一致。
- 服务端校验超时、重试、暂时不可用、购买待批准等场景有明确状态和可恢复路径，不将临时同步状态误报为额度耗尽。
- 增加或完善购买链路测试，覆盖旧免费权益、已耗尽免费额度、已耗尽会员额度、购买成功但状态同步延迟等场景。
- 备注：优先先修正额度耗尽卡片的展示条件，再用真实 Sandbox/网络较慢场景测量 loading；若耗时确实过长，再优化同步请求或改为更明确的分阶段 loading 文案。关联：BUG-003、BUG-006、BUG-007。

- 执行记录（2026-09-02）：
  - 状态：待验证
  - 分支：`Bug-会员购买体验/TODO-002-会员开通后权益同步-loading-时间较长-并短暂显示额度耗尽`
  - 实现摘要：新增会员 Paywall 状态机，仅在权益同步完成且 `remaining <= 0` 时显示额度耗尽；同步中显示明确 loading，失败时显示可恢复的“重新读取”，已有剩余额度时显示会员已开通及本期剩余次数。购买预检、Apple 返回、购买后同步、单次交易同步和总购买流程增加耗时日志，用于区分 StoreKit、服务端校验和重试造成的延迟。
  - 涉及范围：`ios/Core/Purchases/MembershipStore.swift`、`ios/Features/Paywall/PaywallView.swift`、`ios/PictureWordTests/MembershipStoreTests.swift`。
  - 验证：`git diff --check` 通过；完整 iOS 源码类型检查（临时副本移除项目原有 `#Preview` 宏）通过；服务端 `npm test` 通过，35/35。`xcodebuild build/test` 未完成运行时验证，当前环境没有可用 iOS Simulator runtime，且测试无法找到具体 Simulator 设备。
  - 后续事项：在可用 Simulator 或真机 Sandbox 中验证购买成功、网络慢/超时重试、同步中旧额度为 0、同步失败、剩余额度和首页/设置页最终权益一致性；确认耗时日志中的各阶段时长。
- 执行记录（2026-09-03，购买 Sheet loading 优化）：
  - 状态：待验证
  - 分支：`Bug-会员购买体验/TODO-002-会员开通后权益同步-loading-时间较长-并短暂显示额度耗尽`
  - 实现摘要：购买流程新增分阶段文案（确认会员状态、连接 App Store、同步会员权益）；同步队列每个任务只处理启动时的一个批次，购买不再等待之后的前台/交易更新批次；成功同步不再在即将关闭的 Paywall 上弹“会员已开通”Alert。
  - 涉及范围：`ios/Core/Purchases/MembershipStore.swift`、`ios/Features/Paywall/PaywallView.swift`。
  - 验证：`git diff --check`、目标 Swift 文件语法解析、临时副本完整 iOS 源码 `swiftc -typecheck` 通过；iOS Simulator `xcodebuild test/build` 仍受当前环境无可用 Simulator runtime 阻断。
  - 后续事项：在真机 Sandbox 重新购买，确认 Sheet 关闭耗时、按钮文案切换和最终会员状态；检查同一交易不再因后续刷新延迟关闭 Sheet，并确认 Alert warning 消失。


