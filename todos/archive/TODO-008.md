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


