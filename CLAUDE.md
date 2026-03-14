# Claude instructions

Load and follow the shared repository skill guidance below when it is relevant to the task. Shared reusable skill definitions live in `.github/skills/`, and the essential guidance is mirrored here for direct instruction loading.

## Shared skill definitions
- `.github/skills/workbench-feature-brief/SKILL.md`
- `.github/skills/personal-server-principles/SKILL.md`
- `.github/skills/work-ethics/SKILL.md`

When you add another shared skill, add `.github/skills/<skill-name>/SKILL.md` and a concise summary in the instruction files that are actually read.

## Workbench feature brief
Use this skill for non-trivial features, refactors, or operational changes that need full-scope research, a self-contained workbench brief, and tracked execution through rollout.

- Create or update a matching markdown file in `workbench/`.
- Every workbench file should contain:
  - `# Title`
  - `## Summary`
  - `## Todo`
  - `## Discussion`
- Research enough to understand the full scope before narrowing the plan.
- Add new research findings and evidence to timestamped `Discussion` notes.
- When `Discussion` gets long, condense the confirmed decisions into `Summary`.
- Derive self-contained `Todo` items from `Summary`.
- Try to complete each todo before asking the user for input.
- Default to local-repo changes first, then server copy/deploy/hot patch, then re-sync local and server, then commit and close the task when those rollout steps are relevant.

## Personal server principles
Use this skill whenever proposing infrastructure, architecture, or operational decisions for this repository.

Apply these priorities in order:
1. Respect fixed hardware constraints.
2. Minimize cost, especially recurring spend.
3. Prefer the simplest viable deployment and operating model.
4. Favor reliability, reproducibility, recovery, and ease of rebuild.

When giving recommendations:
- Explicitly call out the tradeoffs.
- State which priority decided the outcome.
- Avoid adding cost or complexity unless it clearly protects a higher-priority need.

## Work ethics
Use this skill whenever a task needs persistence, ownership, and end-to-end execution.

- Continue working until you hit a non-trivial blocker that truly requires user input.
- For investigation tasks, keep researching instead of stopping to ask for input just because the path is long.
- Push each todo as far as possible before asking for guidance.
- Prefer concrete progress and verified conclusions over partial handoffs.

## Source references
@.github/skills/workbench-feature-brief/SKILL.md
@.github/skills/personal-server-principles/SKILL.md
@.github/skills/work-ethics/SKILL.md
