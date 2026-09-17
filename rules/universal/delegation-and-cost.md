# Delegation and cost, which model tier does expensive reading

A skill that gathers bulk data inline runs that gathering on whatever model the session is using, usually the most expensive one. Nothing fails when it does: the answer is right, no check errors, and the cost is invisible. This rule governs **where bulk retrieval runs**.

## The mechanism

Two kinds of bulk read behave completely differently, and the difference is not visible from the tool names:

| Read type | Where the output lands | Cost to the caller |
|---|---|---|
| Shell tool (`gh`, `git`, `curl`, `jq`) | Can be redirected to a file | Near zero, the caller sees a line count |
| MCP tool | The calling model's context, in full | Proportional to total response size, unavoidable |

A skill can pull thousands of records through `<cmd> > index.json` for almost nothing and still be ruined by a few hundred MCP reads returning the same information.

Worse, **response size is not always under the caller's control**. Some MCP servers ignore field-selection parameters and return the full record, including long free-text fields, even when the request asks for one field. Assume a response is unbounded unless you have verified otherwise.

## The rules

1. **Prefer a shell tool with file redirection** for any bulk read where one exists. Post-process the file. Report the count, not the contents.

2. **Delegate to a cheap-model subagent** when a check issues more than a handful of MCP calls, or when any MCP response size is not bounded by the caller. The subagent returns a compact structured result, the specific fields the check needs, never raw tool output.

3. **Never delegate the decision, only the retrieval.** The cheap agent gathers and normalises. The calling skill still decides what the findings mean and still applies its own approval gates before any write.

4. **Keep outward-facing writes with the caller.** A delegated agent must not transition a ticket, post a comment, merge a PR, or send a message. Those need the caller's approval gate.

5. **Give a delegated agent the retrieval traps explicitly.** A cheap model will not infer pagination quirks, truncation behaviour, or a flaky endpoint's retry needs. A confident wrong "nothing found" from a subagent is worse than running no check at all, because it reads as a clean result. Every known trap belongs in that agent's own instructions.

## Model-tier policy for delegated agents

- **haiku**, mechanical retrieval, formatting, and running a command and reporting its output.
- **sonnet**, bounded analysis against a clear rubric.
- **opus**, judgement that carries real risk: code review, plan verification, security, final quality gates.

Any agent must justify anything above haiku. Pin the tier explicitly in the agent's `model:` frontmatter; an unpinned agent inherits
the session's model, which defeats the purpose.

Agentic Repos ships no agents of its own: `ar-*` skills delegate to the agents installed by `agentic-devkit`, which already pin their
tiers. A skill names the agent it wants; it does not re-specify the tier.

## Capability is not a control

An available cheap agent does not reduce cost on its own. If no skill instruction says to delegate, delegation is left to in-the-moment judgement and does not reliably happen. A skill that needs a bulk read must **name** the delegation in its own steps.
