# Codex Routing Reference

> 本文件是 `codex-router` skill 的详细路由矩阵。设计工作流、写委托提示词、
> 或调路由边界时读它。这是路由逻辑的真正载体，`SKILL.md` 只是入口。

## Contents

- Capability Profile
- Cost Model
- Token And Context Hygiene
- Routing Rules
- Upgrade Rules
- Downgrade Rules
- Subagent Patterns
- Anti-Patterns

## Capability Profile

分数是本地默认值，不是普世真理。定价、配额、延迟或观察到的模型行为变化时重新打分。
`Cost efficiency` 越高 = 同样可接受产出越便宜。

| 模型 | Cost efficiency | Acceptance reliability | Taste | Throughput | 短标签 |
| --- | ---: | ---: | ---: | ---: | --- |
| GLM | 9 | 6 | 6 | 9 | 默认执行层 |
| Codex | 4 | 9 | 8 | 6 | 专家升级层 |

定义：

- `Cost efficiency`：本部署的实际边际成本（含订阅、配额、缓存折扣、批处理、限速）
- `Acceptance reliability`：不靠昂贵重试或人工监督就能达到质量标准的概率
- `Taste`：UI/UX、文案、API 设计、架构形态、代码可维护性的判断力
- `Throughput`：适合大量工具调用、高 token 上下文收集、常规执行的程度

## Cost Model

委托 Codex 是有成本的。委托前先估算：

```text
expected_cost =
  uncached_input_tokens * input_rate
  + cache_write_tokens * cache_write_rate
  + cache_hit_tokens * cache_hit_rate
  + output_tokens * output_rate
  + expected_retry_cost
  + expected_subagent_cost
```

成本规则：

- **优化"可接受产出的总成本"，不是单次调用价格。** 一个便宜模型循环三次可能比
  一次强模型调用更贵。但如果 GLM 一次就能过验收，那就根本不该上 Codex。
- 把稳定前缀放可缓存位置（系统规则、仓库指令、工具 schema、API 文档）。
  挥发性任务细节放后面。
- **委托前 pilot。** 先让 GLM 做一小片代表样本，看结果质量和成本，再决定是否扩大。
- **Codex 不是"免费"的。** 即便走订阅也有用量上限——后台 review gate、循环任务
  会很快耗光配额。
- 委托前明确：预算上限、最大尝试次数、停止条件。强提示词既说"做什么"也说"何时停"。
- 跟踪**总循环成本**：编排 token + worker token + verifier token + 工具结果 token
  + 失败尝试 + 最终综合——全都算。
- 当 harness 提供按 skill / model / subagent / workflow / MCP 的用量报表时，
  定期 review。停掉或缩小那些"消耗预算但不改变可接受产出"的 agent。

## Token And Context Hygiene

任何多 agent 或长程工作流都用这个 checklist：

- 从一个简短的**设计包**开始：目标、约束、 owned paths、验收标准、相关文件、
  验证命令、审批门。
- **给 Codex 设计包 + 精确 artifact，不是整个会话。** Codex 不该看到你和用户的
  全部来回。
- 让 explorer（GLM）返回：事实 + 路径 + 命令输出 + 矛盾点 + 未知项。避免叙事性
  transcript。
- 让 executor（GLM 或 Codex）返回：改了哪些文件、验收运行及结果、blocker、
  需要 review 的判断点。
- **Codex 的上下文只放决策、风险、证据包、当前状态。** 不要把原始仓库 dump
  丢给 Codex，除非证据本身有争议。
- 在 API 或 harness 支持 task budget 的地方用它。预算覆盖整个 agent 循环：思考、
  工具调用、工具结果、最终输出。
- 清理不再活跃的庞大旧工具结果，或 compact 会话。缓存降低价格，但缓存 token
  仍占用上下文窗口。
- **独立验证放在 fresh context 里。** verifier 应该看到目标、验收标准、diff/artifact、
  证据——不是执行者的自我辩护。
- 重复性变换（计数、格式化、抽取）优先用确定性工具/脚本。模型该判断或适配，
  不该模拟 grep。

## Routing Rules

这些是默认值，不是天花板：

- **用 GLM** 做代码探索、批量读取、grep 式调查、日志分诊、确定性变换、按 clear
  spec 的机械实现。
- **用 Codex** 做模糊架构决策、高风险 review、深度 pre-mortem、跨冲突证据综合、
  最终仲裁。或任何"不同模型家族视角有 material 价值"的场景。
- **不要让 Codex 做原始发现。** 先让 GLM 收集并压缩证据，再把压缩包交给 Codex。
- **路由到能通过验收的最便宜模型。** 对交付物，质量是 gate、成本是 gate 后的优化器。
- 当不确定时**先用 GLM 做一版**。一个失败尝试的成本通常远低于"直接上 Codex 但
  其实 GLM 就够"的机会成本。
- **升级一个 worker**（GLM→Codex）发生在：GLM 的重试消耗的预算已经超过一次更强
  实现的预期成本，或细微代码质量确实重要。
- **只升级需要升级的那部分。** Codex 可以决定方案、仲裁冲突、跑 pre-mortem，
  然后把执行**降级**回去。

## Upgrade Rules

用户给了 standing budget 或自主权时，用自动升级：

- **GLM → Codex**：当执行大体正确，但 taste、API 形态、措辞、可维护性、review
  判断不够好。
- **GLM → Codex**：当失败不是 taste 而是**核心推理**——模糊规划、无法在脑中
  hold 住整个系统、多文件耦合分析。
- **Claude-only → Codex**：当一个编码决策会受益于独立模型家族、本地 Codex 工具、
  或一次 fresh rescue 尝试。

**升级时必须记录**（写进 routing log，防止下次犯同样错判）：

```text
- 什么模型尝试了任务
- 漏掉了哪个验收标准
- 什么证据显示这个漏判
- 更强模型该决定或重做什么
- 允许的额外预算或次数上限
```

## Downgrade Rules

硬决策做完后降级，把执行交回去：

- **Codex → GLM**：Codex 给出架构/方案/根因后，机械实现、测试生成、格式化、
  按清晰 spec 的探索交回 GLM。
- 只有当 Codex 的执行质量**也**明显优于 GLM、且差异值得 token 成本时，才让 Codex
  一路执行到底。

降级不是降级模型能力，是**降级 token 消耗**。

## Subagent Patterns

### GLM Explorer

```text
Use GLM for this subtask.

Goal:
为 [问题] 收集证据。

Scope:
只读 [路径/系统]。不修改文件、不做外部改动。

Output:
- 关键事实 + 文件路径 / 命令输出 / 源码引用。
- 未知项和矛盾点。
- 适合 Codex review 的 token-light 证据包。
- 推荐的下一个模型（如果这看起来比预期难）。
```

### GLM Executor

```text
Use GLM for this subtask. 当编排者说需要更强实现判断、或 GLM 已经失败过同一个
验收标准时，改用 Codex（见下）。

Goal:
在 [owned paths] 内实现 [clear spec]。

Constraints:
遵循现有模式。避免大范围重构。spec 模糊或需要架构判断时停下。

Output:
- 改了哪些文件。
- 验收运行及结果。
- 需要 Codex review 的判断点。
- 预估的后续成本风险：低 / 中 / 高。
- 保持精简，不包含完整推理 transcript。
```

### Codex Peer Engineer

```text
Use Codex for this subtask.

Availability gate:
确认 Codex CLI 已安装并登录（`codex --version` + `codex login`）。
如果没装好，不要假装这个 peer 存在；回退到 GLM + fresh-context verifier，
并把这次 run 标记为 GLM-only。

Goal:
对 [问题 / 设计 / 改动] 给出独立 senior-engineering pass。

Input:
用和 GLM executor 同样的目标、约束、验收标准、压缩证据包。
不要读 GLM 的答案或私有推理。

Output:
- 推荐的路径或具体 patch plan。
- 风险、缺失证据、验证步骤。
- 你的结论与所给证据在哪里一致或冲突。
```

调用 Codex 的命令形态——按执行后端二选一：

**后端 A：`codex-engineer` 子 agent / 直接 `codex exec`**（ZCode、或 Claude Code 未装
OpenAI plugin 时的 fallback）：

```bash
# read-only review（第二意见、方案评审）
codex exec --json --ephemeral -s read-only -C "$(pwd)" \
  -o /tmp/codex-result.txt "$(cat /tmp/codex-task.md)"

# 实现（多文件重构、rescue）
codex exec --json --ephemeral -s workspace-write -C "$(pwd)" \
  -o /tmp/codex-result.txt "$(cat /tmp/codex-task.md)"
```

**后端 B：OpenAI codex plugin**（Claude Code 推荐；后台任务、resume、session transfer、
稳建的 review）——由主会话调用 slash 命令，规格包作为请求正文：

```text
# 实现 / rescue（默认 write-capable）
/codex:rescue --background <规格包正文>
/codex:rescue --resume apply the top fix from the last run

# 第二意见 / 方案评审（read-only）
/codex:review                 # 当前未提交改动
/codex:review --base main     # 相对 base 分支
/codex:adversarial-review challenge whether this caching/retry design is right

# 取回后台结果
/codex:status
/codex:result
```

两种后端的语义对应：`workspace-write` ≈ `/codex:rescue`；`read-only` ≈ `/codex:review`
或 `/codex:adversarial-review`。优先用后端 B 的 `--background` + `/codex:result` 按需取回，
天然隔离 Codex 长输出，替代后端 A 手写的"读结果文件 + 回传精简结论"。

### Fable-style Orchestrator（适配为 GLM-led）

```text
Use GLM as lead orchestrator.

Before delegation:
写一个紧凑设计包：目标、约束、架构或 patch plan、invariants、相关文件、
验收标准、验证命令。

Delegation:
- 证据收集 / 机械实现：GLM 自己做或 GLM executor 子agent。
- 独立 senior perspective / rescue / 高风险并行推理：委托 codex-engineer。

Rule:
高风险决策时，让 GLM 和 Codex 在同一问题上并行工作，互相看不到对方答案。
然后由你（编排者）综合两边的输出，按证据裁定，再把执行交给能通过验收的最便宜 agent。
如果 Codex 不可用，用 GLM + fresh-context verifier，标记为 GLM-only。
```

## Anti-Patterns

- 任务还没框清楚、证据还没收集就让 Codex 上场。
- 让 Codex 读 GLM 本可以先压缩的大段代码区域。
- 让子 agent 返回完整推理 transcript 而不是精简结论、证据、blocker。
- 让 GLM 做最终架构决策，"因为它已经做了实现"——实现权不等于决策权。
- **把 Codex 当橡皮图章 reviewer**，而不是有独立判断的同侪。Codex 的价值在于
  它会形成独立的、不同的观点。
- **默认任何任务都走 Codex**——这直接违背省 Codex token 的核心目标。
- 把路由表当预算上限。它是默认地图，不是天花板。
- **升级后不记录**"漏了什么、Codex 该改什么"——下次还会犯同样的错判。
- 用这套多 agent 模式做简单 CRUD 或一次性编辑，编排开销比节省的多。
