---
name: spec-drift-analysis
description: >
  Verify an OpenAPI specification against authoritative reference documents (like Stellar SEPs) to detect drift.
  Produces a scored drift report covering endpoints, parameters, request/response schemas, authentication,
  types, validations, deprecated flags, error responses, and cross-cutting concerns.
  Use this skill whenever the user asks to verify a spec against SEPs, check spec compliance, detect API drift,
  compare an OpenAPI spec to reference docs, audit an API specification, or ensure spec faithfulness.
  Also trigger when the user mentions "drift analysis", "spec verification", "SEP compliance", or
  "check the spec against the SEPs". Even if they just say "verify the spec" or "is the spec correct",
  this skill applies.
---

# Spec Drift Analysis

Systematically verify an OpenAPI specification against authoritative reference documents (e.g., Stellar Ecosystem Proposals). The output is a scored drift report in markdown with per-item PASS/FAIL/FLAG verdicts and file:line references.

## Why this workflow matters

OpenAPI specs are used for SDK codegen, documentation, and conformance tests. If the spec drifts from the authoritative reference, generated code will have wrong types, missing fields, or incorrect validations. This workflow catches drift early by comparing every endpoint, parameter, schema, and constraint against the source of truth.

## Phase 1: Scope Agreement

Before doing any verification work, confirm scope with the user.

1. **Identify reference documents** -- Ask which SEPs (or other reference docs) to cover. Common choices:
   - SEP-1 (Discovery / stellar.toml)
   - SEP-10 (Web Authentication)
   - SEP-24 (Interactive Deposit & Withdrawal)
   - Others as the spec grows (SEP-6, SEP-9, SEP-12, SEP-38, SEP-45)

2. **Identify the OpenAPI spec root** -- Typically `openapi/ramp-api.yaml` or similar. Confirm with the user.

3. **Identify the reference docs directory** -- Typically `SEPs/` or similar.

4. **Ensure the bundled spec is up to date** -- Run `make bundle` (or equivalent; `make bundle` requires the repo's Makefile) to produce `openapi/dist/ramp-api-bundled.yaml`. This fully-inlined single file is the source of truth for all `openapi spec query` commands. Agents should query this file, not the individual source files.

5. **Check for a previous drift report** -- Look for `.claude/docs/sep-spec-drift-analysis.md` or ask the user. If one exists, this run can be a delta comparison.

## Phase 2: Build the Checklist

This is the most important phase -- building a comprehensive, itemized checklist ensures nothing is forgotten. The scratch file and task list keep every item tracked across a long, multi-agent run.

### Create a scratch file

Write a checklist scratch file to `.claude/drift-analysis-scratch.md`. This file is your persistent working memory throughout the analysis. It tracks what needs to be checked and what's been completed.

Before dispatching any agents, populate this file completely with every checklist item for every SEP in scope. After each agent completes, re-read the scratch file and mark items as done. If any items are still unchecked after all agents return, investigate them before compiling the report.

Also create a TaskCreate entry for each SEP being verified (e.g., "Verify SEP-10 against OpenAPI spec") and mark them in_progress/completed as you go. This gives the user visibility into progress.

The scratch file should be organized by SEP with the following sections per SEP:

```markdown
# Drift Analysis Checklist — [date]

## SEP-X: [Name]
Status: NOT STARTED | IN PROGRESS | COMPLETE

### Files to Read
- [ ] Reference doc: SEPs/sep-00XX.md
- [ ] OpenAPI path files: (list each)
- [ ] OpenAPI schema files: (list each)

### Checklist Items
- [ ] ENDPOINTS: [path] [method] matches reference
- [ ] AUTH: security setting matches reference
- [ ] PARAMS: [param_name] — present, required/optional, type, pattern, constraints
- [ ] REQUEST: schema fields, content types
- [ ] RESPONSE: schema fields, required array, types
- [ ] TYPES: enum values, patterns, maxLength, minimum/maximum
- [ ] DEPRECATED: flags present where reference says deprecated
- [ ] ERRORS: correct HTTP status codes defined
- [ ] CROSS-CUTTING: CORS, HTTPS, additionalProperties
```

### Checklist dimensions

Read `references/checklist-template.md` for the full set of verification dimensions. For each endpoint defined in a reference document, verify ALL of the following:

1. **Endpoint correctness** -- path, HTTP method, operationId
2. **Parameter correctness** -- every param from the reference is present with correct name, type, required/optional status, format, pattern, min/max constraints
3. **Request body correctness** -- schema fields match reference, content types are correct (JSON, form-urlencoded, multipart)
4. **Response correctness** -- schema fields, required array, types, nested object structures
5. **Authentication correctness** -- which endpoints need auth (`security: [{sep10Auth: []}]`) vs public (`security: []`)
6. **Type correctness** -- enum values match exactly, regex patterns match, string formats match
7. **Validation correctness** -- minLength, maxLength, minimum, maximum, pattern constraints from reference
8. **Deprecated flag correctness** -- fields/endpoints marked deprecated in reference have `deprecated: true` in spec
9. **Error response correctness** -- HTTP status codes defined match what reference specifies
10. **Cross-cutting** -- CORS headers, HTTPS enforcement, `additionalProperties` settings, rate-limit headers

## Phase 2.5: Extract Spec Facts with `openapi spec query`

Before dispatching agents, use the `openapi` CLI to extract structured facts from the bundled spec. This is faster and more accurate than reading YAML files by hand, and gives agents concrete data to compare against SEP requirements.

**CLI availability**: Run `command -v openapi` first. If the CLI is missing:

1. Skip the `openapi spec query` steps in this phase (and `make bundle` if it calls the CLI).
2. Extract the same facts by reading the YAML directly (the bundled file if it exists, otherwise the source files in `openapi/paths/` and `openapi/components/schemas/`). Give the agents these facts instead of query output.
3. Tell the user which steps you skipped. Hint: install the `openapi` CLI used locally.

The bundled file (`openapi/dist/ramp-api-bundled.yaml`) is fully inlined — all `$ref`s resolved. Run `openapi spec query` against it. When a finding needs tracing back to the source file, use Grep on the individual files in `openapi/paths/` and `openapi/components/schemas/`.

### Essential queries to run upfront

Run these queries and include their output in the agent prompts so agents have concrete spec data to compare against:

**1. All endpoints with methods and deprecated status:**
```bash
openapi spec query 'operations | select name, method, path, deprecated' openapi/dist/ramp-api-bundled.yaml --format markdown
```

**2. Security per operation (which endpoints need auth):**
```bash
openapi spec query 'operations | security | select operation, schemeName, schemeType' openapi/dist/ramp-api-bundled.yaml --format markdown
```
Note: endpoints with `security: []` (public) will NOT appear in this output — their absence means no auth.

**3. All parameters per operation:**
```bash
openapi spec query 'operations | parameters | select operation, name, in, required, type' openapi/dist/ramp-api-bundled.yaml --format markdown
```

**4. Request body content types:**
```bash
openapi spec query 'operations | request-body | content-types | select operation, mediaType' openapi/dist/ramp-api-bundled.yaml --format markdown
```

**5. All response codes per operation:**
```bash
openapi spec query 'operations | responses | select operation, statusCode, description' openapi/dist/ramp-api-bundled.yaml --format markdown
```

**6. Request body properties for a specific operation** (run per endpoint):
```bash
openapi spec query 'operations | where(name == "postDepositInteractive") | request-body | content-types | to-schema | properties | select name, type' openapi/dist/ramp-api-bundled.yaml --format markdown
```

**7. Full schema with enums/patterns/constraints** (use `to-yaml` for deep inspection):
```bash
openapi spec query 'operations | where(name == "getChallenge") | parameters | where(name == "account") | to-schema | to-yaml' openapi/dist/ramp-api-bundled.yaml
```

**8. Response schema properties (nested):**
```bash
openapi spec query 'operations | where(name == "getTransaction") | responses | where(statusCode == "200") | content-types | to-schema | properties(*) | where(name contains "status") | to-yaml' openapi/dist/ramp-api-bundled.yaml
```

### Tracing back to source files

When a query reveals a potential issue, trace it to the source file for the file:line reference in the report:
- Parameters → `openapi/paths/<endpoint>.yaml`
- Request body schemas → `openapi/components/schemas/<domain>.yaml`
- Scalars (patterns, enums) → `openapi/components/schemas/scalars.yaml`
- Error responses → `openapi/components/responses/errors.yaml`
- Security → `openapi/components/securitySchemes.yaml`

Use Grep to find the exact line: `grep -n 'pattern_or_field_name' openapi/paths/auth.yaml`

## Phase 3: Dispatch Verification Agents

Spawn one agent per SEP/reference document, running in parallel. Each agent is an independent verifier that compares the SEP requirements against the spec facts extracted in Phase 2.5.

### Agent prompt template

For each SEP, provide the agent with:
1. The full path to the reference document
2. The **query outputs from Phase 2.5** — paste the relevant markdown tables so the agent has structured spec data
3. The specific checklist items for that SEP
4. The path to the bundled spec for any follow-up `openapi spec query` commands the agent needs to run
5. Instructions on tracing findings back to source files for file:line references

Use the following prompt structure for each agent:

```
You are a spec drift verification agent. Your task is to verify the OpenAPI spec
against [SEP-X] by going through every checklist item. This is READ-ONLY research.

## Bundled Spec
Path: openapi/dist/ramp-api-bundled.yaml
Use `openapi spec query` for any additional inspection. Use `to-yaml` to inspect
full schemas with enums, patterns, and constraints.

## Spec Facts (extracted via openapi spec query)
[paste the relevant query outputs as markdown tables]

## Reference Document
[path to SEP file — read this completely]

## Checklist
[paste the specific checklist items for this SEP]

## Verdicts
For each item, determine:
- PASS: spec matches the reference document
- FAIL: spec deviates from reference (provide: what spec says, what reference says, file:line)
- FLAG: acceptable deviation or known trade-off (explain why)

## Tracing to Source Files
When reporting file:line references, trace from the bundled file back to the
source files (openapi/paths/, openapi/components/schemas/, etc.) using Grep.

## Output Format
Return a structured report with:
1. Each item number, verdict, justification with exact file:line references
2. Summary counts: X PASS / Y FAIL / Z FLAG
3. Any additional observations not in the checklist
```

### Staying on track

Agents can lose focus on long checklists. To prevent this:
- Keep each agent's checklist focused on a single SEP
- The scratch file acts as the master tracker — after each agent completes, re-read it and mark items done
- If a SEP has more than 40 checklist items (like SEP-24), consider splitting into sub-agents (e.g., one for endpoints/params, one for schemas/types)
- After all agents complete, do a gap check: read the scratch file and verify every item has a verdict. If any items lack a verdict, run targeted `openapi spec query` commands to fill the gaps
- Update task status (TaskUpdate) for each SEP as its agent completes

## Phase 4: Compile the Drift Report

After all agents return, compile results into a single drift report. Read `references/report-template.md` for the exact output format.

### Scoring

Calculate the drift score as:

```
drift_score = (FAIL_count / total_items) * 100
conformance_score = (PASS_count / total_items) * 100
```

A **drift score of 0%** means the spec perfectly matches the reference.

Severity levels for findings:
- **FAIL** -- Spec deviates from reference. Must be fixed.
- **FLAG (LOW)** -- Minor deviation that could confuse implementors. Consider fixing.
- **FLAG (INFO)** -- Acceptable trade-off or format limitation. Document but don't fix.

### Report structure

Save the report to `.claude/docs/sep-spec-drift-analysis.md` (or the path the user specifies). The report follows this structure:

```markdown
# SEP vs OpenAPI Spec Drift Analysis

**Date:** [today]
**Spec Version:** [from openapi info.version]
**SEPs Covered:** [list]

## Executive Summary
**Overall Score: X PASS / Y FAIL / Z FLAG**
**Drift Score: N%** (0% = perfect conformance)
[1-2 sentence summary]

## [SEP-X]: [Name]
**Score: X PASS / Y FAIL / Z FLAG**

**Files verified:**
- [list]

| # | Check | Verdict | Reference |
|---|-------|---------|-----------|
| 1 | [description] | **PASS/FAIL/FLAG** | `file:line` — [details] |

### [SEP-X] Flags Detail
[For each FLAG/FAIL, provide structured detail with severity, location, issue, assessment]

### [SEP-X] Additional Observations
[Numbered list of noteworthy findings not in the checklist]

## Findings Summary
| ID | Severity | SEP | Finding | Action |
|----|----------|-----|---------|--------|

## Methodology
[Description of verification process]
```

## Phase 5: Present Results

After writing the report:
1. Present the executive summary to the user
2. Highlight any FAIL items that need immediate attention
3. List FLAG items grouped by severity
4. Note any additional observations
5. Ask if the user wants to fix any findings

## Key Lessons from Previous Analyses

These patterns have been validated through real drift analyses and help avoid common pitfalls:

### SEP-10 gotchas
- The `account` param allows G... (public key) and M... (muxed account) but NOT C... (contract accounts). The auth endpoint should use an inline pattern `^[GM][A-Z2-7]{55,68}$`, not the general `StellarAccountId` scalar which includes C...
- The `memo` param is type `id` only (numeric) -- verify pattern is `^[0-9]+$`
- POST /auth accepts both `application/json` and `application/x-www-form-urlencoded` but NOT `multipart/form-data`
- 403 Forbidden is only on GET (for forbidden apps), not on POST

### SEP-24 gotchas
- The InteractiveResponse `type` field has ONLY `interactive_customer_info_needed` -- there is no "success" type in SEP-24 (that's SEP-6 only; SEP-24 line 753 is a dangling anchor)
- Deposit `memo`/`memo_type` are NOT deprecated, but withdraw `memo`/`memo_type` ARE -- this asymmetry is intentional
- The `/transaction` endpoint requires "at least one of" three params, which OpenAPI 3.0.3 cannot express
- `additionalProperties: false` blocks SEP-9 KYC fields on deposit/withdraw -- this is a known codegen trade-off
- Content types for deposit/withdraw being a superset (adding JSON beyond multipart) is acceptable
- The `StellarAccountId` scalar correctly includes C... (contract accounts) per SEP-24's support for them

### Cross-cutting gotchas
- CORS headers (`Access-Control-Allow-Origin: *`) are required by all SEPs but typically not modeled in OpenAPI specs -- flag as INFO, not FAIL
- 401 on a `security: []` endpoint is semantically inconsistent -- flag as LOW
- Rate-limit headers are operational additions, not spec requirements -- flag as INFO
