# Windows 沙箱 runner：排查记录与现状

> 本文是详细排查过程。README 里只放当前状态的一句话结论 + 指向这里。
> 仅影响 **Windows**。macOS / Linux 不受影响。

## 现状（TL;DR）

- 在 Windows 上，Codex 的沙箱命令执行器在 **Claude Code 子进程 / 非交互上下文**里会超时：
  ```
  windows sandbox: timed out after 15000ms connecting runner pipe-in
  ```
  这是 OpenAI 的已知 bug [openai/codex#30839](https://github.com/openai/codex/issues/30839)。
- 因此**带 `-s read-only` / `-s workspace-write` 的调用**（包括 OpenAI codex plugin 后端，以及 `codex-engineer` 的默认 `-s` 写法）在 Windows 的 Claude Code 里**暂不可用**。
- **可用解法**：让 Codex 调用**绕过 runner**——全局 `~/.codex/config.toml` 设 `sandbox_mode = "danger-full-access"`，`codex-engineer` 调用时**省略 `-s`** 继承该设置；只读意图改由任务文本约束。
- **UAC 不能修复**（见下）。沙箱早已装好，失败是会话上下文 bug。
- **后续**：#30839 修复后，`-s` 模式与 plugin 后端在 Windows 上即按设计可用，无需额外授权。

## 机制

Codex 父进程创建命名管道 `\\.\pipe\codex-runner-<hash>-in/out`，把 `codex-command-runner.exe`
作为专用沙箱用户（`CodexSandboxOffline` / `CodexSandboxOnline`）拉起，并等待它**回连**该管道。
回连能否成功取决于父进程所在的**会话/窗口站类型**：交互式桌面会话能连，SSH / git-bash pty /
分离的 daemon 子进程连不上 → 15s 超时。

架构细节可参考社区对 Codex Windows sandbox 的拆解（restricted token + 合成 SID + 专用沙箱用户 +
WFP/防火墙规则）；openai/codex#30839 的报告者指出：**同一台机器本地/RDP 交互登录时沙箱正常，
SSH 会话下连 `Get-Location` 都超时**。

## 为什么 UAC 不是解药

排查确认沙箱**早已完全装好**：

- `~/.codex/.sandbox-bin/` 里有完整的一堆 `codex-command-runner-*.exe`（多版本）；
- `~/.codex/.sandbox/setup_marker.json` 存在（setup 已完成）；
- `~/.codex/.sandbox-secrets/sandbox_users.json` 存在（沙箱用户 DPAPI 凭据已存）；
- `CodexSandboxUsers` 组存在，成员 `CodexSandboxOffline` / `Online` 都在。

也就是说，**创建沙箱用户那次需要管理员的 setup 早就成功跑过**——UAC 已经给过了。当前失败是
*会话上下文* bug，不是权限问题：再弹一次 UAC、再把进程提权，都改变不了"子进程连不回父进程的管道"。

## 验证过程

- `codex exec`（**不带 `-s`**，继承全局 `danger-full-access`）→ ✅ 184ms 正常返回（绕过 runner）。
- `codex exec -s read-only` → ❌ 15s 超时。
- `codex exec -s workspace-write` → ❌ 15s 超时。
- 从**原生 PowerShell**（而非 git-bash）跑 `-s read-only` → ❌ 仍是同一个超时
  （即不是 pty/控制台类型的问题，是 Claude Code 子进程这条路径整体不通）。

结论：在 Claude Code 执行上下文里，凡带 `-s` 的 Codex 调用全死；唯一能跑的是 `danger-full-access`（无 `-s`）。

## 当前 Windows 解法

1. 全局 `~/.codex/config.toml` 设 `sandbox_mode = "danger-full-access"`（很多 Windows 用户本就这么设）。
2. `codex-engineer` 调用时省略 `-s`，继承该全局设置；`agents/codex-engineer.md` 已附这条 Windows 注意。
3. review/只读的意图改由任务文本约束（"不要修改任何文件，仅评审"）。

代价：失去 `-s` 的沙箱隔离（已接受 `danger-full-access` 的取舍），以及 plugin 的后台/resume/transfer
（在 Windows 的 Claude Code 里本来就拿不到）。想要那些功能，可在**独立交互式** PowerShell 窗口里
直接跑 `codex` TUI（#30839 报告者证实本地交互登录时沙箱正常）。

## 后续

跟踪 [openai/codex#30839](https://github.com/openai/codex/issues/30839)。OpenAI 让 runner 在非交互会话下
能正常回连后，`-s` 模式与 plugin 后端在 Windows 上即可按设计使用。
