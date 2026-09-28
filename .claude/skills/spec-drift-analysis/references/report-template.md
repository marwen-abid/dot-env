# Drift Report Template

Use this exact structure when generating drift analysis reports. Fill in concrete values — never leave placeholders.

## Template

```markdown
# SEP vs OpenAPI Spec Drift Analysis

**Date:** [YYYY-MM-DD]
**Spec Version:** [from openapi info.version field]
**SEPs Covered:** [comma-separated list, e.g., SEP-1 (Discovery), SEP-10 (Web Authentication)]
**Drift Score:** [N%] (0% = perfect conformance)

---

## Executive Summary

**Overall Score: [X] PASS / [Y] FAIL / [Z] FLAG**

[1-3 sentence summary. Start with the conformance verdict. If FAIL count is 0, say "fully conformant."
If there are FAILs, summarize the most critical ones. Mention the number of FLAGS as trade-offs or limitations.]

---

## [SEP-N]: [Full Name]

**Score: [X] PASS / [Y] FAIL / [Z] FLAG**

**Files verified:**
- [list every OpenAPI file that was read for this SEP]

### [Section Name, e.g., "GET /auth (Challenge Request)"]

| # | Check | Verdict | Reference |
|---|-------|---------|-----------|
| 1 | [Brief description of what was checked] | **PASS** | `[file]:[line]` — [short note] |
| 2 | [description] | **FAIL** | `[file]:[line]` — [what's wrong] |
| 3 | [description] | **FLAG** | `[file]:[line]` — [why it's flagged] |

### [SEP-N] Flags Detail

[For each FLAG and FAIL, provide a structured detail block:]

**F-SEPN-[seq]: [Short title]**
- **Severity:** FAIL | LOW | INFO
- **Location:** `[file]:[line range]`
- **Issue:** [What the spec says vs what the SEP says]
- **Assessment:** [Why this is acceptable / what needs to change]
- **Recommendation:** [Action to take, if any]

### [SEP-N] Additional Observations

[Numbered list of noteworthy findings that don't fit the checklist but are worth documenting.
These might be: encoding choices, asymmetries between similar endpoints, loose patterns, etc.]

---

## Findings Summary

| ID | Severity | SEP | Finding | Action |
|----|----------|-----|---------|--------|
| F-SEP1-1 | LOW | SEP-1 | [short description] | [action or "No action needed"] |
| F-SEP10-1 | INFO | SEP-10 | [short description] | [action] |

---

## Methodology

Each SEP was verified by an independent agent that:
1. Read every referenced OpenAPI file AND the corresponding SEP document
2. Checked each item against a structured checklist covering: endpoints, HTTP methods, parameters, request/response schemas, authentication, types, enums, patterns, deprecated flags, error responses, CORS, and HTTPS
3. Marked each item PASS/FAIL/FLAG with exact file:line references
4. Produced a structured findings table

**Verification scope:** [N] total checklist items across [M] SEPs, covering [P] endpoints, [Q]+ schemas, and all scalar types.
```

## Scoring Rules

### Drift Score Calculation

```
drift_score = (FAIL_count / total_checked_items) * 100
```

Round to one decimal place. A drift score of 0.0% means no deviations.

### Verdict Rules

- **PASS**: The spec field/value exactly matches what the reference document specifies. This includes:
  - Correct values that are a strict superset of the reference (e.g., accepting more content types than required)
  - Values that match the spirit of the reference even if the exact representation differs due to format limitations

- **FAIL**: The spec deviates from the reference in a way that would cause incorrect behavior:
  - Missing required fields or parameters
  - Wrong types (string vs number, wrong enum values)
  - Wrong patterns that would reject valid inputs or accept invalid ones
  - Missing required authentication or authentication on public endpoints
  - Wrong HTTP methods or paths

- **FLAG**: An acceptable deviation or limitation that should be documented:
  - **LOW**: Could confuse implementors but doesn't break correctness (e.g., 401 on a public endpoint)
  - **INFO**: Known trade-off or format limitation (e.g., OpenAPI can't express "at least one of", CORS as infrastructure concern, additionalProperties:false for codegen)

### File:Line References

Every verdict must include a file:line reference so a human can verify the claim. Format: `filename:line` or `filename:line-range`.

Examples:
- `auth.yaml:29` — single line
- `schemas/transaction.yaml:197-216` — line range
- `ramp-api.yaml:56` — root document reference

Use relative paths from the openapi/ directory when possible. For SEP references, use the full filename (e.g., `SEPs/sep-0024.md:841`).
