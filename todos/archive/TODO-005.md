### TODO-005：优化设置页面的会员状态刷新 UI

- 类型：ui
- 优先级：P2
- 状态：已完成
- 需求描述：优化设置页面中会员状态刷新、loading、失败重试和刷新入口的展示，使用户能清楚理解当前状态，不能出现状态切换时的布局跳动和文案混乱。
- 简要分析：
  - 当前会员卡片将方案、额度、重置日期、刷新状态、开通会员和恢复购买集中展示；读取中、已有缓存刷新、失败等状态的视觉层级还可以更明确。
  - 当前页面主要依赖进入设置时自动刷新；成功状态没有明显的手动刷新入口，用户无法主动确认刚完成的购买或恢复结果。
  - loading 时应区分“首次读取”和“刷新已有状态”，并避免用旧额度或旧会员身份产生误导；失败时需要保留上次数据，同时提供紧凑、明确的重试操作。
  - 建议将刷新动作收敛为会员卡片右上角或状态行的图标按钮，统一 spinner、禁用态、失败态和成功后的反馈，避免额外增加大按钮导致卡片变高。
- 影响范围：`ios/Features/Settings/SettingsView.swift`、`ios/Core/Purchases/MembershipStore.swift`；可能涉及会员状态刷新埋点和相关文案。
- 验收标准：
  - 首次读取、刷新中、读取成功、读取失败但有缓存、读取失败且无缓存均有明确且不冲突的状态展示。
  - 用户可以在设置页主动刷新会员状态；刷新过程中按钮不可重复触发，并有清晰 loading 反馈。
  - 刷新失败时保留可用的上次会员/额度信息，并提供“重新读取”路径；无缓存时不展示虚假的额度数据。
  - 购买、恢复购买或前台刷新后，设置页能及时更新会员方案、剩余额度和重置时间。
  - 状态刷新不造成会员卡片明显跳动；小屏、Dynamic Type、VoiceOver 下布局和操作仍可用。
  - 与现有 BUG-001、TODO-002 的会员状态 loading/同步问题保持一致的文案和状态语义。
- 备注：本条只记录设置页 UI 优化；底层刷新耗时或权益同步异常仍按 BUG-001、BUG-003 及 TODO-002 继续排查。

- 执行记录（2026-09-03）：
  - 状态：待验证
  - 分支：`ui/TODO-005-优化设置页面的会员状态刷新-UI`
  - 实现摘要：新增可测试的会员设置页展示状态映射，区分首次读取、缓存刷新、成功和两类失败；设置页会员卡片增加固定 44pt 刷新按钮、spinner、成功反馈、缓存数据标记和无缓存失败文案；设置页进入时自动刷新并复用现有同步冷却，刷新和购买/恢复期间禁止重复操作。
  - 涉及范围：`ios/Core/Purchases/MembershipStore.swift`、`ios/Features/Settings/SettingsView.swift`、`ios/PictureWordTests/MembershipStoreTests.swift`。
  - 验证：`git diff --check`、修改文件 Swift 语法解析和完整 iOS 源码 `swiftc -typecheck` 通过；`xcodebuild test` 与 `xcodebuild build-for-testing` 未进入测试运行阶段，当前环境没有可用 iOS Simulator runtime，`actool` 报 `No available simulator runtimes for platform iphonesimulator`，指定 iPhone 16 设备也不存在。
  - 后续事项：在可用 Simulator 或真机上验证小屏、Dynamic Type、VoiceOver、刷新按钮禁用态、购买/恢复后更新、前台刷新、网络失败重试和缓存保留；确认会员卡片实际无明显布局跳动。

- 执行记录（2026-09-03，缓存文案换行修正）：
  - 状态：待验证
  - 分支：`ui/TODO-005-优化设置页面的会员状态刷新-UI`
  - 实现摘要：移除额度和重置日期中重复的 `上次数据 ·` 前缀，保留独立状态行标识缓存、刷新中和刷新失败；无缓存失败时只显示“暂时无法读取”，避免小屏及 Dynamic Type 下文案换行或展示虚假权益。
  - 涉及范围：`ios/Core/Purchases/MembershipStore.swift`、`ios/Features/Settings/SettingsView.swift`、`ios/PictureWordTests/MembershipStoreTests.swift`。
  - 验证：`git diff --check`、三份修改文件 Swift 语法解析和应用级类型检查通过；运行时验证仍受当前环境无可用 iOS Simulator runtime 阻塞。
  - 后续事项：在具备可用 iOS Simulator runtime 的环境执行 `xcodebuild test`，并完成小屏、Dynamic Type、VoiceOver、按钮禁用态、购买/恢复后更新、前台返回刷新、网络失败重试、缓存保留和无布局跳动的手动验证。

- 执行记录（2026-09-03，Sheet 商品加载与会员刷新解耦）：
  - 状态：待验证
  - 分支：`ui/TODO-005-优化设置页面的会员状态刷新-UI`
  - 实现摘要：新增可并发复用的 `prepareProducts()`，开通会员 Sheet 展示时仅加载 StoreKit 商品，不再因展示 Sheet 触发会员权益刷新；购买前预检及购买/恢复完成后的权益同步保持不变。
  - 涉及范围：`ios/Core/Purchases/MembershipStore.swift`、`ios/Features/Paywall/PaywallView.swift`。
  - 验证：`git diff --check`、四份相关 Swift 文件语法解析和应用级类型检查通过；运行时验证仍受当前环境无可用 iOS Simulator runtime 阻塞。
  - 后续事项：在可用 Simulator 或真机上确认打开 Sheet 不刷新会员状态，商品加载失败可重试，购买和恢复完成后会员卡片及时更新。

- 执行记录（2026-09-03，手动验证完成）：
  - 状态：已完成
  - 分支：`ui/TODO-005-优化设置页面的会员状态刷新-UI`
  - 实现摘要：用户已完成实际手动验证，确认设置页会员状态刷新 UI、缓存/失败展示、刷新入口，以及开通会员 Sheet 仅加载商品、购买/恢复完成后同步会员状态的行为符合预期。
  - 涉及范围：`ios/Core/Purchases/MembershipStore.swift`、`ios/Features/Settings/SettingsView.swift`、`ios/Features/Paywall/PaywallView.swift`、`ios/PictureWordTests/MembershipStoreTests.swift`。
  - 验证：用户手动验证通过；`git diff --check`、Swift 语法解析和应用级类型检查通过。当前环境的 `xcodebuild test` 仍因无可用 iOS Simulator runtime 无法执行。
  - 后续事项：无。


