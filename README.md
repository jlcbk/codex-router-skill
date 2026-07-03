# codex-router-skill

> 在 **GLM（Claude Code / ZCode 默认执行层）** 和 **Codex（OpenAI 专家升级层）** 之间自动路由任务的 Skill 体系。
>
> 目标：**尽量省 Codex token**——让贵的 Codex 只做硬活，便宜且快速的 GLM 承担绝大多数任务。

---

## 这是什么

一个让你在 Claude Code / ZCode 里、按任务难度自动决定"自己用 GLM 做"还是"委托给 Codex"的 Skill 包。

设计灵感来自 [`wquguru/skills`](https://github.com/wquguru/skills) 项目的 `fable5-best-practice` skill——那是一个在 Claude 家族多模型间（Sonnet / Opus / Fable 5 / Codex）路由、用来省 Fable 5 token 的体系。本仓库把它**改造为两模型世界**：

| fable5 原版 | 本仓库 |
| --- | --- |
| Sonnet（默认执行）| **GLM**（默认执行）|
| Opus / Fable 5（升级层）| **Codex**（升级层）|
| 全部走 Claude 家族 API | Codex 通过 `codex exec` 子进程接入 |
| 钉模型子 agent | `codex exec` 包装子 agent |

抄的是**结构和判断框架**（路由表、能力打分、升级纪律、子 agent 提示词），换的是**模型阵容**和**跨软件桥接方式**。

## 为什么默认执行层是 GLM 而不是 Codex

Token 经济学：**编排层是每个任务都要付的固定成本**（读 prompt、判断、调工具、写回复）。如果 Codex 当壳，哪怕你只问"这函数干嘛的"也得烧 Codex token。要让 Codex 真省下来，它就必须是**被按需调用的专家**，不是常驻编排者。

对应 fable5 的核心原则——"用能稳定通过验收的最便宜模型，只在便宜模型漏掉具体标准时才升级"。两模型世界就是这条原则的最简形态：**GLM 是默认，Codex 是升级**。

## 三层结构

本 skill 不是一个孤立文件，而是三层联动（对应 fable5 的 `CLAUDE.md` 片段 + `SKILL.md` + `references` + 子 agent 模板）：

| 层 | 载体 | 作用 |
| --- | --- | --- |
| L0 基线 | `AGENTS.md` | 一条永远在场的"默认 GLM，硬任务才升级 Codex"铁律 |
| L1 判断 | `skills/codex-router/SKILL.md` | 详细决策框架 + 路由表，编码任务自动触发 |
| L2 矩阵 | `skills/codex-router/references/codex-routing.md` | 能力打分、成本模型、升级/降级规则、子 agent 提示词（按需加载）|
| L3 执行 | `agents/codex-engineer.md` | 真正跑 `codex exec`、隔离 Codex 冗长输出、回传精简结论 |

`Skill` 是判断层；`子 agent` 是执行层；`AGENTS.md` 是基线——三层缺一不可。

## 前置依赖

- **Claude Code / ZCode**（本仓库在它的上下文里运行）
- **Codex CLI**（被委托时通过 `codex exec` 调用），并已完成登录：
  ```bash
  codex --version          # 确认已安装
  codex login              # 或在 ~/.codex/config.toml 配 API key
  ```

## 安装

### 方式一：一键脚本（推荐）

```bash
git clone https://github.com/jlcbk/codex-router-skill.git
cd codex-router-skill
./scripts/install.sh
```

脚本会把文件软链（symlink）到 `~/.agents/skills/`、`~/.zcode/agents/`、`~/.zcode/AGENTS.md`，方便 `git pull` 升级。

### 方式二：手动

```bash
# Skill（含 references）
mkdir -p ~/.agents/skills
ln -s "$(pwd)/skills/codex-router" ~/.agents/skills/codex-router

# 子 agent
mkdir -p ~/.zcode/agents
ln -s "$(pwd)/agents/codex-engineer.md" ~/.zcode/agents/codex-engineer.md

# 基线规则——若你已有 AGENTS.md，请把内容追加进去而非覆盖
cat AGENTS.md >> ~/.zcode/AGENTS.md
```

> **Workspace 级**：若只想在某个项目里启用，把同样的结构放到 `<repo>/.agents/` 和 `<repo>/.zcode/` 下即可（深度优先，会覆盖用户级）。

## 验证

装好后开一个新会话，问一句：

> "帮我看看 src/auth.ts 这个文件能不能用 async/await 重构一下"

期望行为：
- 简单任务 → GLM 直接做，不碰 Codex
- 复杂任务 → GLM 触发 `codex-engineer` 子 agent，由 Codex 执行，回传精简结论

也可以显式触发：`/codex-router` 或输入"用不用 codex 做这个"。

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

- [`wquguru/skills`](https://github.com/wquguru/skills) 的 `fable5-best-practice` —— 本仓库直接借鉴其结构与判断框架

## License

MIT
