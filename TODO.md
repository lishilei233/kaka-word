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
| TODO-004 | feature | P1 | 待验证 | 提升物体识别准确率，降低相似物体误识别 | [TODO-004](./todos/active/TODO-004.md) |
| TODO-009 | feature | P2 | 待分析 | 支持会员识别额度动态调整 | [TODO-009](./todos/active/TODO-009.md) |

## 工作规则

- `todo-intake` 新增或更新 TODO 时，写入 `todos/active/` 并同步更新本索引。
- `todo-executor` 执行活动 TODO 时，读取本索引和对应详细文件；状态变化必须同步更新两处。
- TODO 状态为 `已完成` 后仍保留在 `todos/active/`，由 `todo-archive` 单独归档。
- 归档操作只能移动状态已经是 `已完成` 的条目，不修改原始需求和执行记录。
