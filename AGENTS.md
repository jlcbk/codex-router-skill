# Model Routing Baseline

> 这是一条永远在场的基线规则。即使 `codex-router` skill 没被触发，它也成立。
>
> 安装位置（`./scripts/install.sh` 会自动追加本文件内容，不覆盖）：
> - **ZCode**：追加到 `~/.zcode/AGENTS.md`
> - **Claude Code**：追加到 `~/.claude/CLAUDE.md`

## 模型路由基线

你的默认执行模型是 **GLM**（本会话）。绝大多数任务直接做，**不要**调用 Codex。

仅当任务同时满足以下条件之一时，才委托给 Codex（执行后端见下方"执行层"）：

- 涉及多文件重构、架构决策、或算法设计，且 GLM 单次实现质量明显不够
- 需要一个独立模型家族的"第二意见"来交叉验证高风险改动
- GLM 已经尝试过但漏掉了明确的验收标准

**委托 Codex 是有成本的**（token 贵、有延迟、有上下文隔离开销）。默认不委托。

当不确定时，**先用 GLM 做一版，再决定是否升级**——而不是反过来。

## 执行层（委托 Codex 的具体方式）

判断要升级后，按你的运行环境选执行后端：

| 环境 | 执行后端 | 触发方式 |
| --- | --- | --- |
| ZCode / 任意装了 Codex CLI 的环境 | `codex-engineer` 子 agent（直接 `codex exec`） | 委托给 `codex-engineer` 子 agent |
| Claude Code（推荐） | OpenAI codex plugin | 主会话调用 `/codex:rescue`（实现）或 `/codex:review` / `/codex:adversarial-review`（第二意见） |

> Claude Code 下若未安装 OpenAI plugin，`codex-engineer` 子 agent（直接 exec）仍可作为 fallback。
> 安装 plugin：`/plugin marketplace add openai/codex-plugin-cc` → `/plugin install codex@openai-codex` → `/reload-plugins` → `/codex:setup`。

详细决策框架与路由表见 `codex-router` skill。
