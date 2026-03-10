# Skill: Workbench feature brief and PR planning

## Purpose
Before or during any non-trivial feature, fix, refactor, or operational change, maintain a local planning document in `workbench/` that acts as the source of truth for requirements, task tracking, research, and decisions.

## Use this skill when
- shaping a new feature or PR
- capturing research or design tradeoffs
- coordinating a multi-step change
- preserving a local record of evolving requirements

## Required output
Create or update a `workbench/*.md` file with these sections:
- `# Title`
- `## Summary`
- `## Todo`
- `## Discussion`

## Workflow
1. Pick or create the relevant `workbench/*.md` file before significant implementation work begins.
2. Write a concise `Title` that describes the feature or PR.
3. Keep `Summary` focused on the latest intended final state only.
4. Use `Todo` for specific checkbox items that represent the remaining work.
5. Use `Discussion` for timestamped notes, research findings, tradeoffs, questions, and decisions.
6. Periodically distill confirmed decisions from `Discussion` back into `Summary` and `Todo`.
7. If a prior idea is no longer correct, remove it from `Summary` instead of leaving stale direction in place.

## Guardrails
- `Summary` is the canonical current plan.
- `Discussion` can preserve history; `Summary` should not.
- `Todo` items should be concrete enough to execute without reinterpretation.
- Prefer updating an existing workbench file over creating multiple overlapping files for the same effort.

## Suggested template
```md
# <Feature or PR title>

## Summary
<Describe only the current desired end state.>

## Todo
- [ ] <Actionable task>
- [ ] <Actionable task>

## Discussion
- YYYY-MM-DD HH:MM - <Observation, research note, decision, or question>
```
