---
name: openapi-writer
description: "Skill for writing, editing, reviewing, and validating OpenAPI specifications. Use this skill whenever the user mentions OpenAPI, API specs, API specifications, Swagger, REST API documentation, API design, API contracts, writing a spec, designing endpoints, or any task involving .yaml/.yml/.json files that describe HTTP APIs. Even if the user just says 'write an API spec' or 'document my endpoints' or 'create the API contract', this skill applies. Trigger it early — it's better to load this and not need it than to miss an OpenAPI task."
---

# OpenAPI Specification Writer

You write, edit, review, and validate OpenAPI specifications. You produce clean, correct, well-organized specs that follow the OpenAPI 3.1.x standard and official best practices.

## Core Principles

**Design-first**: Write the spec before (or independent of) implementation. The spec is the contract — it defines what the API should do, and implementation follows. This prevents building APIs that can't be properly described.

**Single source of truth**: The spec file is the authoritative description of the API. Don't duplicate information across code annotations and spec files.

**DRY with components**: Any schema, response, parameter, or security scheme used more than once belongs in `components`. Reference it with `$ref`. This keeps specs maintainable as they grow.

**Source-control friendly**: Write specs as YAML (not JSON) for readability and cleaner diffs. Use literal block scalars (`|`) for multi-line descriptions.

## Workflow

### 1. Understand the API

Before writing anything, clarify:
- What resources/entities does the API manage?
- What operations are needed (CRUD, search, batch, etc.)?
- What authentication/authorization model?
- What are the error scenarios?
- Are there pagination, filtering, or sorting needs?

If the user hasn't provided this, ask targeted questions — but don't over-interrogate. Start writing once you have enough to produce a useful first draft.

### 2. Write the Spec

Use YAML format. Target OpenAPI 3.1.0 unless the user requests otherwise.

**Structure the file in this order:**
1. `openapi` + `info`
2. `servers`
3. `tags`
4. `security` (global)
5. `paths` (grouped by resource, ordered logically)
6. `components` (schemas, responses, parameters, securitySchemes)

**Naming conventions:**
- Schemas: PascalCase (`User`, `OrderItem`, `CreateUserRequest`)
- Path parameters: camelCase or snake_case (match the user's existing API style)
- Operation IDs: camelCase verbs (`listUsers`, `getUserById`, `createOrder`)
- Tags: Title Case (`Users`, `Order Management`)

**For every endpoint, include:**
- `operationId` — unique, descriptive
- `summary` — one line
- `description` — if the operation has non-obvious behavior
- `tags` — at least one
- `parameters` — with descriptions and constraints
- `requestBody` — with required schemas and an example
- `responses` — success case + relevant error cases (400, 401, 403, 404, 409, 5XX as appropriate)

**For every schema, include:**
- `type` with appropriate constraints (`minLength`, `maximum`, `pattern`, etc.)
- `required` array listing mandatory fields
- `description` on non-obvious fields
- `format` where applicable (`uuid`, `email`, `date-time`, `uri`, etc.)
- `example` values on leaf schemas or `examples` on media types

### 3. Validate and Lint

After writing or editing a spec, always validate it using the `openapi` CLI (see "CLI availability" below if the CLI is missing):

```bash
# Validate correctness against the OpenAPI specification
openapi spec validate ./spec.yaml

# Lint for style, security, and best practices
openapi spec lint ./spec.yaml
```

Fix any errors or warnings before presenting the spec to the user. If there are linting warnings that are intentional (e.g., the user chose a specific pattern), note them.

### 4. Review Checklist

Before finalizing, verify:
- [ ] All `$ref` references resolve to existing components
- [ ] Every path parameter has a matching `{param}` in the URL
- [ ] `required: true` is set on all path parameters
- [ ] Schemas use appropriate constraints (not just bare `type: string`)
- [ ] Error responses are consistent (same Error schema across endpoints)
- [ ] Security is applied globally and overridden per-operation where needed
- [ ] No duplicate schemas — extract to components
- [ ] `operationId` is unique across all operations
- [ ] Examples are realistic, not placeholder values

## Specification Reference

For detailed guidance on any part of the spec (schemas, security types, parameter serialization, etc.), read `references/spec-guide.md`. It covers:

- Document structure and root object
- Info, servers, and server variables
- Paths, operations, and HTTP methods
- Parameters (path, query, header, cookie) with serialization
- Request bodies and content negotiation
- Schema objects (primitives, arrays, objects, composition with allOf/oneOf/anyOf)
- Responses and status code patterns
- Components and `$ref` references
- Security schemes (API key, HTTP, OAuth 2.0, OpenID Connect, mutual TLS)
- Tags and operation grouping
- Documentation fields, CommonMark, and examples

## CLI Tooling

### CLI availability

Before you use a command in this section, run `command -v openapi`. If the CLI is missing:

1. Skip the CLI validation, lint, bundle and query steps.
2. Validate by reading the YAML directly: check YAML syntax, required fields (`openapi`, `info`, `paths`), that each `$ref` resolves, and that each path parameter is declared.
3. Tell the user which steps you skipped. Hint: install the `openapi` CLI used locally.

If the CLI is present, use these commands as part of your workflow:

### Validation and Linting

```bash
# Validate an OpenAPI specification
openapi spec validate ./spec.yaml

# Lint for style, security, and best practices
openapi spec lint ./spec.yaml

# Lint with custom configuration
openapi spec lint --config lint.yaml ./spec.yaml
```

### Bundling and Inlining

When a spec uses external `$ref` references across multiple files:

```bash
# Bundle external references into components section
openapi spec bundle ./spec.yaml ./bundled-spec.yaml

# Inline all references to create a self-contained document
openapi spec inline ./spec.yaml ./inlined-spec.yaml
```

### Upgrading

```bash
# Upgrade OpenAPI spec to latest version
openapi spec upgrade ./spec.yaml ./upgraded-spec.yaml

# Upgrade Swagger 2.0 to OpenAPI 3.0
openapi swagger upgrade ./api.swagger.yaml ./openapi.yaml
```

### Overlays

```bash
# Apply an overlay to a specification
openapi overlay apply --overlay overlay.yaml --schema spec.yaml
```

### Querying the Schema Graph

Useful for understanding large specs and assessing impact of changes:

```bash
# Find deeply nested components
openapi spec query 'schemas | where(isComponent) | sort-by(depth, desc) | take(10) | select name, depth' ./spec.yaml

# Blast radius of a schema change
openapi spec query 'schemas | where(name == "Error") | blast-radius | length' ./spec.yaml
```

### Swagger and Arazzo

```bash
# Validate a Swagger 2.0 document
openapi swagger validate ./api.swagger.yaml

# Validate an Arazzo workflow document
openapi arazzo validate ./workflow.arazzo.yaml
```

## Common Patterns

### Pagination

```yaml
components:
  schemas:
    PaginatedResponse:
      type: object
      required: [data, pagination]
      properties:
        data:
          type: array
          items: {}    # Override with allOf in specific responses
        pagination:
          $ref: "#/components/schemas/Pagination"
    Pagination:
      type: object
      required: [total, limit, offset]
      properties:
        total:
          type: integer
          minimum: 0
          description: Total number of items
        limit:
          type: integer
          minimum: 1
          maximum: 100
        offset:
          type: integer
          minimum: 0
  parameters:
    LimitParam:
      name: limit
      in: query
      schema:
        type: integer
        minimum: 1
        maximum: 100
        default: 20
    OffsetParam:
      name: offset
      in: query
      schema:
        type: integer
        minimum: 0
        default: 0
```

### Consistent Error Responses

```yaml
components:
  schemas:
    Error:
      type: object
      required: [code, message]
      properties:
        code:
          type: integer
          description: HTTP status code
          example: 404
        message:
          type: string
          description: Human-readable error message
          example: "Resource not found"
        details:
          type: array
          items:
            type: object
            properties:
              field:
                type: string
              reason:
                type: string
  responses:
    BadRequest:
      description: Invalid request parameters
      content:
        application/json:
          schema:
            $ref: "#/components/schemas/Error"
          example:
            code: 400
            message: "Validation failed"
            details:
              - field: email
                reason: "Invalid email format"
    NotFound:
      description: Resource not found
      content:
        application/json:
          schema:
            $ref: "#/components/schemas/Error"
    Unauthorized:
      description: Authentication required
      content:
        application/json:
          schema:
            $ref: "#/components/schemas/Error"
    Forbidden:
      description: Insufficient permissions
      content:
        application/json:
          schema:
            $ref: "#/components/schemas/Error"
```

### Filter Parameters

```yaml
components:
  parameters:
    SortParam:
      name: sort
      in: query
      description: "Field to sort by, prefix with - for descending"
      schema:
        type: string
        example: "-created_at"
    FilterParam:
      name: status
      in: query
      description: Filter by status
      schema:
        type: string
        enum: [active, inactive, pending]
```

## Multi-File Specs

For large APIs, split the spec across files:

```
api/
  openapi.yaml          # Root document with paths and top-level config
  components/
    schemas/
      User.yaml
      Order.yaml
    responses/
      errors.yaml
    parameters/
      pagination.yaml
```

Reference with relative paths: `$ref: "./components/schemas/User.yaml"`. When the spec is ready for distribution, bundle it:

```bash
openapi spec bundle ./api/openapi.yaml ./dist/openapi.yaml
```
