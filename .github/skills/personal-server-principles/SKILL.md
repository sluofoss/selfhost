---
name: personal-server-principles
description: Evaluate infrastructure, architecture, and operational choices for this repository as a personal self-hosted server project. Use this when comparing deployment, storage, service, cost, or reliability tradeoffs.
---

Evaluate proposals in this repository as decisions for a personal self-hosted server, not a generic enterprise environment.

## Use this skill when

- comparing infrastructure options
- choosing services or deployment patterns
- deciding whether to add operational complexity
- evaluating cost, simplicity, and recovery tradeoffs

## Priority order

1. Respect fixed hardware constraints.
2. Minimize cost, especially recurring spend.
3. Prefer the simplest viable deployment and operating model.
4. Favor reliability, reproducibility, recovery, and ease of rebuild.

## Decision process

1. State the requirement and the viable options.
2. Eliminate or flag options that violate fixed hardware constraints.
3. Compare cost, especially recurring spend.
4. Prefer the simplest option that still satisfies the requirement.
5. Evaluate reliability, reproducibility, recovery, and rebuild implications.
6. Explain the final recommendation in terms of the priority order above.

## Guardrails

- Do not assume the hardware can change unless the user explicitly asks to revisit hardware constraints.
- Avoid adding recurring services or operational overhead without a clear payoff.
- If a more complex option is recommended, explain which higher-priority need justifies it.
- When two options are close, prefer the one that is easier to deploy again and recover from.

## Output expectations

- Clearly identify the recommended option.
- Name the deciding priority.
- Call out the main tradeoffs and assumptions.
