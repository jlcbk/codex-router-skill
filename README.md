# codex-router-skill

> 在 **GLM（Claude Code / ZCode 默认执行层）** 和 **Codex（OpenAI 专家升级层）** 之间自动路由任务的 Skill 体系。
>
> 目标：**尽量省 Codex token**——让贵的 Codex 只做硬活，便宜且快速的 GLM 承担绝大多数任务。

---

## 这是什么

一个让你在 Claude Code / ZCode 里、按任务难度自动决定"自己用 GLM 做"还是"委托给 Codex"的 Skill 包。

它提供一个**两模型世界**的路由体系：

- **GLM** 是默认执行层——便宜、快速，承担绝大多数任务。
- **Codex** 是专家升级层——贵、慢、稀缺，只在硬任务上按需调用。
- Codex 通过 `codex exec`（直接子进程）或 OpenAI codex plugin（`/codex:rescue`、`/codex:review`）接入，按运行环境切换。

核心是一套**结构和判断框架**：路由表、能力打分、成本模型、升级/降级纪律、规格化的委托提示词、以及隔离 Codex 冗长输出的子 agent。

## 为什么默认执行层是 GLM 而不是 Codex

Token 经济学：**编排层是每个任务都要付的固定成本**（读 prompt、判断、调工具、写回复）。如果 Codex 当壳，哪怕你只问"这函数干嘛的"也得烧 Codex token。要让 Codex 真省下来，它就必须是**被按需调用的专家**，不是常驻编排者。

原则一句话：**用能稳定通过验收的最便宜模型，只在便宜模型漏掉具体标准时才升级。** 两模型世界就是这条原则的最简形态：**GLM 是默认，Codex 是升级**。

## 三层结构

本 skill 不是一个孤立文件，而是三层联动：

| 层 | 载体 | 作用 |
| --- | --- | --- |
| L0 基线 | `AGENTS.md` | 一条永远在场的"默认 GLM，硬任务才升级 Codex"铁律 |
| L1 判断 | `skills/codex-router/SKILL.md` | 详细决策框架 + 路由表，编码任务自动触发 |
| L2 矩阵 | `skills/codex-router/references/codex-routing.md` | 能力打分、成本模型、升级/降级规则、子 agent 提示词（按需加载）|
| L3 执行 | `agents/codex-engineer.md` + OpenAI codex plugin | 真正跑 Codex：直接 `codex exec`（ZCode / fallback）或 OpenAI plugin 的 `/codex:rescue` `/codex:review`（Claude Code）|

`Skill` 是判断层；执行后端是执行层；`AGENTS.md` 是基线——三层缺一不可。
**判断层与执行层解耦**：路由逻辑（该不该升级）对所有环境一致，只有"怎么调 Codex"按环境切换后端。

## 前置依赖

- **Claude Code 或 ZCode**（本仓库在它的上下文里运行）
- **Codex CLI**，并已完成登录：
  ```bash
  codex --version          # 确认已安装
  codex login              # 或在 ~/.codex/config.toml 配 API key
  ```
- **（Claude Code 推荐）OpenAI codex plugin** —— 提供更稳的执行后端（后台任务、resume、session transfer、adversarial review）：
  ```text
  /plugin marketplace add openai/codex-plugin-cc
  /plugin install codex@openai-codex
  /reload-plugins
  /codex:setup
  ```
  不装也能用：仓库自带的 `codex-engineer` 子 agent 会直接 `codex exec`，作为 fallback。

## 安装

仓库同时支持两个目标环境，判断层（skill + 基线）两者通用，只有安装路径不同：

| 目标 | skill 路径 | 子 agent 路径 | 基线文件 |
| --- | --- | --- | --- |
| **ZCode**（默认） | `~/.agents/skills/` | `~/.zcode/agents/` | `~/.zcode/AGENTS.md` |
| **Claude Code** | `~/.claude/skills/` | `~/.claude/agents/` | `~/.claude/CLAUDE.md` |

### 方式一：一键脚本（推荐）

```bash
git clone https://github.com/jlcbk/codex-router-skill.git
cd codex-router-skill

# ZCode（默认）
./scripts/install.sh
# 或 Claude Code
./scripts/install.sh --target claude
```

脚本默认用 symlink（方便 `git pull` 升级）。在 Windows（git bash / MSYS）上会自动改用 copy，
因为 symlink 通常需要开发者模式或管理员权限。可用 `--symlink` / `--copy` 强制。
基线规则以 marker 形式**追加**进你的 `AGENTS.md` / `CLAUDE.md`，不覆盖已有内容。

### 方式二：手动

> **Windows（git bash / MSYS）**：建议直接用 `scripts/install.sh`（自动 copy）。
> 若手动操作，把下面的 `ln -s` 换成 `cp -r`（skill 目录）/ `cp`（agent 文件），
> 因为 Windows 的 symlink 通常需要开发者模式或管理员权限。

**ZCode：**

```bash
mkdir -p ~/.agents/skills ~/.zcode/agents
ln -s "$(pwd)/skills/codex-router"      ~/.agents/skills/codex-router
ln -s "$(pwd)/agents/codex-engineer.md" ~/.zcode/agents/codex-engineer.md
# 基线：带 marker 幂等追加（重复执行不会重复写入）
grep -q '<!-- codex-router-skill baseline -->' ~/.zcode/AGENTS.md 2>/dev/null \
  || cat AGENTS.md >> ~/.zcode/AGENTS.md
```

**Claude Code：**

```bash
mkdir -p ~/.claude/skills ~/.claude/agents
ln -s "$(pwd)/skills/codex-router"      ~/.claude/skills/codex-router
ln -s "$(pwd)/agents/codex-engineer.md" ~/.claude/agents/codex-engineer.md
grep -q '<!-- codex-router-skill baseline -->' ~/.claude/CLAUDE.md 2>/dev/null \
  || cat AGENTS.md >> ~/.claude/CLAUDE.md
```

> **Workspace 级**：若只想在某个项目里启用，把同样的结构放到 `<repo>/.claude/`（Claude Code）或 `<repo>/.agents/` + `<repo>/.zcode/`（ZCode）下即可（深度优先，会覆盖用户级）。

### 装好执行后端（Claude Code）

判断层装好后，再装执行后端（见上"前置依赖"里的 plugin 四行命令）。然后路由器升级 Codex 时
会走 `/codex:rescue` `/codex:review`，而不是裸 `codex exec`。

## 验证

装好后开一个新会话，问一句：

> "帮我看看 src/auth.ts 这个文件能不能用 async/await 重构一下"

期望行为：
- 简单任务 → GLM 直接做，不碰 Codex
- 复杂任务 → GLM 判断升级，按执行后端交给 Codex：
  - ZCode / fallback → 触发 `codex-engineer` 子 agent（`codex exec`），回传精简结论
  - Claude Code（装了 plugin）→ 主会话调用 `/codex:rescue` 或 `/codex:review`

也可以显式触发：`/codex-router` 或输入"用不用 codex 做这个"。

## 已知限制：Windows 上的沙箱 runner

> 这一节只影响 **Windows**。macOS / Linux 不受影响。

在 Windows 上，Codex 的沙箱命令执行器（`[windows] sandbox = "elevated"`）在**非交互式 / Claude Code 子进程**上下文里会超时：

```
windows sandbox: timed out after 15000ms connecting runner pipe-in
```

机制：codex 父进程建命名管道 `\\.\pipe\codex-runner-<hash>-in/out`，把 `codex-command-runner.exe`
作为专用沙箱用户（`CodexSandboxOffline` / `Online`）拉起并**回连**该管道；回连在某些会话上下文下
15s 连不上 → 超时。这是 OpenAI 的已知 bug [openai/codex#30839](https://github.com/openai/codex/issues/30839)
（同一台机器本地/RDP 交互登录时正常，SSH / 分离子进程下连 `Get-Location` 都超时）。

**影响范围**：凡带 `-s read-only` / `-s workspace-write` 的调用都中招——这同时命中：

- **OpenAI codex plugin（Claude Code 执行后端 B）**：companion 强制 `--write`/read-only（带沙箱），所以在 Windows 的 Claude Code 里**暂不可用**。
- **`codex-engineer` 子 agent 的 `-s` 写法**：默认命令（`-s workspace-write`/`-s read-only`）同样超时。

**关键：重新授予 UAC 不能修复**。沙箱在首次安装时就已经配好了（runner 二进制、`setup_marker.json`、
`CodexSandboxUsers` 组与两个沙箱用户、DPAPI 凭据都在），创建用户那次需要的 UAC 早已给过。当前失败是
*会话上下文* bug，不是权限问题——提权改变不了"子进程连不回管道"。

**Windows 上的可用解法（现在）**：让 Codex 调用**绕过 runner**——

- 全局 `~/.codex/config.toml` 设 `sandbox_mode = "danger-full-access"`（很多 Windows 用户本就这么设）；
- `codex-engineer` 调用时**省略 `-s`**，继承该全局设置（不走 runner，所以不超时）；只读意图改由任务文本
  约束（"不要修改任何文件，仅评审"）。`agents/codex-engineer.md` 已附这条 Windows 注意。

代价：失去 `-s` 的沙箱隔离（但你已接受 `danger-full-access` 的取舍），以及 plugin 的后台/resume/transfer
（在 Windows 的 Claude Code 里本来就拿不到）。

**后续会修**：跟踪 [openai/codex#30839](https://github.com/openai/codex/issues/30839)。一旦 OpenAI 让 runner
在非交互会话下能正常回连，`-s` 模式与 plugin 后端在 Windows 上即可按设计使用，无需任何额外授权。

## 路由表速览

| 任务特征 | 路由到 |
| --- | --- |
| 单行修改、查询、解释、格式化、grep | GLM |
| 按 clear spec 写样板代码、加测试 | GLM |
| 单文件中等复杂度实现 | GLM（先试，按验收标准决定升级）|
| 多文件重构、跨模块改动 | **Codex** |
| 架构决策、技术选型、tradeoff 判断 | **Codex** |
| GLM 已试过但漏掉验收标准的疑难 bug | **Codex** |
| 高风险改动的独立第二意见 | **Codex（read-only review）** |

完整版见 [`skills/codex-router/references/codex-routing.md`](skills/codex-router/references/codex-routing.md)。

## 校准

路由表是"默认地图，不是天花板"。建议：

1. 在 `codex-engineer` 里开启路由日志（每次委托记一条：任务摘要、路由理由、Codex 花的 token、结果质量）
2. 跑两周后回看日志——你会发现一开始要么过度委托（费钱）、要么委托不足（GLM 翻车）
3. 据此调整 `references/codex-routing.md` 的边界

## 致谢

- 本仓库的多模型路由结构（路由表 + 能力打分 + 升级纪律 + 子 agent 提示词）受益于社区里关于"按难度在模型间路由、省昂贵模型 token"这一思路的公开实践。

## License

MIT
