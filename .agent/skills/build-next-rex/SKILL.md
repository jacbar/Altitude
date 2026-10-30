---
name: build-next-rex
description: >-
  Orchestrate the next feature from freeform text: evaluate the idea, ask
  clarifying questions, produce a spec and implementation plan, then open a
  Rex terminal tab on a git worktree and start a Cursor agent (--model auto,
  --auto-review) to implement it. This session stays the orchestrator;
  worktree agents are implementors. Use when the user runs /build-next-rex
  or asks to build next, evaluate a feature then implement in Rex, or spawn
  a worktree implementor after planning.
disable-model-invocation: true
---

# Build Next (Rex)

Turn feature text into a ready slice, then hand implementation to a worktree
agent in Rex.

**This session is the orchestrator.** It owns evaluation, questions, spec,
implementation plan, worktree/tab creation, and the builder prompt. Implementor
agents execute that plan in isolated worktrees — they must not re-derive the
design from scratch.

Requires a live Rex context (`REX_SESSION` set, or discoverable via
`rex whoami --json` / `rex ls --json`). Requires `rex`, `git`, and `agent`
(Cursor Agent CLI) on `PATH`.

Optional arg: `$ARGUMENTS` — the feature text / idea. If empty, ask once for it.

## Role split

| Role | Who | Model / mode |
| --- | --- | --- |
| Orchestrator | This session (skill invoker) | Current high-capability session — evaluate, ask, spec, plan, spawn |
| Implementor | Cursor `agent` in a Rex tab on a worktree | `--model auto --auto-review --trust` |

Do **not** implement the feature in this orchestrator session once the plan is
approved. Design stays here; code stays in the worktree agent.

## Checklist

```
Build-next progress:
- [ ] 1. Preconditions (Rex + tools)
- [ ] 2. Ingest feature text
- [ ] 3. Feature evaluation (repo-grounded)
- [ ] 4. Clarifying questions (gate)
- [ ] 5. Spec (gate)
- [ ] 6. Implementation plan (gate)
- [ ] 7. Create git worktree + branch
- [ ] 8. Open Rex tab on the worktree
- [ ] 9. Start implementor agent (auto / model auto)
- [ ] 10. Feed builder prompt
- [ ] 11. Report handles; stay orchestrator
```

Print status lines: `FEATURE_OK`, `EVAL_OK`, `QUESTIONS_OK`, `SPEC_OK`,
`PLAN_OK`, `WORKTREE <path>`, `BRANCH <name>`, `REX_WINDOW <id>`,
`REX_BLOCK <id>`, `AGENT_STARTED`, `READY`, or `START_FAILED <reason>`.

---

## 1. Preconditions

```bash
command -v rex >/dev/null
command -v git >/dev/null
command -v agent >/dev/null
test -n "${REX_SESSION:-}" || true
```

If `REX_SESSION` is empty:

```bash
rex whoami --json
rex ls --json
```

Use the session that matches this chat / the user’s Rex location. If more than
one plausible session, ask once. Prefer `$REX_SESSION` when set.

Confirm you are in (or can resolve) the primary repo checkout:

```bash
primary=$(git rev-parse --show-toplevel)
```

If not inside a git repo, ask for the primary path. Fail with
`START_FAILED not in git repo` if unresolved.

Do not close Rex windows/blocks/sessions you did not create.

## 2. Ingest feature text

Use `$ARGUMENTS` if non-empty. Otherwise ask once: “What should we build next?”

Normalize into a short working title and kebab `slug` (lowercase, hyphens,
max ~40 chars). Print `FEATURE_OK <slug>`.

## 3. Feature evaluation

Stay read-only. Skim the repo for fit (patterns under `Altitude/`, config,
README / `AGENTS.md` constraints). Produce a short evaluation for the user:

1. **Problem** — what pain this addresses
2. **Fit** — how it maps onto existing modules / surfaces
3. **Value** — why it is worth doing now
4. **Risks** — technical, UX, permission, or scope risks
5. **Rough size** — S / M / L with one-line rationale
6. **Recommendation** — build / slim-first / defer (with why)

Print `EVAL_OK`. Do not write code.

## 4. Clarifying questions (gate)

Ask **3–7** pointed questions before drafting the spec. Prefer concrete choices
over open essays. Cover at least:

- User / trigger (who, when)
- Success criteria (observable done-when)
- In-scope vs out-of-scope
- Constraints (permissions, config, platform)
- Non-goals

Wait for answers. If the user says “you decide”, state assumptions explicitly
and get a single confirm. Print `QUESTIONS_OK` only after answers or confirmed
assumptions.

If the idea is incoherent or clearly wrong for this repo after answers:
`START_FAILED rejected <reason>` and stop.

## 5. Spec (gate)

Write a concise spec (chat is fine; optionally save under
`docs/features/<slug>.md` only if the user wants a file). Required sections:

```markdown
# <Title>

## Objective
## User / trigger
## Behavior
## Done when
## Out of scope
## Risks / open questions
```

Show the spec to the user and wait for approval (explicit yes / LGTM /
“proceed”). Revise until approved. Print `SPEC_OK`.

## 6. Implementation plan (gate)

Still orchestrator-only, still no feature code. Ground the plan in the tree
(files, symbols, tests/build commands). Required shape:

```markdown
# Implementation plan — <Title>

## Approach
## Steps (ordered, concrete paths)
## Files / symbols to touch
## Tests / verification
## Do not touch
## Done-when checks (builder-verifiable)
```

Show the plan and wait for approval. Print `PLAN_OK` only when both spec and
plan are approved.

Author the **builder prompt** now (send in §10). It must be executable by a
capable auto-model agent without redesigning: role, paths, branch, done-when,
numbered steps with file/symbol paths, constraints, and “escalate to
orchestrator if blocked”.

If the prompt still says “figure out the design”, it is not ready — rewrite.

## 7. Create git worktree + branch

From the primary checkout:

```bash
primary=$(git rev-parse --show-toplevel)
repo_name=$(basename "$primary")
base_remote=$(git -C "$primary" symbolic-ref --quiet --short refs/remotes/origin/HEAD || true)
base_branch=${base_remote#origin/}
base_branch=${base_branch:-main}
git -C "$primary" fetch origin "$base_branch" 2>/dev/null || true

worktrees_root="${BUILD_NEXT_WORKTREES:-$HOME/.cursor/worktrees/$repo_name}"
mkdir -p "$worktrees_root"
slug="<slug>"
branch="feat/${slug}"
wt_path="${worktrees_root}/${slug}"
```

If `branch` or `wt_path` already exists, ask once: reuse, or use
`feat/<slug>-2` / alternate path.

```bash
git -C "$primary" worktree add -b "$branch" "$wt_path" "origin/${base_branch}"
```

If `-b` fails because the branch exists and reuse was chosen:

```bash
git -C "$primary" worktree add "$wt_path" "$branch"
```

Print `WORKTREE <wt_path>` and `BRANCH <branch>`. On failure:
`START_FAILED worktree <error>`.

## 8. Open Rex tab on the worktree

Tab label: `impl-<slug>` (truncate if needed).

```bash
created=$(rex window new -s "$REX_SESSION" "impl-${slug}" -c "$wt_path" --json) || exit
window_id=$(printf '%s' "$created" | jq -er '.window_id')
block_id=$(printf '%s' "$created" | jq -er '.block_ids[0]')
```

Print `REX_WINDOW <window_id>` and `REX_BLOCK <block_id>`.

The new tab should be an interactive shell in `$wt_path`. Confirm with a short
capture if needed (`rex capture -s "$REX_SESSION" -b "$block_id" --trim`).

Do **not** start the agent in the orchestrator’s own block.

## 9. Start implementor agent

In the new tab’s shell, start Cursor Agent in auto mode with model auto:

```bash
rex send -s "$REX_SESSION" -b "$block_id" \
  "agent --model auto --auto-review --trust --workspace $(printf %q "$wt_path")"
rex send-key -s "$REX_SESSION" -b "$block_id" enter
```

Wait until the agent is ready for a prompt (poll `rex capture` until the UI
looks idle / awaiting input; typically a few seconds). Do not race the prompt.

Print `AGENT_STARTED`. On failure: report window/block/worktree ids and
`START_FAILED agent start`.

Notes:

- `--model auto` selects Cursor Auto.
- `--auto-review` is Smart Auto (auto mode): safe tool calls run; others prompt.
- `--trust` avoids the workspace-trust interstitial in a fresh worktree.
- Do **not** pass `--force` / `--yolo` unless the user explicitly asks for
  unsupervised run-everything.
- Do **not** also pass `agent -w`; the worktree already exists and is the cwd.

## 10. Feed builder prompt

Send the prompt authored in §6 into the implementor pane. Prefer one bracketed
paste via `rex send` (large text is fine; Rex reads it in parts), then Enter if
needed so the agent submits.

Shape:

```text
You are the implementor for feature "<title>" (slug: <slug>).

Working tree: <wt_path>
Branch: <branch>
Base: <base_branch>
Orchestrator: Rex session <REX_SESSION>, block <REX_BLOCK> (do not use this pane)

You are a lower-tier implementer. The orchestrator already evaluated the idea,
wrote the spec, and designed the implementation plan. Execute the plan below.
Do not reinvent acceptance, redesign the approach, or expand scope. If blocked,
ask in your pane (user-visible) and stop — do not improvise a new design.

## Spec (summary)
<compressed approved spec: objective, behavior, done-when, out of scope>

## Done when
<bulleted verification checks>

## Build plan (execute in order)
1. <step — concrete files/symbols>
2. …

## Constraints
- Out of scope: …
- Do not touch: …
- Follow existing patterns in: …
- Honor AGENTS.md (document user-facing behavior in README.md in the same change)

## Your loop
1. Implement in this worktree only. Stay on branch <branch>.
2. Prefer small, reviewable commits. Do not push unless asked.
3. Run the verification checks above.
4. When done, summarize: files changed, how to verify, remaining risks.
5. Do not delete this worktree or Rex tab — the orchestrator owns cleanup.
```

Do not `--wait` for the whole implementation. Return control to the user after
submission.

## 11. Report

Tell the user:

- Slug / title
- One-line evaluation outcome
- Worktree path + branch + base
- Rex window + block ids
- That the implementor is `agent --model auto --auto-review` on that worktree
- That **this** session remains orchestrator (further slices, review, cleanup)

End with `READY`.

---

## Parallel slices

Each approved feature gets its **own** worktree + Rex tab + implementor. Keep
this session as the single orchestrator. Do not overload one worktree with
unrelated features.

When starting another slice, re-run from §2 (reuse §1). Unique slugs/branches.

## Cleanup (orchestrator only)

Only when the user asks, or when an implementor reports the slice finished and
the user wants teardown:

1. Confirm desired disposition (keep branch / PR / discard).
2. Close the Rex window you created if still open:
   `rex window close -s "$REX_SESSION" <window_id>` (or the CLI’s close form
   from `rex window --help`).
3. Remove the git worktree from the primary checkout:
   `git -C "$primary" worktree remove "$wt_path"` (use `--force` only if the
   user explicitly wants a dirty discard).
4. Delete the branch only if the user asked.

## Failure rules

- No feature text after one ask → `START_FAILED`
- Cannot resolve Rex session → `START_FAILED`
- Spec or plan not approved → stay in gate; do not open worktree
- Worktree / Rex tab / agent start failure → leave partial artifacts, report
  ids, `START_FAILED` — do not delete unless the user asks

## Do not

- Implement the feature in the orchestrator session after `PLAN_OK`
- Hand the implementor a vague “build this idea” without spec + plan
- Start the implementor in `$REX_BLOCK` (orchestrator pane)
- Use Herdr APIs for this skill (Rex only)
- Force-push, or delete worktrees/branches without an explicit user request
