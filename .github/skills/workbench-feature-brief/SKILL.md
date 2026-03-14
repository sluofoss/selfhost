---
name: workbench-feature-brief
description: Drive non-trivial repository work with a self-contained workbench brief. Use this when a feature, fix, refactor, or operational change needs full-scope research, distilled decisions, derived todos, and tracked rollout steps from local changes through server sync.
---

Use a matching `workbench/*.md` file as the source of truth for non-trivial features, fixes, refactors, or operational changes. The workbench file should be self-contained enough that someone can understand the current state of the work, the decisions already made, and the remaining tasks just by reading it.

## Use this skill when

- shaping a new feature or PR
- capturing research or design tradeoffs
- coordinating a multi-step change
- preserving a local record of evolving requirements
- carrying a change from investigation through implementation and rollout

## Required output

Create or update the relevant `workbench/*.md` file with these sections:

- `# Title`
- `## Summary`
- `## Todo`
- `## Discussion`

## Workflow

1. Reuse an existing matching workbench file when one already exists; otherwise create a new one.
2. Research broadly enough to understand the full scope of the problem before narrowing to a plan or implementation.
3. Record new research findings, evidence, tradeoffs, open questions, and decisions as timestamped notes in `Discussion`.
4. When `Discussion` grows long or a direction becomes clear, condense the confirmed decisions into `Summary`.
5. Keep `Summary` focused on the latest intended final state only.
6. Derive `Todo` items from `Summary`. Keep them self-contained, actionable, and specific enough to execute without rereading the entire history.
7. Try your best to complete each todo before asking the user for input.
8. For implementation work, default to making the changes in the local repository first.
9. After local changes, SSH to the server and copy, deploy, or hot patch the relevant changes when the task affects deployed behavior.
10. Debug on the server as needed, then ensure the local repository and server state are back in sync before finishing.
11. After rollout and sync, commit the complete workbench feature and close the ticket or task.
12. after closing the ticket rename the workbench file with a prefix of either COMPLETED or ABANDONED.
13. Only ask for user input when you hit a non-trivial decision, missing access, or another blocker that cannot be resolved through further work.

## Guardrails

- `Discussion` is where new research accumulates; `Summary` is where the current chosen direction is distilled.
- `Todo` items should be concrete enough to execute without reinterpretation.
- Prefer updating one relevant workbench file over creating overlapping files for the same effort.
- Remove obsolete direction from `Summary` once it has been superseded.
- If a rollout step is not applicable, say so explicitly in `Discussion` instead of silently skipping it.

## Suggested template

```md
# <Feature or PR title>

## Summary
<Describe only the current desired end state.>

## Todo
- [ ] <Actionable task>
- [ ] <Actionable task>

## Discussion
- YYYY-MM-DD HH:MM - <Research finding, tradeoff, decision, rollout note, or question>
```
