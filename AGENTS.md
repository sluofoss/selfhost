# Agent instructions

This repository keeps reusable agent skills in `docs/ai/skills/`, but that directory is documentation rather than an autoload hook. If a shared skill must reliably apply, explicitly list it here and in `CLAUDE.md`, and treat the files in `docs/ai/skills/` as the detailed source material behind the inline guidance below.

## Shared skill files
- `docs/ai/skills/workbench-feature-brief.md`
- `docs/ai/skills/personal-server-principles.md`

When you add another shared skill, add both the skill file and a concise summary in the agent instruction files that are actually read.

## Workbench feature brief
Use this skill for non-trivial features, refactors, or operational changes that need planning or research.

- Create or update a matching markdown file in `workbench/`.
- Every workbench file should contain:
  - `# Title`
  - `## Summary`
  - `## Todo`
  - `## Discussion`
- Keep `Summary` limited to the current desired end state.
- Keep `Todo` actionable and maintained as checkboxes.
- Keep `Discussion` records timestamped and use it for research, tradeoffs, and intermediate decisions.
- Periodically fold confirmed decisions in `Discussion` back into `Summary` and `Todo`.
- Remove obsolete direction from `Summary` once it is superseded.

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
