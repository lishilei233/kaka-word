# Picture Word UI 规范

> 本文档是 Picture Word iOS 客户端当前的界面设计与交互约定。
> 新页面、新组件和视觉调整应优先遵循本文档；如果页面属于特殊场景，应在代码中明确说明例外原因。

## 1. 设计定位

Picture Word 的核心视觉方向是“英语学习手账”：

- 纸张、横线、点阵、贴纸和胶带等手账元素。
- 温暖的米白背景，搭配少量高饱和强调色。
- 圆润、亲和的中文界面文字。
- 衬线标题和等宽英文标签形成编辑感与学习工具感。
- 通过卡片、圆角、颜色和层级留白组织内容，避免复杂装饰堆叠。

当前主题和公共视觉组件集中在：

- `ios/App/AppTheme.swift`
- `ios/App/PageHeader.swift`
- `ios/App/PictureWordApp.swift`

## 2. 色彩规范

代码中使用语义色，不要在页面中重复声明 RGB 数值。

| 语义色 | 用途 |
| --- | --- |
| `Color.ink` | 主文字、深色按钮、主要图标 |
| `Color.paper` | 页面主背景 |
| `Color.paperLight` | 内容卡片、浅色玻璃、按钮底色 |
| `Color.paperDeep` | 纸张深色层、弱化背景 |
| `Color.sun` | 主操作、积极状态、强调按钮 |
| `Color.coral` | 品牌强调、错误、重要标签、编号 |
| `Color.mint` | 学习完成、辅助信息、结果状态 |
| `Color.sky` | 信息卡片和次要视觉区块 |
| `Color.pencil` | 背景纹理、弱化描边和辅助文字 |

使用原则：

- 主页面以 `Color.paper` 和 `NotebookBackground` 为基础。
- 主文字使用 `Color.ink`，次要文字通过透明度弱化，例如 `.opacity(0.48)`～`.opacity(0.68)`。
- 红色仅用于错误、重要提示或品牌强调，不作为大面积背景。
- 卡片优先使用 `Color.paperLight`，避免使用纯白造成页面层级过硬。
- 新增颜色应先判断是否可以复用现有语义色；确有需要时再扩展 `Color` 语义角色。

## 3. 页面背景

普通页面使用：

```swift
NotebookBackground()
```

`NotebookBackground` 包含：

- 米白纸张底色。
- 低透明度横线。
- 低透明度点阵。
- 忽略安全区，覆盖完整页面背景。

不要在普通手账页面使用纯黑全屏背景。识别结果、设置、分享编辑和普通详情页都应保持纸张主题的一致性。

相机取景页是例外：为了保证取景、曝光和照片预览的可读性，可以使用深色主体和深色控制层。

## 4. 字体与文字层级

公共字体定义位于 `ios/App/AppTheme.swift`：

| 类型 | 推荐字体 | 用途 |
| --- | --- | --- |
| `Font.scrapbookHero` | 粗体衬线 | 首页主标题、强视觉标题 |
| `Font.scrapbookTitle` | 粗体圆体 | 区块标题、学习卡片标题 |
| `Font.scrapbookBody` | 中等圆体 | 首页说明和正文 |
| `Font.scrapbookCaption` | 粗体圆体 | 小标签、状态文字 |
| 等宽字体 | `.monospaced` | 英文 eyebrow、编号、版本、进度标签 |
| 圆体 | `.rounded` | 中文正文、按钮、表单控件 |
| 衬线字体 | `.serif` | 英文单词、编辑感标题、例句等内容 |

文字原则：

- 页面标题采用“英文 eyebrow + 中文标题”结构。
- eyebrow 使用大写等宽字体，并适当增加字距。
- 重要标题使用较重字重，说明文字使用中等字重和较低透明度。
- 单词本身可以使用衬线字体，突出学习内容和卡片感。
- 长文本必须支持换行，标题应设置 `lineLimit` 和 `minimumScaleFactor` 避免小屏溢出。

## 5. 二级页面 Header

统一组件为 `PictureWordPageHeader`，位于 `ios/App/PageHeader.swift`。

Header 采用分离胶囊结构：

```text
[返回/取消]      [英文 eyebrow + 中文标题]      [页面操作]
```

规范：

- 左、中、右区域使用彼此独立的胶囊，不使用一条连续导航栏。
- 中间标题使用 `ZStack` 居中，不能因为左右按钮宽度不同而偏移。
- 胶囊高度约为 50pt。
- Header 左右留白约 18pt，胶囊之间保持约 6pt 间距。
- 浅色页面使用 `Color.ink` 前景和纸张色玻璃。
- 深色页面使用白色前景和暗色玻璃。
- 页面操作应使用独立胶囊，例如分享、删除、AI、SET。
- Header 内的返回和取消必须是明确可点击的 `Button`，点击区域覆盖整个胶囊。

需要吸顶时，Header 应放在滚动内容外，并使用：

```swift
.safeAreaInset(edge: .top, spacing: 0) {
    header
}
```

目前设置页已经采用该方式。

相机页继续使用现有 UIKit Header，不强行迁移到 SwiftUI 通用组件。

## 6. 卡片、按钮与玻璃效果

卡片规范：

- 普通内容卡片圆角约 18～30pt。
- 卡片使用 `Color.paperLight` 及适当透明度。
- 描边使用低透明度 `Color.ink`，不要使用高对比黑色边框。
- 阴影应轻柔，用于区分层级，不制造悬浮面板感。
- 重要信息可以通过 `Color.sun`、`Color.mint`、`Color.sky` 或 `Color.coral` 的低透明度背景区分。

按钮规范：

- 普通页面的主要、次要和危险 CTA 统一使用 `PictureWordButton`，不要在业务页面重复实现字体、圆角、阴影和按压反馈。
- `PictureWordButton.Style.primary` 使用 `Color.sun`，用于页面中最重要的下一步；`secondary` 用于返回、跳过等弱操作；`destructive` 用于明确的删除或清空操作。
- 大面积 CTA 使用默认的 `large` 尺寸；工具栏和短文本操作使用 `compact`。加载过程通过 `isLoading` 表达，业务层继续通过 `.disabled(...)` 提供输入校验状态。
- 圆形按钮用于相机、播放、语音等单一图标操作。
- Capsule 用于返回、筛选、状态和短文本操作。
- 圆角矩形用于主要行动按钮和较长文字按钮。
- 主要行动优先使用 `Color.sun`；危险操作使用系统 destructive 角色或 `Color.coral`。
- 图标按钮必须提供 `accessibilityLabel`。
- 复杂玻璃按钮统一复用 `pictureWordGlass`，不要另写一套材质效果。

`pictureWordGlass` 的行为：

- iOS 26 使用系统 Liquid Glass。
- 较早系统使用材质、半透明色、描边和阴影模拟相同层级。
- 交互胶囊传入 `interactive: true`。
- 被动标签和标题胶囊传入 `interactive: false`。

## 7. 导航与页面呈现

导航选择：

| 场景 | 方式 |
| --- | --- |
| 首页进入设置等层级页面 | `NavigationStack` + `NavigationLink` |
| 相机 | `.fullScreenCover` |
| 识别流程 | `.fullScreenCover` |
| 历史详情/识别结果 | `.fullScreenCover` |
| 单词详情 | `.sheet` |
| 分享卡编辑 | `.sheet` |
| 系统分享面板 | `.sheet` + `UIActivityViewController` |

交互原则：

- 普通层级页面优先使用系统 `NavigationStack` 返回手势。
- 使用自定义 Header 时隐藏系统导航栏，避免出现两套 Header。
- 自定义 Header 的返回按钮必须调用当前页面的 `dismiss()`。
- 自定义返回手势只作为特殊页面的兼容方案，不应覆盖普通页面的横向滚动。
- 当前需要保留自定义 Header 的导航页面，可以使用 `InteractivePopGestureEnabler` 重新启用系统侧滑返回。

## 8. 弹窗规范

确认、错误和提示反馈使用系统原生弹窗：

- `.alert`：错误、保存失败、取消识别等单次确认或提示。
- `.confirmationDialog`：清空历史、切换任务等 destructive 操作。
- `.sheet`：图片、滚动内容、编辑和单词详情等复杂内容。

不要为短暂错误或提示新增自定义 Toast overlay、自动消失动画或重复的弹窗系统。

### 8.1 Sheet UI 规范

普通内容 Sheet 使用 `PictureWordSheet` 作为内容容器，统一以下行为：

- 背景使用 `Color.paper`，内容水平边距为 24pt。
- 长内容使用无滚动条的纵向滚动，并支持交互式下滑收起键盘。
- 标题使用 `PictureWordSheetHeader`，采用英文大写 eyebrow + 中文标题的层级结构。
- eyebrow 使用 10pt 黑体等宽字，标题使用 24pt heavy rounded 字体。
- 右侧取消、完成等操作放在标题行，使用明确文字或图标无障碍标签。
- Sheet 呈现优先使用 `pictureWordSheetPresentation()`，统一纸张背景和拖拽指示器。

高度规范：

- 信息提示、简单表单默认使用 `.medium`。
- 详情和可滚动内容可以提供 `.medium`、`.large` 两档，并通过 selection binding 控制当前高度。
- 键盘和 detent 行为由具体 Sheet 根据内容决定；共用容器只负责内容滚动和视觉层级，不强制改变 Sheet 高度。

系统弹窗按钮文字应明确：

- 取消类操作使用“取消”“继续等待”等语义明确的文字。
- 破坏性操作使用 destructive role。
- 纯提示使用“知道了”或“完成”。

## 9. 深色模式

当前 App 在根节点固定使用浅色外观：

```swift
.preferredColorScheme(.light)
```

因此普通页面不需要额外维护暗黑模式配色。相机页可以保留自己的深色拍摄控制视觉，但这属于页面场景例外，不代表 App 开启了系统暗黑模式。

## 10. 布局与适配

- 页面主体通常使用约 20pt 的水平边距。
- Header 和底部操作需要遵守安全区。
- 长页面使用 `ScrollView(showsIndicators: false)`，避免滚动条破坏手账视觉。
- 关键标题、按钮和胶囊要兼容小屏宽度。
- 不依赖固定屏幕宽度；优先使用 `frame(maxWidth: .infinity)`、`Spacer` 和弹性布局。
- 需要保持居中的标题使用叠加布局，而不是依赖左右内容的自然排列。
- 动态字体下不能让标题遮挡操作按钮，必要时使用 `minimumScaleFactor` 或限制最大宽度。

## 11. 无障碍与反馈

- 图标按钮必须设置无障碍标签。
- 装饰性背景、纹理、胶带和贴纸应设置为无障碍隐藏。
- 重要状态不能只依赖颜色表达，应同时有文字或图标。
- 动画应尊重 `accessibilityReduceMotion`。
- 网络识别过程中必须提供明确的阶段状态：准备、上传、分析、处理中、成功或失败。
- 识别失败应保留重试路径，不改变已存在的识别结果或历史数据。

## 12. 新页面开发检查清单

- [ ] 是否使用了语义色，而不是新增页面级 RGB 颜色？
- [ ] 普通页面是否使用 `NotebookBackground`？
- [ ] 二级页面是否使用分离胶囊 Header？
- [ ] Header 返回按钮是否覆盖完整点击区域并设置无障碍标签？
- [ ] 需要吸顶时是否使用 `.safeAreaInset(edge: .top)`？
- [ ] 是否隐藏了重复的系统导航栏？
- [ ] 确认、错误和提示是否使用原生 `.alert` / `.confirmationDialog`？
- [ ] 复杂内容是否使用 `.sheet` 或 `.fullScreenCover`？
- [ ] 是否适配小屏、动态字体和 Reduce Motion？
- [ ] 是否完成无签名 Debug 构建验证？
