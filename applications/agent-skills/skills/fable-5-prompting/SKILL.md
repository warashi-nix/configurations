---
name: fable-5-prompting
description: Optimize prompts, system prompts, agent instructions, and skills for Claude Fable 5 (and Claude Mythos 5). Use when writing a new prompt targeting Fable 5, migrating an existing prompt or skill from an older Claude model (e.g. Opus 4.x, Sonnet 4.x), or debugging Fable 5 behaviors such as overplanning, early stopping, unrequested actions, fabricated progress reports, or unwanted refusals.
---

# Fable 5 Prompt Optimization

Optimize a prompt, skill, or agent scaffold for Claude Fable 5. Fable 5 follows instructions more strongly, runs longer turns, and needs *less* prescription than prior models — most optimization is removing instructions, not adding them.

The exact wording of every recommended instruction snippet lives in `resources/prompting-claude-fable-5.md`. Read it before inserting any snippet; copy snippets verbatim rather than paraphrasing from memory.

## Workflow

1. Read the target prompt/skill in full and identify which model it was written for.
2. Read `resources/prompting-claude-fable-5.md`.
3. Apply the audit below: first removals, then refusal-risk fixes, then targeted additions.
4. Present changes as a diff or edited file, with a one-line reason per change.

## Audit checklist

### Step 1: Remove what Fable 5 no longer needs

Fable 5's instruction following is strong enough that brief instructions replace enumerations. Over-prescription actively degrades output.

- [ ] Collapse lists that enumerate every variant of a behavior ("don't do X, don't do Y, don't do Z…") into one short instruction stating the principle.
- [ ] Remove step-by-step hand-holding for tasks the model handles well by default (basic tool use, standard coding practice, generic "be careful" advice). Keep prescriptive steps only for genuinely fragile operations.
- [ ] Remove extended-thinking budget parameters and thinking-mode toggles; Fable 5 uses adaptive thinking only.
- [ ] If unsure whether an instruction is still needed, prefer removal and test — default performance is often better.

### Step 2: Fix refusal risks

- [ ] Remove any instruction telling the model to echo, transcribe, reproduce, or explain its internal reasoning/thinking in the response text. These trigger the `reasoning_extraction` refusal category. If reasoning visibility is needed, read structured `thinking` blocks from the API instead.
- [ ] If the workload touches cybersecurity or biology/life-sciences domains, note that safety classifiers may refuse even benign requests; recommend configuring fallback to Claude Opus 4.8.

### Step 3: Add targeted instructions — only for observed or expected problems

Do not add all of these. Match each snippet to a symptom; each has verbatim text in the resource doc (section named in parentheses).

| Symptom / need | Snippet (resource section) |
|---|---|
| Overplanning, re-litigating settled decisions | "When you have enough information to act, act." (Longer turns by default) |
| Unrequested refactoring, speculative abstractions, defensive code | "Don't add features, refactor, or introduce abstractions…" (Consider all effort levels) |
| Verbose, over-structured output | Brevity instruction: "Lead with the outcome…" (Strong instruction following) |
| Stops to ask too often / too rarely | Checkpoint instruction: "Pause for the user only when…" (Strong instruction following) |
| Fabricated or unverified status reports on long runs | "Before reporting progress, audit each claim against a tool result…" (Ground progress claims) |
| Unrequested actions (fixes when only asked to assess, defensive backups) | Boundary instruction: "When the user is describing a problem…" (State the boundaries) |
| Autonomous pipeline ends turn with intent statement instead of acting | Autonomy reminder: "You are operating autonomously…" (Rare cases of early stopping) |
| Model suggests new session / trims work due to visible token counts | Hide the countdown, or add reassurance: "You have ample context remaining…" (Rare cases of context-budget concern) |
| Hard-to-read final summaries (arrow chains, working shorthand) | Communication-style addendum (Readability when communicating with the user) |
| Underused parallelism | Subagent delegation instruction (Parallel subagents) |

### Step 4: Scaffolding review (for agent harnesses, not plain prompts)

- [ ] Turns can run many minutes and autonomous runs hours: check client timeouts, streaming, and progress UX.
- [ ] Effort level: default `high`; `xhigh` for capability-critical work, `medium`/`low` for routine work. Lower effort on Fable 5 often beats `xhigh` on prior models.
- [ ] Long autonomous runs: add explicit self-verification with fresh-context verifier subagents at intervals.
- [ ] Long/async agents delivering verbatim content mid-turn: add a `send_to_user` tool *and* the paired elicitation instruction (the tool alone is rarely called). Schema and wording in the resource doc.
- [ ] Memory across runs: provide a notes location and the one-lesson-per-file instruction (Construct a memory system).
- [ ] Request phrasing: include the *why* behind requests ("I'm working on [X] for [who]; they need [what]…").

## Gotchas

- Skills and prompts written for older models are often *too prescriptive* for Fable 5 and degrade its output — removal is the highest-value edit, not addition.
- Adding every snippet from the table indiscriminately recreates the over-prescription problem. Add only what a symptom justifies.
- Snippets in the resource doc are tested wording; paraphrasing them weakens their effect. Copy verbatim, then adapt names/placeholders like `[X]` only.
- `send_to_user` without its elicitation instruction in the system prompt is dead weight — Fable 5 rarely calls an unprompted tool.
- Test Fable 5 at the top of your difficulty range; evaluating it only on tasks tuned for prior models undersells it and hides regressions from over-prescription.
