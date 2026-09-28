---
name: readme
description: >
  Generate comprehensive README.md documentation for any project. Use this skill whenever the user asks to
  create, write, generate, or update a README, project documentation, or "docs for this repo". Also trigger
  when the user says things like "document this project", "write docs", "what does this codebase do" (when
  they want it written up), "create a getting started guide", or "I need a README". This skill covers both
  operational documentation (installation, usage, configuration) AND architectural/internal documentation
  (system design, state machines, data flow). Use it even if the user only mentions one of these aspects —
  the skill will determine the right depth and coverage.
---

# README Generator

Generate thorough, genuinely useful README documentation that helps people both *use* and *understand* a codebase. A good README answers two questions fast: "Is this relevant to me?" and "How do I get started?" — then progressively reveals deeper detail for those who need it.

## Philosophy

The goal is documentation that *earns its length*. Every section should teach the reader something they can't easily figure out by skimming the code. Operational docs (install, run, configure) save people from trial-and-error. Architectural docs (design decisions, state machines, data flow) save people from reading every file to build a mental model.

Brevity is a feature. If a section would just restate what's obvious from a `package.json` or `Makefile`, make it concise. Spend words where the reader's confusion would be highest.

## Workflow

### Step 1: Parallel Codebase Exploration

Before writing anything, understand the project. For a large codebase, explore it with parallel subagents (`worker` for reading and extraction), one per aspect below. For a small project, explore it yourself.

The four aspects:

**Agent 1 — Project Identity & Build System**
> Explore the project root. Read package.json, Cargo.toml, pyproject.toml, go.mod, Makefile, Dockerfile, docker-compose.yml, or whatever build/config files exist. Determine: project name, language(s), framework(s), dependencies, build commands, entry points, scripts/tasks available. Also check for .env.example, config files, and CI/CD configs (.github/workflows/, .gitlab-ci.yml, etc.).

**Agent 2 — Architecture & Code Structure**
> Map the high-level directory structure (depth 2-3). For each top-level directory, identify its purpose. Find the main entry point(s) and trace the primary code paths. Look for architectural patterns: MVC, microservices, event-driven, plugin systems, etc. Identify the key abstractions/interfaces. Read any existing ARCHITECTURE.md or design docs.

**Agent 3 — State, Data Models & Diagrams**
> Search for state machines, enums representing states/statuses, database schemas (migrations, ORM models, SQL files), and data flow patterns. Look for workflow/lifecycle patterns (e.g., order states, request pipelines, auth flows). Identify the key entities and their relationships. Look for pub/sub, event systems, or message queues.

**Agent 4 — API Surface & Configuration**
> Find API endpoints (routes, controllers, handlers), CLI commands, exported functions/classes (for libraries), and configuration options. Check for existing API docs, OpenAPI/Swagger specs, or JSDoc/docstrings. Identify environment variables and their purposes.

If any agent finds the codebase is very simple (e.g., a single-file utility), that's fine — report what's there and don't invent complexity.

### Step 2: Synthesize Findings

Once all agents return, synthesize their findings. Identify:
- What's the one-sentence "what and why" for this project?
- What's the quickest path to "hello world" for a new user?
- What are the non-obvious design decisions someone would need to understand?
- Where would a new contributor get confused?
- What state transitions or data flows are complex enough to deserve a diagram?

### Step 3: Write the README

Use the template in `references/readme-template.md` as a starting structure, but adapt it to the project. Not every project needs every section. A CLI tool doesn't need an API reference section. A library doesn't need deployment instructions. Use judgment.

**Key principles while writing:**

- **Cognitive funneling**: Start broad (what is this?), get progressively specific (how do I configure the retry logic?)
- **Show, don't tell**: Use code examples, command snippets, and diagrams instead of prose wherever possible
- **Answer "why"**: Don't just document *what* the architecture is — explain *why* it's that way. "We use an event bus between services because X" is 10x more useful than "Services communicate via an event bus"
- **Mermaid diagrams as PNGs**: Generate diagrams as PNG images using `mmdc` (via npx) and embed them as image references. Keep the `.mmd` source files for future edits. See the diagram guidelines below
- **Honest about status**: If the project is alpha, say so. If parts are broken, note it. Trust > polish

### Step 4: Review and Refine

After writing the draft, review it with fresh eyes:
- Does the description make sense to someone who's never seen the project?
- Can someone go from zero to running the project by following the instructions?
- Are the diagrams actually clarifying, or just decorative?
- Is anything redundant or obvious enough to cut?
- Are there sections that are too thin to justify their heading? (If so, merge or remove them)

## Diagram Guidelines

Diagrams are rendered as **PNG images** using the Mermaid CLI (`mmdc` via npx), not as inline Mermaid code blocks. This ensures diagrams display correctly everywhere — not just GitHub — and gives a polished, professional look.

### Rendering Process

For each diagram:

1. **Create a `docs/diagrams/` directory** in the project root (if it doesn't exist)
2. **Write the Mermaid source** to a `.mmd` file with a descriptive name:
   ```bash
   cat << 'EOF' > docs/diagrams/payment-lifecycle.mmd
   stateDiagram-v2
       [*] --> Pending: Order created
       Pending --> Processing: Payment initiated
       Processing --> Completed: Payment confirmed
       Processing --> Failed: Payment declined
       Failed --> Processing: Retry
       Completed --> Refunded: Refund requested
       Refunded --> [*]
   EOF
   ```
3. **Render to PNG** using the Mermaid CLI:
   ```bash
   npx -y -p @mermaid-js/mermaid-cli mmdc -i docs/diagrams/payment-lifecycle.mmd -o docs/diagrams/payment-lifecycle.png -t neutral -b white
   ```
4. **Embed in the README** as an image with alt text:
   ```markdown
   The payment lifecycle follows these states:

   ![Payment lifecycle state diagram](docs/diagrams/payment-lifecycle.png)
   ```

Keep the `.mmd` source files alongside the PNGs so diagrams can be updated later. The source is the authoritative version; the PNG is the rendered output.

**Flags reference:**
- `-t neutral` — clean, readable theme (alternatives: `default`, `dark`, `forest`)
- `-b white` — white background (use `transparent` if the project prefers dark-mode compatibility)
- `-w 1200` — optional max width in pixels for very wide diagrams
- `-s 2` — optional scale factor for higher resolution

If `npx` fails or the user doesn't have Node.js, fall back to inline Mermaid code blocks (which GitHub still renders) and note in the README that diagrams can be regenerated with `npx -y -p @mermaid-js/mermaid-cli mmdc`.

### When to Use Which Diagram Type

| Situation | Diagram Type | Example |
|---|---|---|
| Component relationships | `flowchart LR` or `flowchart TD` | Service architecture, request flow |
| Request/response sequences | `sequenceDiagram` | API call chains, auth flows |
| Lifecycle / status machine | `stateDiagram-v2` | Order states, connection lifecycle |
| Data models & relationships | `erDiagram` | Database schema, entity relationships |
| Class/module structure | `classDiagram` | OOP hierarchies, interface contracts |

### Diagram Best Practices

- One concept per diagram — don't cram the entire system into one chart
- Use descriptive labels on nodes, not cryptic abbreviations
- Use `subgraph` to group related components
- Choose a consistent direction (LR for pipelines/flows, TD for hierarchies)
- Add a one-line caption above the diagram explaining what it shows
- Keep diagrams under ~15 nodes; split larger ones
- Name `.mmd` files descriptively: `architecture-overview.mmd`, `order-states.mmd`, `auth-flow.mmd`

## Section Depth Guide

Not every project needs the same depth. Use this to calibrate:

| Project Type | Operational Depth | Internals Depth |
|---|---|---|
| Small utility / script | Light (install + usage example) | Minimal or skip |
| CLI tool | Medium (install, usage, all commands, config) | Light (architecture if non-trivial) |
| Library / SDK | Medium (install, quick start, API reference) | Medium (design decisions, extension points) |
| Web application | Full (install, run, deploy, env vars, troubleshoot) | Full (architecture, state, data flow) |
| Microservices / platform | Full + per-service breakdown | Full (system diagram, service boundaries, protocols) |

## What NOT to Do

- Don't pad sections with filler. An empty "Contributing" section with just "PRs welcome!" is worse than no section
- Don't add badges for the sake of badges. Only include badges that convey useful status information
- Don't duplicate information that lives in other standard files (CHANGELOG.md, CONTRIBUTING.md, LICENSE) — link to them instead
- Don't write architecture docs for trivial projects — a 50-line script doesn't need a system diagram
- Don't include auto-generated API docs inline — link to them or suggest generating them
- Don't fabricate information. If you can't determine something from the codebase (e.g., deployment URL, team contacts), leave a `<!-- TODO: ... -->` placeholder and tell the user
