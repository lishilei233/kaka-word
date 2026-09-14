### TODO-004：通过移动物体范围修正引导线指向

- 类型：bug
- 优先级：P1
- 状态：待验证
- 需求描述：引导线圆点始终位于物体边界框的几何中心；位置不准确时，用户可以拖动中心圆点整体平移物体范围。编辑模式展示当前物体的矩形边界框，退出编辑后隐藏。
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

- 需求调整（2026-09-11）：物体命名准确率问题已经解决，本轮不再修改识别协议或候选确认能力。后续范围调整为 iOS 端引导线定位：忽略 AI 锚点和历史端点覆盖值，以边界框中心作为唯一端点；用户拖动端点时保持宽高并整体平移边界框，范围不得越出图片。旧字段继续兼容解码，矩形框只在当前物体编辑时展示，不进入普通浏览和分享图片。

- 调整后验收标准：
  - 引导线圆点始终与物体边界框的几何中心重合，不受 AI `anchor` 或旧 `targetOverride` 影响。
  - 长按标签进入编辑模式后只展示当前物体的半透明矩形边界框；退出编辑后隐藏。
  - 拖动中心圆点时矩形范围同步平移、宽高保持不变且不会越出图片，松手后保存到历史记录。
  - 历史详情重新打开和分享卡片使用调整后的范围；分享卡片不显示编辑矩形。
  - 标签位置拖动和物体范围拖动互不覆盖，VoiceOver 可以识别并增量移动物体范围。
  - 结果图片支持与猜单词一致的 1×～4×双指缩放、放大后单指平移，以及双击当前位置放大至 2.5×或复位；缩放状态不写入历史和分享图片。

- 实施范围确认（2026-09-04）：本次收缩为首次 AI 识别返回最多 3 个候选，iOS 对不确定物体逐个展示局部图片和候选确认 sheet；不实施二次识别、准确率评测、多轮对话或复杂权限凭证。

- 执行记录（2026-09-04）：
  - 状态：待验证
  - 分支：`feature/TODO-004-提升物体识别准确率-降低相似物体误识别`
  - 实现摘要：识别协议新增最多 3 个完整词汇候选和确认状态；旧响应默认为已确认。iOS 识别完成后按顺序展示候选 sheet 和局部裁剪图，支持免费选择候选、关闭后保留待确认标记、点击重新打开，以及会员通过“其他”手动修改。选择结果保存至本地历史。
  - 涉及范围：`server/src/core/image-analysis/`、`server/src/routes/analyze.test.ts`、`ios/Core/Models/AnalyzeModels.swift`、`ios/Features/Result/`、`ios/PictureWordTests/AnalysisViewModelTests.swift`。
  - 验证：`server/npm run build` 通过；`server/npm test` 37/37 通过；`xcodebuild build` 应用目标成功（排除 Asset Catalog 以适配当前无 Simulator runtime 环境）；`git diff --check` 通过。iOS 完整测试未运行：当前没有可用 Simulator runtime，且现有 `MembershipStoreTests` 存在与本任务无关的 MainActor 编译错误。
  - 后续事项：在可用 Simulator 或真机验证多个待确认物体的 sheet 顺序、关闭与重新打开、局部图裁剪方向、Dynamic Type、VoiceOver 和免费/会员的“其他”入口。

- 执行记录（2026-09-11）：
  - 状态：待验证
  - 分支：`bug/TODO-004-通过移动物体范围修正引导线指向`
  - 实现摘要：引导线端点改为始终使用边界框几何中心；长按标签进入编辑后展示当前物体的半透明虚线矩形，拖动中心圆点会在图片范围内整体平移边界框并通过现有结果更新链路保存。旧 `anchor` 和 `targetOverride` 保持可解码但不再影响渲染，范围调整后清除旧端点覆盖值；VoiceOver 提供四方向增量移动操作。
  - 涉及范围：`ios/Core/Models/AnalyzeModels.swift`、`ios/Features/Result/AnnotatedImageView.swift`、`ios/Features/Result/AnnotationLayoutEngine.swift`、`ios/Features/Result/ResultView.swift`、`ios/PictureWordTests/AnnotationLayoutEngineTests.swift`。
  - 验证：`git diff --check` 通过；无签名 `xcodebuild build-for-testing`（排除 Asset Catalog）成功，App 与测试目标均完成编译。定向测试未执行：当前没有可用 Simulator runtime，无签名 iOS App 也无法安装到本机的 Designed for iPhone/iPad 目标。
  - 后续事项：在可用 Simulator 或真机验证细小物体的矩形显示、连续拖动、边缘夹取、历史重新打开、分享卡片、标签拖动互不干扰及 VoiceOver 四方向移动；验证通过后再标记完成。

- 执行记录（2026-09-11，缩放补充）：
  - 状态：待验证
  - 分支：`bug/TODO-004-通过移动物体范围修正引导线指向`
  - 实现摘要：结果图片新增 1×～4×双指缩放、放大后单指平移，以及双击当前位置放大至 2.5×或复位。图片和标注共用变换，标签、引导线、编辑圆点及边界框描边通过反向缩放维持屏幕可读尺寸；切换图片会重置缩放，编辑状态切换不会重置，分享渲染不保存缩放状态。操作提示同步补充缩放说明。
  - 涉及范围：`ios/Features/Result/AnnotatedImageView.swift`、`ios/Features/Result/ResultView.swift`、`ios/PictureWordTests/AnnotationLayoutEngineTests.swift`。
  - 验证：`git diff --check` 通过；无签名 `xcodebuild build-for-testing`（排除 Asset Catalog）成功，App 与测试目标均完成编译；新增缩放倍率、偏移夹取、双击定位与复位测试已通过编译。
  - 后续事项：当前没有可用 Simulator runtime，需在真机或可用 Simulator 验证捏合、双击、图片平移、父级纵向滚动，以及放大后圆点拖动和标签拖动的手势优先级。

- 执行记录（2026-09-11，缩放修正）：
  - 状态：待验证
  - 分支：`bug/TODO-004-通过移动物体范围修正引导线指向`
  - 问题与修正：真机反馈原 SwiftUI 自定义变换会缩放整个相框，并出现单词与引导线错位。现已删除自定义比例、偏移和反向尺寸补偿，改为与猜单词相同的 `UIScrollView` 原生缩放；完整的图片和标注画布作为同一个缩放视图放在 `NotebookPhotoFrame` 内部，相框保持固定。
  - 交互：继续使用 1×～4×自由缩放、放大后单指平移、双击当前位置放大至 2.5×或复位；1×时关闭内部平移以保留结果页纵向滚动。
  - 验证：`git diff --check` 通过；无签名 `xcodebuild build-for-testing`（排除 Asset Catalog）成功，App 与测试目标均完成编译。
  - 后续事项：需真机复核图片、单词、引导线和编辑框同步缩放，以及圆点/标签拖动与放大后画面平移的手势优先级。

- 执行记录（2026-09-11，标签碰撞修正）：
  - 状态：待验证
  - 分支：`bug/TODO-004-通过移动物体范围修正引导线指向`
  - 问题与修正：标签拖动布局此前冻结其他手动标签，并让当前标签避开碰撞，因此无法放到其他单词的位置。现改为锁定当前拖动标签，由发生冲突的其他标签自动重新排布；松手后批量保存当前标签及被让位标签的最终位置，避免退出编辑后回跳。
  - 测试：更新布局测试，验证拖动标签保持用户指定位置、原位置标签被移开且所有标签仍不重叠。
  - 验证：`git diff --check` 通过；无签名 `xcodebuild build-for-testing`（排除 Asset Catalog）成功，App 与测试目标均完成编译。
  - 后续事项：需真机验证多个相邻标签连续挤压时的动画流畅度、最终保存位置，以及缩放状态下标签拖动与画面平移的手势优先级。
