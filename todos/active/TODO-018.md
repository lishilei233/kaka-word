### TODO-018：修复历史 StoreKit 交易触发重复权益同步和启动卡顿

- 类型：bug
- 优先级：P1
- 状态：已完成
- Bug 描述：
  - 触发条件：设备存在多笔历史、过期或尚会由 StoreKit 更新序列投递的订阅交易，App 冷启动或恢复到前台时执行会员权益同步。
  - 实际结果：启动阶段同时出现 `foreground`、`startup` 和 `transactionUpdate` 同步请求；首批交易同步结束后，相同 transaction hash 又被后续 `transactionUpdate` 逐笔触发完整权益刷新，连续产生多轮 1.6～5.8 秒的同步。一次启动可能持续约一分钟处于权益刷新状态，并伴随明显界面卡顿或系统手势超时。
  - 预期结果：同一批已处理交易在一次启动/前台周期内不会被重复提交；并发的启动、前台和交易更新请求应安全合并，会员状态及时完成刷新，且不阻塞普通页面交互和系统手势。
- 简要分析：
  - 用户事实：日志中 revision 1～3 的首次同步持续约 19～21 秒并处理约 10 笔过期交易；revision 4～23 随后再次同步其中多笔相同 transaction hash，单轮耗时约 1.6～5.8 秒；期间出现 `Gesture: System gesture gate timed out`。
  - 初步分析：`Transaction.updates` 为历史交易逐条产生事件，每条事件都会调用 `refreshCurrentEntitlements`；该刷新又遍历 `Transaction.unfinished` 与 `Transaction.currentEntitlements`，可能造成事件携带交易和全量扫描之间的重复处理。
  - 初步分析：当前 revision 队列能够合并同时到达的请求，但无法去重首批完成后继续逐条抵达的历史交易更新。`MembershipStore` 在主 actor 上持续发布刷新状态，也可能放大用户感知到的卡顿和控件禁用时间。
  - 初步分析：`UIContextMenuInteraction` 警告不是主要原因；`IPCAUClient` 与空 `AVAudioBuffer` 更可能影响语音播放，不足以解释大量重复会员同步。
- 影响范围：
  - iOS `MembershipStore` 的启动准备、前台刷新、`Transaction.updates` 监听、权益同步队列、交易去重和完成策略。
  - 会员状态卡、购买页及依赖 `isRefreshingEntitlements`、`entitlementLoadState` 的按钮和 loading 展示。
  - StoreKit Sandbox、Xcode StoreKit 配置和真实 App Store 历史交易场景；可能需要服务端同步日志辅助确认幂等行为，但不预设必须修改服务端。
- 验收标准：
  - 含多笔历史或过期订阅交易的设备冷启动时，每个交易在同一同步周期内至多提交一次，不再出现相同 transaction hash 的连续重复同步风暴。
  - `startup`、`foreground` 和 `transactionUpdate` 近同时发生时能够合并或去重，并最终发布正确的会员状态。
  - 已成功处理并 `finish()` 的过期或撤销交易不会在后续更新事件中再次触发完整全量扫描；真正的新交易更新仍能及时同步，不能被错误去重。
  - 无交易、有效会员、过期会员、撤销、未验证交易、网络失败和可重试服务端错误均保留正确的完成、重试与降级行为。
  - 同步期间首页、设置页滚动、返回手势和普通学习功能保持可响应；不再出现由该同步流程引起的系统手势超时。
  - 自动化测试覆盖并发请求合并、批次结束后迟到的重复更新、不同交易更新、失败重试及去重状态的生命周期。
  - 真机或可复现的 StoreKit 测试环境中，对包含至少 10 笔历史交易的启动场景记录同步次数和总耗时，并确认不再产生 revision 连续增长的重复请求链。
- 备注：
  - 关联：TODO-002（已归档）处理购买后权益同步 loading 和错误中间态；本条聚焦启动/前台阶段的历史交易重复投递与卡顿，属于新的可独立验收问题。
  - P1 为初步优先级：问题会在受影响设备上造成约一分钟持续同步、明显交互卡顿及手势超时，但目前没有证据表明会破坏交易或永久丢失会员权益。
  - 待确认：该日志来自 Xcode StoreKit 配置、Sandbox 账号还是真实 App Store 环境；实施前应在对应环境复现并确认 `Transaction.updates` 的具体投递来源。

## 技术分析

- 原 revision/布尔批次队列把运行期间收到的更新转成后续批次，而后续批次再次枚举完整 StoreKit 历史，导致请求量随未完成历史交易数量线性增长。
- 本次改为 `StoreKitTransactionGateway → SubscriptionReconciliationPlanner → EntitlementSyncCoordinator`：网关只负责 StoreKit 采集和 `finish()`，规划器按交易与订阅链归并，actor 统一负责单飞对账、事件缓冲、失败恢复和最终状态发布。
- 冷启动合并 `Transaction.currentEntitlements`、`Transaction.unfinished` 和启动前缓存的 updates；相同交易 ID 以 JWS SHA-256 区分版本，并按 `originalTransactionID` 每条订阅链只选择最新代表交易。
- 当前有效或撤销的代表交易每链最多调用一次 `/v1/store/sync`；普通过期或已升级替代的历史链在本地验证后直接完成，不上传完整历史流水。需要服务端同步的链仅在响应状态一致且同步成功后才完成链内 unfinished 交易。
- 启动后的 update 只处理事件本身；相同 ID/JWS 成功指纹直接忽略，相同 ID 的新 JWS 重新处理。失败指纹不记录并保留重试，unverified 永不提交或 finish。
- 每次对账结束统一读取 `/v1/access/status` 并一次发布权益。前台五分钟内不请求，超过五分钟只读 status；设置页在启动成功后不自动请求，启动失败时按三秒退避重试完整对账。
- `/v1/store/sync` 协议、Bearer token、renewal JWS、请求 ID 和最多三次临时错误重试保持不变；日志新增 reconciliation ID、模式、链统计、逻辑同步次数、HTTP attempt、finish 数量及脱敏交易/JWS 哈希。

## 执行记录

### 2026-09-08

- 状态：待验证
- 分支：`bug/TODO-018-修复历史-StoreKit-交易触发重复权益同步和启动卡顿`
- 实现摘要：重构会员权益同步协调器，区分全量扫描与定向交易更新；增加交易 JWS 指纹去重、在途候选合并、失败保留重试和批次/跳过数量日志；保留未验证、过期、撤销及可重试服务端错误处理。
- 涉及范围：`ios/Core/Purchases/MembershipStore.swift`、`ios/PictureWordTests/MembershipStoreTests.swift`、TODO 索引与详细记录；未修改服务端接口、数据库或 StoreKit 配置。
- 验证结果：`git diff --check` 通过；源码静态检查未发现本次改动的独立错误。`xcodebuild build-for-testing` 与 `xcodebuild test` 受当前机器 `CoreSimulatorService` 不可用、无 iOS Simulator runtime 影响，Asset Catalog 报 `No available simulator runtimes`；完整 XCTest 未执行。
- 后续事项：在可用 Simulator 或真机的 StoreKit 测试环境生成至少 10 笔历史/过期交易，验证冷启动同步次数、总耗时、重复 transaction hash、前后台并发、撤销/过期和网络失败重试；通过后再将状态改为“已完成”。

### 2026-09-09

- 状态：已完成
- 分支：`bug/TODO-018-修复历史-StoreKit-交易触发重复权益同步和启动卡顿`
- 实现摘要：删除 revision、pending full/targeted 和逐笔全量扫描路径，将购买模块拆分为 `MembershipStore`、`StoreKitTransactionGateway` 与 `EntitlementSyncCoordinator`；按 `originalTransactionID` 归并订阅链，当前有效/撤销链每链最多同步一次，普通过期历史本地完成，最终统一读取服务端状态并发布一次 UI 权益。
- 测试覆盖：新增 9 笔同链只规划/执行 1 次 store sync、9 笔及多链全部过期 0 次 store sync、撤销、两条独立有效链、启动前 update 缓冲、生命周期请求单飞合并、同 ID/JWS 去重、同 ID 新 JWS 重处理、失败不 finish 且可重试、unverified 隔离、前台五分钟策略及 status-only 不扫描 StoreKit。
- 验证结果：`git diff --check`、Xcode 工程 plist 校验、核心购买源码 iOS Swift 类型检查及 `MembershipStoreTests.swift` iOS Simulator SDK 类型检查通过；额外运行轻量协调器验收，9 笔同链实际产生 1 次逻辑同步并 finish 9 笔，首次失败未 finish 且第二次对账重试成功。`xcodebuild build-for-testing` 已进入构建但因 Asset Catalog 报 `No available simulator runtimes` 失败；`xcodebuild test` 因 `CoreSimulatorService` 连接失败且不存在可用 `iPhone 16` 设备而未执行。
- 用户验收：用户已在实际运行环境完成验证并确认没有问题；结合源码/测试类型检查与轻量协调器运行验收，本条验收通过。
- 后续事项：无阻塞事项；完整 XCTest 可在 Simulator 服务恢复后作为后续回归检查运行，不影响本条关闭。
