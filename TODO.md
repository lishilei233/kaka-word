# 项目 TODO

这里仅维护活动 TODO 的索引。每个 TODO 的完整需求、分析、验收标准和执行记录保存在独立文件中。

## 状态说明

- 待分析：已记录，尚未完成技术分析。
- 待开发：已明确方案，等待实现。
- 开发中：正在实现。
- 待验证：已完成实现，等待测试或真机回归。
- 已完成：已实现并通过验证，等待归档。
- 暂缓：暂不纳入当前版本。

## 类型说明

类型严格使用以下英文小写值之一：`feature` / `ui` / `bug` / `optimization` / `other`。

## 目录结构

- `todos/active/TODO-xxx.md`：待处理或刚完成、尚未归档的详细条目。
- `todos/archive/TODO-xxx.md`：已经归档的完整条目和历史执行记录。
- `todos/archive/INDEX.md`：已归档条目索引。

## 活动 TODO

| ID | 类型 | 优先级 | 状态 | 标题 | 详细记录 |
| --- | --- | --- | --- | --- | --- |
| TODO-004 | bug | P1 | 待验证 | 通过移动物体范围修正引导线指向 | [TODO-004](./todos/active/TODO-004.md) |
| TODO-010 | feature | P2 | 已完成 | 记录匿名聚合的识别纠错与候选确认数据 | [TODO-010](./todos/active/TODO-010.md) |
| TODO-012 | feature | P2 | 已完成 | 基于已掌握词的自动个性化推荐 | [TODO-012](./todos/active/TODO-012.md) |
| TODO-013 | ui | P2 | 待分析 | 统一并优化 App 整体 UI 风格 | [TODO-013](./todos/active/TODO-013.md) |
| TODO-014 | feature | P2 | 已完成 | 在单词详情 Sheet 中展示物体图片 | [TODO-014](./todos/active/TODO-014.md) |
| TODO-015 | feature | P2 | 暂缓 | 建立仅支持 Apple 登录的用户系统 | [TODO-015](./todos/active/TODO-015.md) |
| TODO-016 | feature | P2 | 暂缓 | 支持通过 iCloud 跨设备同步学习数据 | [TODO-016](./todos/active/TODO-016.md) |
| TODO-017 | feature | P2 | 已完成 | 评估并支持英语发音音色选择 | [TODO-017](./todos/active/TODO-017.md) |
| TODO-018 | bug | P1 | 已完成 | 修复历史 StoreKit 交易触发重复权益同步和启动卡顿 | [TODO-018](./todos/active/TODO-018.md) |

## 工作规则

- `todo-intake` 新增或更新 TODO 时，写入 `todos/active/` 并同步更新本索引。
- `todo-executor` 执行活动 TODO 时，读取本索引和对应详细文件；状态变化必须同步更新两处。
- TODO 状态为 `已完成` 后仍保留在 `todos/active/`，由 `todo-archive` 单独归档。
- 归档操作只能移动状态已经是 `已完成` 的条目，不修改原始需求和执行记录。
