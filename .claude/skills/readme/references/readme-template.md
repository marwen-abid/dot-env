# README Template Reference

This is a reference template. Adapt it to the project — skip sections that don't apply, merge thin sections, add project-specific ones. The ordering below reflects cognitive funneling: broad context first, then progressively specific.

---

## Template

```markdown
# Project Name

One-line description: what it does and why it exists.

> Optional: a longer paragraph (2-3 sentences) explaining the problem this solves,
> who it's for, and what makes it different from alternatives.

<!-- Badges: only if they convey real information (build status, version, coverage) -->

## Table of Contents

<!-- Include for READMEs longer than ~4 screens. Use anchor links. -->

## Quick Start

<!-- The fastest path from zero to "it works".
     Ideally 3-5 commands max. Save detailed explanation for later sections. -->

## Prerequisites

<!-- What needs to be installed before this project. Be specific about versions.
     Example: Node.js >= 18, PostgreSQL 15+, Docker (optional) -->

## Installation

<!-- Step-by-step. Include both the common case and platform-specific notes if needed. -->

## Usage

<!-- Show, don't tell. Code examples with expected output.
     Start with the most common use case, then show advanced usage. -->

### Basic Usage

### Advanced Usage

### Configuration

<!-- Environment variables, config files, CLI flags.
     Use a table for env vars:
     | Variable | Description | Default | Required |
     |----------|-------------|---------|----------|
-->

## Architecture

<!-- High-level system design. Answer: "How is this organized and why?"
     Include a Mermaid diagram if the system has >3 interacting components. -->

### Directory Structure

<!-- Annotated tree of key directories. Don't list every file —
     focus on the ones that help someone navigate the codebase. -->

### Key Components

<!-- For each major component/module: what it does, what it depends on,
     and any important design decisions. -->

### State Management

<!-- If the system has meaningful state (order lifecycle, connection states,
     job queues, etc.), document the state machine with a Mermaid stateDiagram.
     Skip this section if state is trivial. -->

### Data Flow

<!-- How data moves through the system. Useful for pipelines,
     event-driven architectures, or multi-service setups.
     Use a Mermaid flowchart or sequence diagram. -->

### Data Model

<!-- Key entities and their relationships.
     Use a Mermaid erDiagram for database-backed projects. -->

## API Reference

<!-- For libraries: key exports with signatures and examples.
     For services: endpoints, methods, request/response formats.
     For CLIs: commands and flags.
     If extensive, link to generated docs instead of inlining. -->

## Development

### Setup

<!-- How to set up a dev environment. Include database setup,
     seed data, etc. if applicable. -->

### Running Tests

### Building

### Debugging Tips

<!-- Common issues and how to diagnose them.
     "If you see X, it usually means Y." -->

## Deployment

<!-- How to deploy. Include environment-specific notes if relevant.
     Skip for libraries. -->

## Troubleshooting

<!-- FAQ-style: common problems and solutions.
     Only include if there are known gotchas. -->

## Contributing

<!-- Link to CONTRIBUTING.md if it exists, or brief guidelines.
     Skip if not accepting contributions. -->

## License

<!-- State the license and link to LICENSE file. -->
```

---

## Section Selection Guidance

**Always include:** Project Name, Description, Quick Start, Installation, Usage, License

**Include if relevant:**
- Prerequisites — if there are non-obvious dependencies
- Architecture — if the codebase has >3 major components or non-obvious design
- State Management — if there are meaningful state machines or lifecycles
- Data Flow — if data passes through multiple stages/services
- Data Model — if there's a database with >3 related tables
- API Reference — if the project exposes an API (REST, GraphQL, CLI, library exports)
- Development — if setup involves more than `git clone && npm install`
- Deployment — if deploying is non-trivial (skip for libraries)
- Troubleshooting — if there are known gotchas
- Configuration — if there are >3 configurable options

**Skip for simple projects:** Table of Contents, Architecture subsections, Deployment, Troubleshooting, Contributing (unless accepting contributions)
