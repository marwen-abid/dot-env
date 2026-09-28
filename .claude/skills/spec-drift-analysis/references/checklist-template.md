# Drift Analysis Checklist Templates

This file contains the detailed checklist templates for each verification dimension. When building a checklist for a specific SEP, use these templates as the basis and fill in the concrete values from the reference document.

**Important:** Always run queries against the bundled spec (`openapi/dist/ramp-api-bundled.yaml`), then trace findings back to source files for file:line references.

## Table of Contents

1. [openapi spec query Cheat Sheet](#openapi-spec-query-cheat-sheet)
2. [Endpoint Verification](#endpoint-verification)
3. [Parameter Verification](#parameter-verification)
4. [Request Body Verification](#request-body-verification)
5. [Response Verification](#response-verification)
6. [Authentication Verification](#authentication-verification)
7. [Type & Scalar Verification](#type--scalar-verification)
8. [Deprecated Field Verification](#deprecated-field-verification)
9. [Error Response Verification](#error-response-verification)
10. [Cross-Cutting Verification](#cross-cutting-verification)
11. [SEP-Specific Checklists](#sep-specific-checklists)

---

## openapi spec query Cheat Sheet

All queries run against the bundled file. Use `--format markdown` for structured output, `to-yaml` for full schema details.

| What | Query |
|------|-------|
| All endpoints | `operations \| select name, method, path, deprecated` |
| Auth per endpoint | `operations \| security \| select operation, schemeName, schemeType` |
| Params per endpoint | `operations \| parameters \| select operation, name, in, required, type` |
| Request content types | `operations \| request-body \| content-types \| select operation, mediaType` |
| Response codes | `operations \| responses \| select operation, statusCode, description` |
| Request body fields | `operations \| where(name == "OP") \| request-body \| content-types \| to-schema \| properties \| select name, type` |
| Full param schema | `operations \| where(name == "OP") \| parameters \| where(name == "PARAM") \| to-schema \| to-yaml` |
| Response fields (nested) | `operations \| where(name == "OP") \| responses \| where(statusCode == "200") \| content-types \| to-schema \| properties(*) \| select name, type` |
| Full field schema | `operations \| where(name == "OP") \| responses \| where(statusCode == "200") \| content-types \| to-schema \| properties(*) \| where(name contains "FIELD") \| to-yaml` |

**Notes:**
- The bundled file is fully inlined — `isComponent` is always false, so use operation-based navigation instead
- `properties(*)` recurses into nested objects
- `to-yaml` exposes enums, patterns, maxLength, minimum, descriptions — everything you need for type/validation checks
- Endpoints with `security: []` (public) will NOT appear in the security query — their absence means no auth required

---

## Endpoint Verification

For each endpoint defined in the reference document:

**Query:** `operations | select name, method, path, deprecated`

```
- [ ] Path matches reference (e.g., GET /auth, POST /sep24/transactions/deposit/interactive)
- [ ] HTTP method matches (GET, POST, PUT, DELETE)
- [ ] No unexpected additional methods defined on the path
- [ ] operationId is descriptive and follows naming conventions
- [ ] Tags group the endpoint correctly
```

## Parameter Verification

**Query:** `operations | parameters | select operation, name, in, required, type`
**Deep inspect:** `operations | where(name == "OP") | parameters | where(name == "PARAM") | to-schema | to-yaml`

For each parameter on each endpoint:

```
- [ ] Parameter name matches reference exactly (case-sensitive)
- [ ] Parameter location matches (query, header, path, cookie)
- [ ] required flag matches reference (true for required params, false for optional)
- [ ] Type matches (string, integer, number, boolean)
- [ ] Format matches if specified (date-time, uri, hostname, etc.)
- [ ] Pattern (regex) matches reference constraints
- [ ] maxLength / minLength match reference constraints
- [ ] minimum / maximum match reference constraints
- [ ] enum values match reference exactly (order doesn't matter)
- [ ] default value matches if reference specifies one
- [ ] Description is accurate and matches reference semantics
- [ ] No extra parameters not in the reference (unless documented as extensions)
- [ ] No missing parameters from the reference
```

## Request Body Verification

**Query (content types):** `operations | request-body | content-types | select operation, mediaType`
**Query (fields):** `operations | where(name == "OP") | request-body | content-types | to-schema | properties | select name, type`

For each endpoint that accepts a request body:

```
- [ ] Content types match reference (application/json, application/x-www-form-urlencoded, multipart/form-data)
- [ ] required flag on the requestBody matches
- [ ] Schema name matches conventions (e.g., DepositRequest, TokenRequest)
- [ ] Every field from the reference is present in the schema
- [ ] required array lists exactly the fields the reference marks as required
- [ ] Each field's type matches the reference
- [ ] Each field's $ref points to the correct scalar/component
- [ ] additionalProperties setting is documented if it differs from reference
- [ ] No extra fields not in the reference (unless documented as extensions)
```

## Response Verification

**Query (status codes):** `operations | responses | select operation, statusCode, description`
**Query (response fields):** `operations | where(name == "OP") | responses | where(statusCode == "200") | content-types | to-schema | properties(*) | select name, type`
**Deep inspect:** `operations | where(name == "OP") | responses | where(statusCode == "200") | content-types | to-schema | properties(*) | where(name contains "FIELD") | to-yaml`

For each endpoint's success response:

```
- [ ] HTTP status code matches (200, 201, etc.)
- [ ] Content-Type matches (application/json, text/plain, etc.)
- [ ] Schema name follows conventions
- [ ] Every field from the reference is present
- [ ] required array matches reference
- [ ] Nested object schemas are correctly structured
- [ ] Array schemas have appropriate maxItems
- [ ] $ref chains resolve to correct types
```

## Authentication Verification

**Query:** `operations | security | select operation, schemeName, schemeType`
(Endpoints NOT in this output have `security: []` — i.e., they are public/unauthenticated.)

```
- [ ] Public endpoints have security: [] (overriding any global security)
- [ ] Authenticated endpoints have security: [{sep10Auth: []}] (or equivalent)
- [ ] Security scheme definition matches reference (type, scheme, bearerFormat)
- [ ] 403 AuthRequired response defined on endpoints that require auth
- [ ] AuthRequired response schema matches reference ({type: "authentication_required"})
```

## Type & Scalar Verification

For each named scalar/type in the spec:

```
- [ ] Type matches reference (string, number, integer, boolean)
- [ ] Pattern (regex) correctly validates the format the reference describes
- [ ] maxLength is appropriate for the data the reference describes
- [ ] Enum values match reference exactly
- [ ] Format matches if applicable (uri, date-time, hostname, etc.)
- [ ] Example values are valid instances of the type
```

### Common Stellar types to verify:

| Type | Expected Pattern | maxLength | Notes |
|------|-----------------|-----------|-------|
| AssetCode | `^[a-zA-Z][a-zA-Z0-9]{0,11}$` | 12 | 1-12 chars, letter start |
| Amount | `^[0-9]+(\.[0-9]+)?$` | 32 | String for decimal precision |
| StellarPublicKey | `^G[A-Z2-7]{55}$` | 56 | G... only (Ed25519) |
| StellarAccountId | `^[GMC][A-Z2-7]{55,68}$` | 69 | G/M/C... (includes contracts) |
| StellarTransactionHash | `^[0-9a-f]{64}$` | 64 | Lowercase hex |
| MemoType | enum [text, id, hash] | — | Exactly 3 values |
| TransactionId | `^[a-zA-Z0-9_-]+$` | 128 | Alphanumeric + dash/underscore |
| Lang | `^[a-zA-Z]{2,3}(-[a-zA-Z0-9]+)*$` | 16 | RFC 4646 |
| Sep38AssetId | `.+` | 128 | scheme:identifier format |

## Deprecated Field Verification

```
- [ ] Every field the reference marks as deprecated has deprecated: true in the spec
- [ ] Deprecated fields are NOT in the required array
- [ ] Deprecated endpoints have deprecated: true on the operation
- [ ] Description mentions deprecation and suggests alternative
```

## Error Response Verification

```
- [ ] All error status codes from the reference are defined
- [ ] Error response schemas match reference format ({error: string})
- [ ] No error codes that contradict the endpoint's security setting (e.g., 401 on security: [])
- [ ] 404 only on endpoints where the reference specifies "not found" behavior
- [ ] Rate-limit responses (429) include Retry-After header
```

## Cross-Cutting Verification

```
- [ ] Server URL uses HTTPS (https://{domain})
- [ ] CORS headers defined or documented as infrastructure concern
- [ ] Global security scheme matches reference auth mechanism
- [ ] Rate-limit headers are reasonable additions (not conflicting with reference)
- [ ] additionalProperties: false is documented as a known constraint where it blocks extensibility
```

---

## SEP-Specific Checklists

### SEP-1 (Discovery) Checklist

```
1.  Endpoint: GET /.well-known/stellar.toml
2.  Method: only GET, no other methods
3.  Auth: security: [] (public)
4.  Response Content-Type: text/plain
5.  Response max size: maxLength matches SEP-1 100KB limit (102400)
6.  Response schema: opaque type: string (TOML not structurally representable)
7.  CORS: Access-Control-Allow-Origin: * header on 200 response
8.  Example: includes representative TOML fields
9.  Error responses: check appropriateness for a public endpoint
10. Rate-limit headers: acceptable additions, not required by SEP
```

### SEP-10 (Web Auth) Checklist

GET /auth (Challenge):
```
1.  Path: /auth (or configurable WEB_AUTH_ENDPOINT)
2.  Auth: security: [] (unauthenticated)
3.  account param: required, pattern ^[GM] (NOT ^[GMC] — SEP-10 excludes contracts)
4.  memo param: optional, pattern ^[0-9]+$ (id-type only), G-only restriction
5.  home_domain param: optional, format hostname, maxLength 253
6.  client_domain param: optional, format hostname, maxLength 253
7.  No extra params beyond these 4
8.  ChallengeResponse: transaction (required, base64 XDR), network_passphrase (optional)
9.  additionalProperties: false on response schema
10. Response Content-Type: application/json
```

POST /auth (Token):
```
11. Auth: security: [] (unauthenticated)
12. TokenRequest: transaction (required, base64, maxLength 16384)
13. Content types: application/json AND application/x-www-form-urlencoded (both required)
14. No multipart/form-data
15. TokenResponse: token (required, JWT pattern, maxLength 4096)
16. JWT claims documented: iss, sub, iat, exp, client_domain (optional)
```

Errors & Security:
```
17. GET errors: 400, 401, 403, 429, 500
18. POST errors: 400, 401, 429, 500 (NO 403 on POST)
19. Security scheme: HTTP bearer, JWT format
20. CORS headers: check presence (typically infrastructure concern)
```

### SEP-24 (Interactive Transfer) Checklist

Endpoints & Methods:
```
1.  GET /sep24/info
2.  POST /sep24/transactions/deposit/interactive
3.  POST /sep24/transactions/withdraw/interactive
4.  GET /sep24/fee (must be deprecated)
5.  GET /sep24/transactions
6.  GET /sep24/transaction
```

Authentication:
```
7.  /info: security: [] (unauthenticated)
8.  All other endpoints: security: [{sep10Auth: []}]
9.  403 AuthRequired response on authenticated endpoints
```

GET /info Response:
```
10. InfoResponse: deposit, withdraw, fee, features fields
11. deposit/withdraw: dynamic asset code maps -> AssetOperation
12. AssetOperation: enabled (req bool), min_amount, max_amount, fee_fixed, fee_percent, fee_minimum
13. fee: enabled, authentication_required booleans
14. features: account_creation (default true), claimable_balances (default false)
```

POST Deposit (DepositRequest):
```
15. asset_code: required, AssetCode ref
16. asset_issuer: optional, StellarPublicKey (G... only)
17. source_asset: optional, Sep38AssetId
18. amount: optional, number >= 0
19. quote_id: optional, QuoteId
20. account: optional, StellarAccountId (G/M/C per SEP-24)
21. memo_type: optional, MemoType [text, id, hash]
22. memo: optional, string, maxLength 64
23. wallet_name: optional, deprecated: true
24. wallet_url: optional, deprecated: true
25. lang: optional, Lang
26. claimable_balance_supported: optional, boolean
27. customer_id: optional, CustomerId
28. Content types: at least multipart/form-data (JSON and form-urlencoded acceptable additions)
29. additionalProperties setting (false blocks SEP-9 — document as trade-off)
```

POST Withdraw (WithdrawRequest):
```
30. asset_code: required
31. destination_asset (NOT source_asset): optional, Sep38AssetId
32. amount, quote_id, account: correct types
33. memo, memo_type: BOTH deprecated: true
34. wallet_name, wallet_url: BOTH deprecated: true
35. lang, customer_id: present
36. refund_memo: optional, string, maxLength 64
37. refund_memo_type: optional, MemoType
```

InteractiveResponse:
```
38. type: enum [interactive_customer_info_needed] ONLY (no "success" — that's SEP-6)
39. url: required, format uri, maxLength 2048
40. id: required, TransactionId
```

GET /fee (Deprecated):
```
41. deprecated: true flag
42. Parameters: operation (enum), type (optional), asset_code, amount
43. FeeResponse: fee (required, number >= 0)
```

GET /transactions:
```
44. Parameters: asset_code (req), no_older_than, limit (1-1000), kind (enum), paging_id, lang
45. Response: TransactionsResponse with transactions array, maxItems 1000
```

GET /transaction:
```
46. Parameters: id, stellar_transaction_id, external_transaction_id (all optional), lang
47. "At least one" constraint (OpenAPI 3.0.3 limitation — document)
48. 404 response defined
```

Transaction Schema:
```
49. Required: [id, kind, status, more_info_url, started_at]
50. kind enum: [deposit, withdrawal]
51. TransactionStatus: all 16 values
52. All shared fields present with correct types
53. Deposit-specific: from, to, deposit_memo, deposit_memo_type, claimable_balance_id
54. Withdrawal-specific: withdraw_anchor_account, withdraw_memo, withdraw_memo_type, from, to
55. Deprecated fields: amount_fee, amount_fee_asset, refunded (all deprecated: true)
```

FeeDetails & Refunds:
```
56. FeeDetails: required [total, asset], optional breakdown array
57. FeeBreakdown: required [name, amount], optional description
58. Refunds: required [amount_refunded, amount_fee, payments]
59. RefundPayment: required [id, id_type, amount, fee], id_type enum [stellar, external]
```

Scalar Types:
```
60. AssetCode: pattern, maxLength 12
61. Amount: string pattern (decimal precision)
62. StellarPublicKey: G-only pattern, maxLength 56
63. StellarAccountId: G/M/C pattern, maxLength 69
64. StellarTransactionHash: hex pattern, maxLength 64
65. MemoType: enum [text, id, hash]
66. TransactionId, QuoteId, CustomerId: alphanumeric pattern, maxLength 128
```

Cross-cutting:
```
67. CORS headers (typically infrastructure — flag as INFO)
68. Server URL: https://
69. Error format: {error: string}
```
