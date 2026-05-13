# SendToTmux 编辑后发送 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `send-to-tmux.nvim` 增加基于 `snacks.nvim` 的编辑后发送流程，在浮窗中编辑内容，保存时自动发送到目标 tmux pane，并在成功后关闭窗口。

**Architecture:** 保留现有“取文本”和“发 tmux”两层职责，但把发送能力提炼成共享的内部路径。新增两个编辑命令，通过 `Snacks.win` 承载一个临时 `acwrite` buffer，并在 `BufWriteCmd` 中复用共享发送逻辑。测试继续沿用现有 plenary 单元测试，通过 stub `Snacks.win` 和 Neovim API 验证行为，不依赖真实 UI。

**Tech Stack:** Lua, Neovim API, plenary.nvim, snacks.nvim

---

### Task 1: 拆分共享发送路径

**Files:**
- Modify: `lua/send_to_tmux.lua`
- Test: `tests/send_to_tmux_spec.lua`

- [ ] **Step 1: 写失败测试，证明普通发送与编辑发送都会走统一发送路径**

在 `tests/send_to_tmux_spec.lua` 中新增针对共享发送函数行为的外层测试，验证：
- `SendToTmux` 仍然发送当前行
- 未来的编辑命令能把显式文本传入同一发送路径

- [ ] **Step 2: 运行目标测试确认失败**

Run: `make test TEST_FILE=tests/send_to_tmux_spec.lua`
Expected: FAIL，提示缺少编辑命令或共享发送入口

- [ ] **Step 3: 以最小改动实现共享发送路径**

在 `lua/send_to_tmux.lua` 中：
- 抽出一个内部 `send_payload(text, send_enter)` 函数
- 让现有 `send_to_tmux` / `send_to_tmux_exec` 仅负责取文本后调用它

- [ ] **Step 4: 再跑目标测试确认通过**

Run: `make test TEST_FILE=tests/send_to_tmux_spec.lua`
Expected: PASS

- [ ] **Step 5: 提交本任务**

```bash
git add lua/send_to_tmux.lua tests/send_to_tmux_spec.lua
git commit -m "refactor: share tmux send path"
```

### Task 2: 增加 Snacks 编辑浮窗命令

**Files:**
- Modify: `lua/send_to_tmux.lua`
- Modify: `plugin/send_to_tmux.lua`
- Test: `tests/send_to_tmux_spec.lua`

- [ ] **Step 1: 写失败测试，覆盖编辑命令与参数映射**

新增测试验证：
- `SendToTmuxEdit` 会打开编辑窗口
- `SendToTmuxEditExec` 会以 `send_enter = true` 运行
- 未安装 `snacks.nvim` 时会报错

- [ ] **Step 2: 运行目标测试确认失败**

Run: `make test TEST_FILE=tests/send_to_tmux_spec.lua`
Expected: FAIL，提示缺少编辑命令或缺少 snacks 集成

- [ ] **Step 3: 实现最小编辑命令**

在 `lua/send_to_tmux.lua` 中：
- 新增编辑命令入口
- 解析文本
- 检查 `Snacks.win`
- 创建临时 buffer 和浮窗

在 `plugin/send_to_tmux.lua` 中：
- 注册 `SendToTmuxEdit`
- 注册 `SendToTmuxEditExec`

- [ ] **Step 4: 再跑目标测试确认通过**

Run: `make test TEST_FILE=tests/send_to_tmux_spec.lua`
Expected: PASS

- [ ] **Step 5: 提交本任务**

```bash
git add lua/send_to_tmux.lua plugin/send_to_tmux.lua tests/send_to_tmux_spec.lua
git commit -m "feat: add edit commands for send-to-tmux"
```

### Task 3: 增加保存即发送并关闭逻辑

**Files:**
- Modify: `lua/send_to_tmux.lua`
- Test: `tests/send_to_tmux_spec.lua`

- [ ] **Step 1: 写失败测试，覆盖 `BufWriteCmd` 行为**

新增测试验证：
- 保存编辑 buffer 时读取全文并发送
- 成功时关闭窗口并清理 buffer 状态
- 失败时保留窗口

- [ ] **Step 2: 运行目标测试确认失败**

Run: `make test TEST_FILE=tests/send_to_tmux_spec.lua`
Expected: FAIL，提示未绑定保存钩子或行为不符合预期

- [ ] **Step 3: 实现最小保存拦截**

在 `lua/send_to_tmux.lua` 中：
- 为临时 buffer 绑定 `BufWriteCmd`
- 保存时拼接全部行后复用 `send_payload`
- 成功时关闭并 wipe
- 失败时保持编辑状态

- [ ] **Step 4: 再跑目标测试确认通过**

Run: `make test TEST_FILE=tests/send_to_tmux_spec.lua`
Expected: PASS

- [ ] **Step 5: 提交本任务**

```bash
git add lua/send_to_tmux.lua tests/send_to_tmux_spec.lua
git commit -m "feat: send edited text on save"
```

### Task 4: 更新 README 与帮助文档

**Files:**
- Modify: `README.md`
- Modify: `doc/send-to-tmux.txt`

- [ ] **Step 1: 写出文档变更清单**

列出需要补充的内容：
- 新命令
- 保存即发送行为
- `snacks.nvim` 依赖说明
- Neovim 版本说明

- [ ] **Step 2: 更新 README 与帮助文档**

将新的编辑工作流写入 `README.md` 和 `doc/send-to-tmux.txt`，保持现有文档风格。

- [ ] **Step 3: 自查文档与实现是否一致**

检查命令名、依赖说明、行为描述与实现完全一致。

- [ ] **Step 4: 提交本任务**

```bash
git add README.md doc/send-to-tmux.txt
git commit -m "docs: describe edit-before-send workflow"
```

### Task 5: 完整验证

**Files:**
- Modify: `tests/send_to_tmux_spec.lua`（如果验证中发现遗漏）

- [ ] **Step 1: 跑目标测试**

Run: `make test TEST_FILE=tests/send_to_tmux_spec.lua`
Expected: PASS

- [ ] **Step 2: 跑完整测试集**

Run: `make test`
Expected: PASS

- [ ] **Step 3: 检查工作树**

Run: `git status --short`
Expected: 只包含本次任务相关改动，以及任何预先存在的未提交改动

- [ ] **Step 4: 汇总验证结果**

记录：
- 跑了哪些命令
- 哪些测试通过
- 是否存在未解决风险
