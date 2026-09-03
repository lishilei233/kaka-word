# 下一版本 TODO

用于记录下一版本需要开发的功能、UI 修改和待处理问题。

状态说明：

- 待分析：已记录，尚未完成技术分析。
- 待开发：已明确方案，等待实现。
- 开发中：正在实现。
- 待验证：已完成实现，等待测试或真机回归。
- 已完成：已实现并通过验证。
- 暂缓：暂不纳入当前版本。

## 记录格式

### 条目模板

- 类型：feature / ui / bug / optimization / other
- 优先级：P0 / P1 / P2 / P3
- 状态：待分析
- 需求描述：
- 简要分析：
- 影响范围：
- 验收标准：
- 备注：

类型必须严格使用以上五个英文小写值之一，不添加模块、场景或体验后缀；具体领域信息写入标题、简要分析、影响范围或备注。

## TODO 列表

### TODO-001：优化“我的单词”列表页 UI，减少视觉和信息噪音

- 类型：ui
- 优先级：P1
- 状态：已完成
- 需求描述：当前“我的单词”页面元素较多，页面显得杂乱，需要重新整理信息层级并精简列表视觉表现。
- 简要分析：
  - 页面顶部同时展示英文 eyebrow、中文标题、说明文案和状态贴纸；其中说明文案与贴纸可以弱化或移除，优先突出标题和单词数量/状态。
  - 学习状态切换和搜索框各占一整行，控制区高度较大；可考虑合并为更紧凑的筛选区，或将搜索入口降级为按需展开。
  - 列表项同时包含单词、中文、IPA、遇见次数、最近时间、状态图标、右箭头、左侧色条、胶带、阴影和轻微旋转，装饰元素与功能信息叠加过多。
  - 建议列表项保留“单词 + 中文/IPA + 缩略图 + 一个主要状态提示”，将遇见次数和最近时间合并为次要信息；移除胶带、旋转和非必要装饰，统一卡片间距和对齐。
  - 需要保留当前的学习中/已会分类、搜索能力、单词详情点击和无障碍标签；若调整状态入口，仍应支持单手操作和左右切换。
- 影响范围：`ios/Features/Home/HomeView.swift`、`ios/Features/Home/WordLearningViews.swift`、`ios/Features/Home/WordFilterControls.swift`；可能涉及 `WordLearningStore` 提供列表统计或排序数据。
- 验收标准：
  - 页面首屏能明确看出当前分类、搜索入口和单词列表，不再有明显装饰堆叠。
  - 列表项在小屏、长单词、较长中文释义和 Dynamic Type 大字号下保持对齐，不发生截断遮挡或横向溢出。
  - 学习中/已会数量、搜索过滤、点击进入单词详情等现有功能保持可用。
  - 普通列表项的视觉元素数量明显减少，卡片间距、文字层级和状态表达统一。
  - 验证 VoiceOver、Reduce Motion 和不同屏幕尺寸下的交互与布局。
- 备注：设计方向优先采用“内容优先、轻手账装饰”的精简方案；具体是否保留顶部贴纸和列表状态图标，待 UI 草图或实现时确认。

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

### TODO-003：修复上传照片进度条从 0% 到 100% 缺少平滑过渡

- 类型：bug
- 优先级：P2
- 状态：已完成
- 需求描述：上传照片时，进度条看起来从 0% 直接跳到 100%，缺少连续的视觉过渡，需要确认真实上传进度是否正常传递，以及 UI 是否正确表现进度变化。
- 简要分析：
  - `UploadRequestExecutor` 已通过 `URLSessionTaskDelegate.didSendBodyData` 提供真实上传进度，并在开始时发送 0、完成时发送 1；目前不是完全没有进度数据。
  - `AnalysisViewModel.receiveUploadProgress` 每次回调直接更新 `phase`，没有使用显式线性动画、显示值插值或回调节流；网络回调较快时，SwiftUI 可能来不及渲染中间帧。
  - 进度达到 1.0 后会立即将状态切换为 `.analyzing`，因此 100% 状态可能还未完成一次可见渲染就被替换为 AI 分析状态。
  - 需要分别验证：回调本身是否只产生 0/1 两个值、主线程状态更新是否丢失中间值、进度条是否缺少动画，以及上传完成到 AI 分析之间是否需要短暂保持完成态。
- 影响范围：`ios/Core/Networking/APIClient.swift`、`ios/Features/Analysis/AnalysisViewModel.swift`、`ios/Features/Result/ResultView.swift`；可能涉及上传进度测试和识别阶段文案。
- 验收标准：
  - 在大图片、慢速网络和正常网络下，进度条能根据真实上传进度连续、单调地从 0% 变化到 100%。
  - 进度百分比和进度条宽度保持一致，不出现回退、超过 100% 或明显跳变。
  - 上传完成后能稳定看到 100% 或明确的“上传完成”，再进入 AI 分析状态；不能因为动画导致识别流程被阻塞。
  - 小图片或极快上传时，即使真实回调很少，也应有合理的最小视觉过渡；不得用与实际进度严重不符的假进度误导用户。
  - 取消识别、上传失败、重试和重复进入识别流程时，进度状态正确重置，不残留上一次进度。
  - 增加或完善进度回调与 UI 状态测试，覆盖 0、连续中间值、重复值、回退值和 1.0 等输入。
- 备注：优先确认数据链路，再决定采用显式动画、进度插值、回调节流或短暂的“上传完成”过渡；真实上传进度仍应作为基础数据。关联：识别上传状态组件。
- 执行记录（2026-09-02）：
  - 状态：待验证
  - 实现摘要：保留真实上传回调的单调进度，移除请求结束时重复发送的 `1.0`，不再在进度达到 100% 时立即切换分析态；上传完成态至少保留约 180ms，进度百分比与进度条宽度共享动画显示值。
  - 涉及范围：`ios/Core/Networking/APIClient.swift`、`ios/Features/Analysis/AnalysisViewModel.swift`、`ios/Features/Result/ResultView.swift`、`ios/PictureWordTests/AnalysisViewModelTests.swift` 及测试 target 配置。
  - 验证：`xcrun swiftc -frontend -parse ...` 通过；使用去除 `#Preview` 宏块的临时副本执行完整 iOS 源码 `swiftc -typecheck` 通过。`xcodebuild test` 和 `xcodebuild build` 未能进入测试/编译阶段，原因是当前环境没有可用的 iOS Simulator runtime，`actool` 报 `No available simulator runtimes for platform iphonesimulator`。
  - 后续事项：在可用 Simulator 或真机上验证大图、慢速网络、极快上传、取消/失败/重试，以及 Reduce Motion 下的实际动画与状态切换。
- 执行记录（2026-09-02，方案调整）：
  - 状态：待验证
  - 实现摘要：部分撤销上一版百分比 UI、显示值插值和 100% 保持态；识别处理中统一显示“正在分析照片…”，移除右侧百分比/实时单词数，准备、上传、分析阶段统一使用左右往返滑动效果，仅变化顶部阶段标签。保留真实上传回调去重、进度归一化和单调保护。
  - 涉及范围：`ios/Features/Analysis/AnalysisViewModel.swift`、`ios/Features/Result/ResultView.swift`、`ios/PictureWordTests/AnalysisViewModelTests.swift`。
  - 验证：`git diff --check`、目标 Swift 文件语法解析通过；使用去除 `#Preview` 宏块的临时副本执行完整 iOS 源码 `swiftc -typecheck` 通过。`xcodebuild test` 未能进入测试阶段，原因是当前环境没有可用的 iOS Simulator runtime，无法找到指定设备。
  - 后续事项：重点确认极快上传不会出现空白等待，上传/分析阶段的顶部标签切换、取消/失败/重试重置，以及 Reduce Motion 下静态进度段表现。
- 执行记录（2026-09-02，状态文案调整）：
  - 状态：待验证
  - 实现摘要：保留统一的左右滑动进度条和顶部阶段标签，但将识别处理中正文改为按阶段显示“正在准备照片…”、“正在上传照片…”和“正在分析照片…”，避免所有阶段重复显示同一文案。
  - 涉及范围：`ios/Features/Result/ResultView.swift`。
  - 验证：`git diff --check`、目标 Swift 文件语法解析和完整 iOS 源码 `swiftc -typecheck` 通过；iOS 测试仍受当前环境没有可用 Simulator runtime 阻断。
  - 后续事项：确认正文与顶部标签的切换时机一致，完成/失败/取消文案保持不变。
- 执行记录（2026-09-02，完成态揭示动画）：
  - 状态：待验证
  - 实现摘要：对上一版 UI 方案继续做局部调整：仅在 `recognizing → complete` 时显示私有完成态页脚，顶部切换为 `COMPLETE`，Coral 进度线约 320ms 填充到满宽，约 80ms 后底部现有详情以约 240ms 淡入；照片和识别标签保持可见。历史详情首次以 `.complete` 打开时直接显示详情；取消、失败、重试和再次识别会清理完成揭示状态；Reduce Motion 下按相同顺序但跳过填充与淡入动画。
  - 涉及范围：`ios/Features/Result/ResultView.swift`。
  - 验证：`git diff --check`、目标 Swift 文件语法解析和使用可写临时模块缓存的完整 iOS 源码 `swiftc -typecheck` 通过；Xcode 构建已进入 Swift 编译准备，但资源编译因当前环境没有可用的 iOS Simulator runtime 失败，尚未完成运行时验证。
  - 后续事项：在可用 Simulator 或真机上检查普通动画、Reduce Motion、小屏、长详情、极快上传、取消、失败、重试以及结果页重新识别的状态顺序。
- 执行记录（2026-09-02，完成态切换平滑化）：
  - 状态：待验证
  - 实现摘要：修正“正在分析照片…”切换到“识别完成”时的视觉跳变：完成态页脚复用相同的尺寸、边距和滑动条占位，先只更新文案并保持滑动约 80ms，再从当前滑块位置连续扩展至满宽约 320ms，避免进度线从 0 重新出现造成卡顿感。
  - 涉及范围：`ios/Features/Result/ResultView.swift`。
  - 验证：目标 Swift 文件语法解析、完整 iOS 源码 `swiftc -typecheck` 和 `git diff --check` 通过；运行时验证仍受当前环境没有可用的 iOS Simulator runtime 阻断。
  - 后续事项：在 Simulator 或真机确认文案切换无跳变、满宽进度线与详情淡入的衔接，以及 Reduce Motion 行为。
- 执行记录（2026-09-02，进度线重构）：
  - 状态：待验证
  - 实现摘要：将识别页脚的进度线、滑块尺寸、往返相位和动画时长抽取为共享私有实现，统一完成态与处理中页脚的视觉参数；完成填充继续从当前相位平滑收满，收满后停止时间线刷新，Reduce Motion 下全程使用静态进度线。
  - 涉及范围：`ios/Features/Result/ResultView.swift`。
  - 验证：目标 Swift 文件语法解析、完整 iOS 源码 `swiftc -typecheck` 和 `git diff --check` 通过；运行时验证仍受当前环境没有可用的 iOS Simulator runtime 阻断。
  - 后续事项：在 Simulator 或真机确认共享进度线在普通动画、Reduce Motion、重试和再次识别场景下无视觉回归。

### TODO-004：提升物体识别准确率，降低相似物体误识别

- 类型：feature
- 优先级：P1
- 状态：待开发
- 需求描述：针对花瓶被识别成水杯等相似物体误识别问题，提升物体命名、边界框和锚点的准确率，同时允许用户确认或纠正不确定结果。
- 简要分析：
  - 首轮识别提示词调整为“准确率优先”：无法可靠命名时允许跳过，并要求模型返回最多两个候选词及候选置信度差异。
  - 对低置信度、候选分差较小或命中易混淆类别的物体进行选择性复核；优先裁剪边界框并外扩约 20% 重新识别，每张图片最多复核 3 个物体，并限制并发数。
  - 易混淆类别初步覆盖 `mug/cup/glass/vase/jar/bottle`、`bowl/plate/pot/pan`、`window/curtain/door` 等组合。
  - 复核结果区分“已确认、待确认、用户已确认、拒绝”；复核失败时保留首轮结果并标记待确认，不让整次识别失败，也不重复扣除识别次数。
  - iOS 结果页对待确认物体展示提示，支持快捷选择候选词、“都不是，手动输入”，并将用户确认结果保存到历史记录。
  - 纠正已有识别结果不应要求会员；手动增加新物体仍保持现有会员限制。词汇解析接口增加 `purpose: correction | addition`，旧客户端未传时按 `addition` 处理。
  - 保持 SSE 流式体验：高置信物体可先返回，可疑物体等待复核，`complete` 事件作为最终权威结果。
- 影响范围：
  - 服务端：`server/src/core/image-analysis/`、`server/src/routes/analyze.ts`、`server/src/routes/vocabulary.ts`、图片裁剪能力及相关测试。
  - iOS：`ios/Core/Models/AnalyzeModels.swift`、`ios/Core/Networking/APIClient.swift`、`ios/Features/Result/ResultView.swift`、`ios/Features/Result/WordDetailSheet.swift`、历史记录兼容解码。
  - 评测与数据：固定测试集、复核耗时/触发率/改名率/待确认率统计，以及匿名聚合的纠错词对；不得保存照片、用户身份或可关联请求信息。
- 验收标准：
  - 易混淆类别误判率相对当前基线下降至少 30%，物体召回率下降不超过 5 个百分点。
  - 平均每张图片额外模型调用不超过 1 次，单张图片硬上限为 3 次；复核失败不会导致整次识别失败。
  - 识别结果中的待确认状态、候选词和用户纠正结果能够在新旧历史记录中兼容展示与保存。
  - 免费用户可以纠正已有物体，但不能通过纠正接口新增物体；旧版客户端行为保持兼容。
  - SSE 顺序、最终结果覆盖、额度只扣一次、取消和超时降级均有测试覆盖。
  - 先通过固定测试集验证，再使用环境开关逐步开启生产流量；统计数据不包含照片和个人身份信息。
- 备注：引用任务“提升物体识别准确率”的方案记录；需先完成离线评测基线和服务端复核链路，再接入 iOS 交互。关联：识别结果准确性、用户纠错、会员词汇解析权限。

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

### TODO-006：优化“听音找词”练习页面

- 类型：ui
- 优先级：P2
- 状态：待开发
- 需求描述：优化“听音找词”页面的信息层级和操作反馈，让用户能快速理解“播放声音 → 在照片中寻找 → 查看答案/判断结果”的练习流程。
- 简要分析：
  - 当前页面同时包含顶部剩余数量、练习说明、播放按钮、完整照片、提示文案、错误点击标记、查看答案和答题结果操作，首屏信息较多，需要突出当前唯一主要任务。
  - 播放单词按钮应成为明确的首要操作，并强化播放中/可再次播放/语音关闭等状态反馈；提示文案不应与主操作争夺注意力。
  - 图片区域需要明确“点击寻找”的交互暗示，同时保持放大、点选、揭晓答案和错误反馈之间的状态一致，避免用户不知道下一步该做什么。
  - 答案揭晓后，单词、中文、音标和“我还不会/我会了”应形成清晰的结果区；可考虑减少重复说明和不必要的视觉装饰，降低页面滚动距离。
  - 空队列完成页、没有可用照片、无边界框以及连续答错等异常场景需要有一致的引导和返回路径。
- 影响范围：`ios/Features/Home/WordLearningViews.swift`、`ios/Features/Result/WordDetailSheet.swift`（如复用学习内容组件）、`ios/Core/Media/SpeechService.swift` 及相关无障碍文案。
- 验收标准：
  - 用户进入页面后能明确理解当前单词练习目标和下一步操作，主要 CTA 在首屏清晰可见。
  - 播放、再次播放、语音关闭、点中目标、点错目标、查看答案和答题完成等状态反馈明确且不冲突。
  - 图片点选区域、最小点击尺寸、双指缩放和错误提示在小屏及大字号下仍可用。
  - 答案揭晓后能清楚看到英文、中文、IPA，并能快速选择“我还不会”或“我会了”进入下一题。
  - 没有学习中的单词、照片缺失、目标框缺失和连续答错时均有可理解的提示与恢复操作。
  - VoiceOver、Reduce Motion 和语音关闭状态下仍能完成完整练习流程。
- 备注：设计方向优先采用“单任务、强反馈、少装饰”；具体布局和是否加入练习进度指示，待 UI 草图或实现时确认。

### TODO-007：补充识别完成态揭示动画的 UI 状态测试

- 类型：optimization
- 优先级：P2
- 状态：已完成
- 需求描述：为识别页脚的阶段文案、完成进度填充、详情淡入和状态清理补充可自动验证的 UI 状态测试，避免后续调整动画时再次出现跳变、顺序错误或旧动画残留。
- 简要分析：
  - 当前 `PhotoWordCardDetailView` 的完成揭示状态是私有 SwiftUI 状态，现有测试主要覆盖 `AnalysisViewModel` 的上传进度数据链路，尚未覆盖视图状态顺序。
  - 测试应区分历史记录首次打开的 `.complete` 与新识别的 `.recognizing → .complete`，并覆盖取消、失败、重试和再次识别后的清理路径。
  - 如果引入 UI 测试辅助依赖，需要先确认项目当前测试框架和依赖管理方式；若不适合直接断言动画帧，可抽取无副作用的状态转换辅助逻辑进行单元测试。
- 影响范围：`ios/Features/Result/ResultView.swift`、`ios/PictureWordTests/`、测试 target 配置；可能涉及 UI 测试辅助工具。
- 验收标准：
  - 能验证新识别完成时顺序为 `COMPLETE`、进度线填满、详情区淡入。
  - 历史 `.complete` 初次展示不播放完成揭示动画。
  - 取消、失败、重试和再次识别不会保留上一轮完成态或延迟回调。
  - Reduce Motion 下不执行进度填充和详情淡入动画，但展示顺序和最终内容正确。
  - 测试在小屏和长详情内容场景下至少覆盖布局不跳变或内容不可见的问题。
- 备注：关联 TODO-003；优先在可用 Simulator 或真机环境补充验证，避免为了测试引入与项目现有架构不一致的重型依赖。

### TODO-008：打开单词详情时自动播放单词音频，并支持设置开关

- 类型：feature
- 优先级：P2
- 状态：已完成
- 需求描述：打开单词详情时自动播放当前单词音频；在设置页面提供“自动播放单词音频”开关，默认开启。用户关闭后，进入单词详情不再自动播放，但仍可通过现有手动播放入口播放音频。
- 简要分析：
  - 用户明确要求单词详情打开时触发自动播放，并可在设置页控制该行为；默认值为开启。
  - 初步判断需要统一设置项的读取与持久化，并让单词详情展示生命周期只在合适的打开时机触发一次播放，避免视图刷新、返回或重复渲染造成重复播放。
  - 音频播放失败、单词没有可用音频或系统语音不可用时，不应阻塞详情页打开；具体失败提示、是否显示静默反馈及设置项文案待确认。
- 影响范围：`ios/Features/Result/WordDetailSheet.swift`、`ios/Features/Settings/SettingsView.swift`、`ios/Core/Media/SpeechService.swift`；可能涉及设置状态存储、单词详情打开方式及相关测试。
- 验收标准：
  - 首次使用或清除设置后，自动播放开关默认处于开启状态。
  - 开关开启时，用户打开单词详情会自动播放当前单词音频，且同一次打开不会因视图刷新重复播放。
  - 开关关闭后，用户打开单词详情不会自动播放；手动播放入口仍可正常使用。
  - 用户修改开关后离开并重新进入设置页或重启应用，选择能够正确保留。
  - 切换到另一条单词详情、关闭后重新打开同一详情时，播放内容与触发次数符合预期，不播放上一个单词的音频。
  - 音频缺失、播放失败、系统静音或语音服务不可用时，详情页仍可正常打开并保持可操作；不因自动播放失败导致页面崩溃或卡住。
  - 设置项具备清晰的中文标题和 VoiceOver 可读标签，开关在小屏和 Dynamic Type 下正常显示。
- 备注：优先级为初步判断；“打开详情”是否包含从列表点击、练习答案揭晓和历史记录进入等所有入口，以及自动播放失败时是否提示用户，待分析/实现时确认。

- 执行记录（2026-09-03）：
  - 状态：待验证
  - 分支：`feature/TODO-008-打开单词详情时自动播放单词音频-并支持设置开关`
  - 分析结论：确认“我的单词”和识别结果两处入口都通过 `WordDetailSheet` 打开，因此在详情 Sheet 生命周期内统一处理即可覆盖现有详情入口；采用独立于手动朗读的本地偏好，避免关闭自动播放后禁用已有手动播放。
  - 实现摘要：新增默认开启的 `automaticWordSpeechEnabled` 设置并使用 `@AppStorage` 持久化；详情首次出现时自动朗读当前单词，切换到新单词时重新朗读，同一次展示通过对象 ID/英文词追踪避免 SwiftUI 重绘重复触发；详情消失时停止朗读并重置追踪器。设置页新增中文标题、说明和 VoiceOver 标签；语音服务忽略空文本并支持停止当前朗读。
  - 涉及范围：`ios/App/AppSettings.swift`、`ios/Core/Media/SpeechService.swift`、`ios/Features/Result/WordDetailSheet.swift`、`ios/Features/Settings/SettingsView.swift`、`ios/PictureWordTests/WordLearningStoreTests.swift`。
  - 验证：`xcrun swiftc -frontend -parse`（目标 Swift 文件）通过；`git diff --check` 通过；`xcodebuild test` 无法运行，当前环境没有匹配的 iPhone 16 Simulator；通用 iOS 构建已进入 Swift 编译准备，但因 `actool` 报 `No available simulator runtimes for platform iphonesimulator` 失败。
  - 后续事项：在可用 Simulator 或真机验证默认开关、开关关闭后的手动播放、详情重复重绘/切换/关闭重开、语音停止、VoiceOver、Dynamic Type，以及无语音服务或空文本时详情仍可正常打开。
- 执行记录（2026-09-03，用户验证完成）：
  - 状态：已完成
  - 分支：`feature/TODO-008-打开单词详情时自动播放单词音频-并支持设置开关`
  - 验证：用户已完成实际验证，确认自动播放开关、详情播放、重复触发防护、手动播放和语音停止行为符合预期。
  - 后续事项：无。
