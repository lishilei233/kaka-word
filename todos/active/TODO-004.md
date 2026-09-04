### TODO-004：提升物体识别准确率，降低相似物体误识别

- 类型：feature
- 优先级：P1
- 状态：待验证
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

- 实施范围确认（2026-09-04）：本次收缩为首次 AI 识别返回最多 3 个候选，iOS 对不确定物体逐个展示局部图片和候选确认 sheet；不实施二次识别、准确率评测、多轮对话或复杂权限凭证。

- 执行记录（2026-09-04）：
  - 状态：待验证
  - 分支：`feature/TODO-004-提升物体识别准确率-降低相似物体误识别`
  - 实现摘要：识别协议新增最多 3 个完整词汇候选和确认状态；旧响应默认为已确认。iOS 识别完成后按顺序展示候选 sheet 和局部裁剪图，支持免费选择候选、关闭后保留待确认标记、点击重新打开，以及会员通过“其他”手动修改。选择结果保存至本地历史。
  - 涉及范围：`server/src/core/image-analysis/`、`server/src/routes/analyze.test.ts`、`ios/Core/Models/AnalyzeModels.swift`、`ios/Features/Result/`、`ios/PictureWordTests/AnalysisViewModelTests.swift`。
  - 验证：`server/npm run build` 通过；`server/npm test` 37/37 通过；`xcodebuild build` 应用目标成功（排除 Asset Catalog 以适配当前无 Simulator runtime 环境）；`git diff --check` 通过。iOS 完整测试未运行：当前没有可用 Simulator runtime，且现有 `MembershipStoreTests` 存在与本任务无关的 MainActor 编译错误。
  - 后续事项：在可用 Simulator 或真机验证多个待确认物体的 sheet 顺序、关闭与重新打开、局部图裁剪方向、Dynamic Type、VoiceOver 和免费/会员的“其他”入口。
