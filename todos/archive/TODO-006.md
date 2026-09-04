### TODO-006：优化“听音找词”练习页面

- 类型：ui
- 优先级：P2
- 状态：已完成
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

- 执行记录（2026-09-03，练习页单屏布局与 Tip 导航）:
  - 状态：待验证
  - 分支：`ui/TODO-006-优化听音找词练习页面`
  - 实现摘要：将练习页 header 固定到安全区顶部并改为与 ResultView 一致的分离胶囊导航；右侧新增灯泡 Tip 按钮和听音找词专属说明 Sheet；新增按可用高度自适应的紧凑播放/提示/照片布局，并保留小屏和大字号下的 ScrollView 兜底；补充语音关闭、再次播放和 Tip 的无障碍反馈。
  - 涉及范围：`ios/Features/Home/WordLearningViews.swift`、`TODO.md`。
  - 验证：`git diff --check`、相关 Swift 文件语法解析通过；应用级 Swift 源码类型检查在排除项目现有 `ResultView.swift` 的 `#Preview` 外部宏后通过。`xcodebuild build` 已进入 Swift 编译阶段，但因当前环境没有可用 iOS Simulator runtime，`actool` 报 `No available simulator runtimes for platform iphonesimulator`，未能完成 Xcode 构建和运行时手动验证。
  - 后续事项：在可用 Simulator 或真机上验证常见机型单屏展示、小屏/横屏/Dynamic Type、Tip Sheet、VoiceOver、Reduce Motion、照片缩放和完整答题流程；通过后将状态更新为“已完成”。

- 执行记录（2026-09-03，关闭按钮与播放区调整）:
  - 状态：待验证
  - 分支：`ui/TODO-006-优化听音找词练习页面`
  - 实现摘要：修复共享 PageHeader 居中标题层在小屏覆盖左右按钮导致关闭按钮无响应的问题；移除练习 prompt；将播放说明置于左侧、播放按钮置于右侧，并释放照片区域高度。
  - 涉及范围：`ios/App/PageHeader.swift`、`ios/Features/Home/WordLearningViews.swift`、`TODO.md`。
  - 验证：`git diff --check`、修改后的 Swift 文件语法解析和应用级 Swift 源码类型检查通过；Simulator/真机运行时验证仍受当前环境没有可用 iOS Simulator runtime 阻塞。
  - 后续事项：在可用 Simulator 或真机上确认关闭按钮实际 dismiss、播放按钮右对齐、无 prompt 后的单屏布局，以及 ResultView/SettingsView Header 按钮无回归。

- 执行记录（2026-09-03，播放区移至照片下方）:
  - 状态：待验证
  - 分支：`ui/TODO-006-优化听音找词练习页面`
  - 实现摘要：将播放按钮和语音状态移至照片下方；答题揭晓后隐藏播放区并展示英文、中文和 IPA；调整照片高度预留，确保未揭晓时主要操作紧邻照片且小屏仍可滚动。
  - 涉及范围：`ios/App/PageHeader.swift`、`ios/Features/Home/WordLearningViews.swift`、`TODO.md`。
  - 验证：`git diff --check`、修改后的 Swift 文件语法解析通过；Simulator/真机运行时验证仍受当前环境没有可用 iOS Simulator runtime 阻塞。
  - 后续事项：在可用 Simulator 或真机上确认 Header 两个按钮可点击、选择正确后播放按钮隐藏并显示单词，以及照片点选坐标、Tip Sheet 和答题流程无回归。

- 执行记录（2026-09-03，按 ResultView 结构修复导航点击）:
  - 状态：待验证
  - 分支：`ui/TODO-006-优化听音找词练习页面`
  - 实现摘要：将练习页调整为背景、固定 Header、内容的明确层级，避免安全区内容遮挡导航按钮；关闭动作增加父级 fullScreenCover 状态复位回调，确保页面可退出；Tips 按钮继续使用 Header 内的真实交互按钮。
  - 涉及范围：`ios/Features/Home/HomeView.swift`、`ios/Features/Home/WordLearningViews.swift`、`ios/App/PageHeader.swift`、`TODO.md`。
  - 验证：`git diff --check`、相关 Swift 文件语法解析通过；完整源码类型检查仍只被项目原有 `ResultView.swift` 的 `#Preview` 外部宏错误阻塞；Simulator/真机运行时验证仍受当前环境没有可用 iOS Simulator runtime 阻塞。
  - 后续事项：在可用 Simulator 或真机上实际点击关闭和 Tips，确认 fullScreenCover 退出、Tip Sheet 展示，以及 ResultView/SettingsView 的共享 Header 无回归。

- 执行记录（2026-09-03，切换 NavigationStack 页面转场）:
  - 状态：待验证
  - 分支：`ui/TODO-006-优化听音找词练习页面`
  - 实现摘要：将听音找词入口从 fullScreenCover 改为复用 HomeView 现有 NavigationStack 的 navigationDestination，获得系统左右 push/pop 转场；练习页隐藏系统导航栏以保留自定义 Header；关闭动作优先复位父级导航状态，无回调时再使用环境 dismiss。
  - 涉及范围：`ios/Features/Home/HomeView.swift`、`ios/Features/Home/WordLearningViews.swift`、`TODO.md`。
  - 验证：`xcrun swiftc -frontend -parse`、`git diff --check` 通过；完整 Swift 源码类型检查仍被项目现有 `ResultView.swift` 第 1156 行 `#Preview` 外部宏环境错误阻塞。
  - 后续事项：在可用 Simulator 或真机上确认首页其他导航入口、听音找词左右转场、关闭按钮、边缘返回手势和 Tips Sheet 无回归。

- 执行记录（2026-09-03，启用设置页同款跟手返回）:
  - 状态：待验证
  - 分支：`ui/TODO-006-优化听音找词练习页面`
  - 实现摘要：按 SettingsView 的导航实现恢复安全区吸顶 Header，加入 `InteractivePopGestureEnabler` 重新启用系统 interactive pop，并移除仅在拖动结束后触发 dismiss 的自定义边缘手势，使页面跟随手指完成左右返回。
  - 涉及范围：`ios/Features/Home/WordLearningViews.swift`、`TODO.md`。
  - 验证：`xcrun swiftc -frontend -parse`、`git diff --check` 通过；运行时验证仍受当前环境没有可用 iOS Simulator runtime 阻塞。
  - 后续事项：在可用 Simulator 或真机上确认页面打开/关闭转场跟手、Header 按钮、系统边缘返回和其他导航页面无回归。

- 执行记录（2026-09-03，Header 返回图标对齐设置页）:
  - 状态：待验证
  - 分支：`ui/TODO-006-优化听音找词练习页面`
  - 实现摘要：将听音找词左侧导航从关闭图标改为设置页同款 `chevron.left`，并对齐直接 Button、胶囊玻璃效果、字号和“返回”无障碍标签。
  - 涉及范围：`ios/Features/Home/WordLearningViews.swift`、`TODO.md`。
  - 验证：`xcrun swiftc -frontend -parse`、`git diff --check` 通过；运行时验证仍需 Simulator 或真机。
  - 后续事项：确认返回图标视觉和点击行为与 SettingsView 一致。


