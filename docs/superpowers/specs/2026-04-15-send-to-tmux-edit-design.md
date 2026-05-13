# SendToTmux 编辑后发送设计

日期: 2026-04-15
状态: 已在对话中确认

## 概述

为 `send-to-tmux.nvim` 增加一个“编辑后再发送”的工作流：把当前行或可视选区内容放进一个临时浮动编辑器中。这个编辑器由 `snacks.nvim` 承载；当用户保存该缓冲区时，插件会把编辑后的内容发送到已选中的 tmux pane，并关闭窗口。

这个设计把主流程保留在 Neovim 内部，避免引入 tmux popup 的额外进程管理，同时复用插件现有的 tmux 目标校验与发送逻辑。

## 目标

- 允许用户在发送前先编辑文本。
- 整个流程保持在当前 Neovim 会话内完成。
- 保持现有 `SendToTmux` 和 `SendToTmuxExec` 的行为不变。
- 成功保存并发送后，立即关闭编辑窗口。
- 让该功能保持为可选增强，即使没有安装 `snacks.nvim`，插件原有功能仍可正常使用。

## 非目标

- 不打开磁盘上的真实文件进行编辑。
- 不做跨会话的草稿持久化。
- 不在 tmux 内再启动一个独立的 `nvim`。
- 不替代现有的非编辑发送命令。

## 用户体验

新增两个命令：

- `:SendToTmuxEdit`
- `:SendToTmuxEditExec`

行为如下：

1. 命令先按现有发送命令的规则解析源文本：优先取可视选区，否则取当前行。
2. 通过 `Snacks.win` 打开一个浮动编辑窗口。
3. 将解析得到的文本预填充到临时 buffer 中。
4. 用户在该窗口内正常编辑内容。
5. 当用户执行 `:w` 时，插件拦截保存动作，将整个 buffer 内容发送到 tmux；成功后关闭浮窗。
6. 如果发送失败，则保留窗口，并显示错误通知。

`SendToTmuxEdit` 只发送内容，不按 `Enter`。  
`SendToTmuxEditExec` 发送内容后再补一个 `Enter`。

## 依赖策略

`snacks.nvim` 只对新增的编辑命令是必需的。现有的目标选择和发送命令，即使没有安装它，也必须继续正常工作。

这意味着：

- 如果系统中没有 `snacks.nvim`，那么 `:SendToTmuxEdit` 和 `:SendToTmuxEditExec` 需要给出通知并中止执行。
- 插件文档里已有的最低 Neovim 版本要求可以继续保留给基础功能使用；但新增的编辑工作流必须明确说明依赖一个可用的 `snacks.nvim` 配置。由于 `snacks.nvim` 文档声明要求 `Neovim >= 0.9.4`，这也会成为该编辑工作流的实际最低版本要求。

## 窗口与 Buffer 设计

编辑界面使用一个临时 buffer，并通过 `Snacks.win` 显示在浮动窗口中。

buffer 属性：

- `buftype = "acwrite"`
- `bufhidden = "wipe"`
- `swapfile = false`
- `modifiable = true`
- `filetype` 在可用时继承当前 buffer

这样可以保持工作流轻量，不需要创建临时文件，也不用处理磁盘清理、文件写入自动命令重复触发发送等问题。

## 命令与内部 API 结构

当前代码把“解析源文本”和“发送实际内容”混在同一个本地流程里。这个功能需要把两者拆开，这样新的编辑器路径才能复用同一套发送逻辑。

内部结构建议调整为：

- 保留 `get_text_to_send(opts)`，继续负责提取当前行或可视选区
- 新增一个专门负责发送指定内容的内部函数，例如 `send_payload(text, send_enter)`
- 保持 `send_to_tmux(opts)` 和 `send_to_tmux_exec(opts)` 作为轻量包装
- 为编辑工作流增加对应的包装函数

`send_payload` 应统一负责：

- 检查 tmux 是否已安装
- 检查是否已经选择目标 pane
- 重新验证目标 pane 是否仍然存在
- 调用 `tmux.send_to_tmux`
- 处理成功与失败通知

这样可以避免普通发送与编辑后发送之间出现逻辑分叉。

## 保存拦截

临时编辑 buffer 上会挂一个 buffer-local 的 `BufWriteCmd` 自动命令。

当用户在编辑 buffer 中执行 `:w` 时：

1. 读取整个 buffer 的所有行。
2. 用 `\n` 连接为完整文本。
3. 根据当前命令对应的 `send_enter` 模式，调用共享的发送逻辑。
4. 如果发送成功：
   - 将 buffer 标记为未修改
   - 关闭浮动窗口
   - wipe 掉该 buffer
5. 如果发送失败：
   - 保留窗口
   - 保留 buffer 内容
   - 通过 `vim.notify` 报错

## 失败处理

编辑命令在下列情况中必须尽早失败，并给出明确反馈：

- tmux 未安装
- 还没有选择目标 pane
- 已选择的目标 pane 已不存在
- 没有可发送的源文本
- 未安装 `snacks.nvim`，或者它没有暴露所需的窗口 API

如果编辑窗口已经打开，但发送阶段失败，则必须保留当前内容，确保用户可以继续修改或重试，而不会丢失文本。

## 测试策略

在现有的 plenary 测试套件中补充聚焦的单元测试。

覆盖范围：

- 打开编辑模式时，会把预期文本放进临时 buffer
- `SendToTmuxEdit` 对应 `send_enter = false`
- `SendToTmuxEditExec` 对应 `send_enter = true`
- 保存编辑 buffer 时会调用共享发送逻辑
- 保存成功后会关闭窗口并清理临时 buffer 状态
- 保存失败时窗口保持打开
- 缺少 `snacks.nvim` 时会给出可操作的错误提示

测试应 stub 掉 snacks 的窗口构造，而不是依赖真实 UI。

## 文档更新

需要更新用户文档，覆盖：

- 两个新命令
- 保存即发送的工作流
- `snacks.nvim` 的可选依赖说明
- 编辑工作流的实际 Neovim 版本要求
- 如果 README 继续维护按键映射示例，也应补充对应示例

## 实现说明

第一版实现应保持收敛：

- 不做持久化草稿
- 不做“发送成功后是否关闭”的可配置项
- 不提供 tmux popup 作为回退方案
- 不增加除正常编辑和 `:w` 之外的额外窗口动作

这样更符合插件当前较小的功能面，也能减少发送逻辑里的分支复杂度。
