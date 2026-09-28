# OpenAPI Specification Reference Guide

Comprehensive reference for writing correct OpenAPI 3.1.x specifications. Read the relevant section when you need details on a specific aspect of the spec.

## Table of Contents

1. [Document Structure](#document-structure)
2. [Info Object](#info-object)
3. [Servers](#servers)
4. [Paths and Operations](#paths-and-operations)
5. [HTTP Methods](#http-methods)
6. [Parameters](#parameters)
7. [Request Bodies](#request-bodies)
8. [Content and Schemas](#content-and-schemas)
9. [Responses](#responses)
10. [Components and Reuse](#components-and-reuse)
11. [Security](#security)
12. [Tags](#tags)
13. [Documentation Fields](#documentation-fields)

---

## Document Structure

An OpenAPI Description (OAD) is a JSON object written in JSON or YAML. YAML is preferred for readability. Field names are case-sensitive (`openapi` is not `OpenAPI`).

### Root Object (minimum required)

```yaml
openapi: 3.1.0
info:
  title: My API
  version: 1.0.0
paths: {}
```

The root OpenAPI Object requires:
- `openapi` — OAS version string (e.g., `"3.1.0"`)
- `info` — Info Object (see below)
- At least one of: `paths`, `components`, or `webhooks`

Optional root fields: `servers`, `security`, `tags`, `externalDocs`, `jsonSchemaDialect`

---

## Info Object

Required fields:
- `title` — human-readable API name
- `version` — API description version (not the OAS version)

Optional fields: `summary`, `description`, `termsOfService`, `contact`, `license`

```yaml
info:
  title: Acme Payments API
  version: 2.3.1
  summary: Process payments and manage transactions
  description: |
    The Acme Payments API allows merchants to process credit card
    transactions, manage refunds, and view transaction history.
  contact:
    name: API Support
    email: api@acme.com
    url: https://acme.com/support
  license:
    name: Apache 2.0
    url: https://www.apache.org/licenses/LICENSE-2.0.html
```

---

## Servers

Define base URLs where the API is accessible. If omitted, endpoints are relative to the document location.

```yaml
servers:
  - url: https://api.example.com/v1
    description: Production server
  - url: https://staging-api.example.com/v1
    description: Staging environment
  - url: http://localhost:3000/v1
    description: Local development
```

### Server Variables

URLs can contain variables in curly braces:

```yaml
servers:
  - url: https://{environment}.api.example.com:{port}/{version}
    variables:
      environment:
        default: production
        enum:
          - production
          - staging
          - sandbox
        description: Deployment environment
      port:
        default: "443"
        enum:
          - "443"
          - "8443"
      version:
        default: v1
```

Each variable requires a `default`. Use `enum` to restrict values. When server arrays exist at multiple levels (root, path, operation), only the innermost applies.

---

## Paths and Operations

The Paths Object maps URL paths to Path Item Objects. Paths must start with `/`.

```yaml
paths:
  /users:
    get:
      summary: List all users
      responses:
        "200":
          description: Successful response
    post:
      summary: Create a user
      responses:
        "201":
          description: User created
  /users/{id}:
    get:
      summary: Get user by ID
      responses:
        "200":
          description: Successful response
```

### Path Item Object

Contains Operation Objects keyed by HTTP method, plus shared properties:
- `summary`, `description` — apply to all operations on this path
- `parameters` — shared parameters inherited by all operations (can be overridden)
- `servers` — path-level server override

### Operation Object

Key fields:
- `summary` — short description
- `description` — detailed explanation (CommonMark supported)
- `operationId` — unique string identifier for the operation
- `tags` — array of tag names for grouping
- `parameters` — operation-specific parameters
- `requestBody` — request payload description
- `responses` — **required** — expected responses
- `security` — operation-level security (overrides global)
- `deprecated` — boolean, marks as deprecated

---

## HTTP Methods

Standard methods available as operation keys: `get`, `post`, `put`, `delete`, `patch`, `head`, `options`, `trace`.

REST conventions:
- **GET** — retrieve resources (no request body)
- **POST** — create resources
- **PUT** — replace resources entirely
- **PATCH** — partial update
- **DELETE** — remove resources
- **HEAD** — like GET but returns only headers
- **OPTIONS** — describe communication options

---

## Parameters

Parameters are defined in arrays within Path Item and Operation Objects. Each requires `in` and `name`.

### Parameter Locations

**path** — part of the URL, enclosed in `{}`. Must set `required: true`:
```yaml
parameters:
  - name: userId
    in: path
    required: true
    schema:
      type: string
      format: uuid
```

**query** — appended to the query string:
```yaml
parameters:
  - name: limit
    in: query
    schema:
      type: integer
      minimum: 1
      maximum: 100
      default: 20
```

**header** — sent as custom HTTP header (case-insensitive names):
```yaml
parameters:
  - name: X-Request-ID
    in: header
    schema:
      type: string
      format: uuid
```

**cookie** — sent in the Cookie header:
```yaml
parameters:
  - name: session_id
    in: cookie
    schema:
      type: string
```

### Parameter Type

Exactly one of `schema` or `content` must be present. Use `schema` for simple types, `content` for complex serialization.

### Serialization

Control with `style` and `explode`:
- `simple` — comma-separated (default for path/header)
- `form` — ampersand-separated (default for query/cookie)
- `label` — dot-prefixed
- `matrix` — semicolon-prefixed

---

## Request Bodies

Specified via `requestBody` in Operation Objects:

```yaml
post:
  summary: Create a user
  requestBody:
    required: true
    description: User object to create
    content:
      application/json:
        schema:
          $ref: "#/components/schemas/CreateUser"
        example:
          name: Jane Doe
          email: jane@example.com
  responses:
    "201":
      description: User created
```

Fields: `content` (required), `description`, `required` (boolean).

---

## Content and Schemas

The `content` field maps media types to Media Type Objects:

```yaml
content:
  application/json:
    schema:
      type: object
      properties:
        id:
          type: string
        name:
          type: string
  application/xml:
    schema:
      type: object
      properties:
        id:
          type: string
```

### Schema Object

Defines data types using JSON Schema vocabulary:

**Primitive types:**
```yaml
# String with constraints
type: string
minLength: 1
maxLength: 255
pattern: "^[a-zA-Z]+$"

# Number with constraints
type: integer
minimum: 0
maximum: 1000
format: int32

# Boolean
type: boolean

# Enum
type: string
enum:
  - active
  - inactive
  - pending
```

**Arrays:**
```yaml
type: array
items:
  type: string
minItems: 1
maxItems: 100
```

**Objects:**
```yaml
type: object
required:
  - id
  - name
properties:
  id:
    type: string
    format: uuid
  name:
    type: string
  email:
    type: string
    format: email
  role:
    type: string
    enum:
      - admin
      - user
      - viewer
additionalProperties: false
```

**Composition:**
```yaml
# allOf — combine schemas (AND)
allOf:
  - $ref: "#/components/schemas/BaseModel"
  - type: object
    properties:
      extra_field:
        type: string

# oneOf — exactly one must match
oneOf:
  - $ref: "#/components/schemas/Cat"
  - $ref: "#/components/schemas/Dog"
discriminator:
  propertyName: petType

# anyOf — at least one must match
anyOf:
  - type: string
  - type: integer
```

**Common formats:** `date-time`, `date`, `email`, `uri`, `uuid`, `ipv4`, `ipv6`, `int32`, `int64`, `float`, `double`, `password`, `byte`, `binary`

---

## Responses

The Responses Object maps HTTP status codes (as quoted strings) to Response Objects:

```yaml
responses:
  "200":
    description: Successful response
    content:
      application/json:
        schema:
          $ref: "#/components/schemas/User"
  "400":
    $ref: "#/components/responses/BadRequest"
  "404":
    description: User not found
  "5XX":
    description: Server error
```

At least one response is required (typically the success case). Wildcards allowed: `1XX`, `2XX`, `3XX`, `4XX`, `5XX`. The `default` key catches unspecified codes.

Response Objects require `description` and optionally include `content`, `headers`, and `links`.

---

## Components and Reuse

The `components` section defines reusable objects referenced via `$ref`:

```yaml
components:
  schemas:
    User:
      type: object
      required: [id, name, email]
      properties:
        id:
          type: string
          format: uuid
        name:
          type: string
        email:
          type: string
          format: email
    Error:
      type: object
      required: [code, message]
      properties:
        code:
          type: integer
        message:
          type: string
  responses:
    NotFound:
      description: Resource not found
      content:
        application/json:
          schema:
            $ref: "#/components/schemas/Error"
    BadRequest:
      description: Invalid request
      content:
        application/json:
          schema:
            $ref: "#/components/schemas/Error"
  parameters:
    PageLimit:
      name: limit
      in: query
      schema:
        type: integer
        minimum: 1
        maximum: 100
        default: 20
    PageOffset:
      name: offset
      in: query
      schema:
        type: integer
        minimum: 0
        default: 0
```

### Reference syntax

```yaml
# Local reference
$ref: "#/components/schemas/User"

# External file
$ref: "./schemas/user.yaml"

# External file with pointer
$ref: "./common.yaml#/components/schemas/Error"

# Remote URL
$ref: "https://api.example.com/schemas/user.yaml"
```

Use components aggressively — any schema, response, parameter, header, request body, or security scheme that appears more than once should be a component. This reduces spec size and maintenance cost.

---

## Security

Define security schemes in `components/securitySchemes`, apply them via `security` at root or operation level.

### API Key
```yaml
components:
  securitySchemes:
    ApiKeyAuth:
      type: apiKey
      in: header          # header, query, or cookie
      name: X-API-Key
security:
  - ApiKeyAuth: []
```

### HTTP Bearer Token
```yaml
components:
  securitySchemes:
    BearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
security:
  - BearerAuth: []
```

### HTTP Basic Auth
```yaml
components:
  securitySchemes:
    BasicAuth:
      type: http
      scheme: basic
```

### OAuth 2.0
```yaml
components:
  securitySchemes:
    OAuth2:
      type: oauth2
      flows:
        authorizationCode:
          authorizationUrl: https://auth.example.com/authorize
          tokenUrl: https://auth.example.com/token
          scopes:
            read:users: Read user data
            write:users: Modify user data
        clientCredentials:
          tokenUrl: https://auth.example.com/token
          scopes:
            admin: Full admin access
security:
  - OAuth2:
      - read:users
```

### OpenID Connect
```yaml
components:
  securitySchemes:
    OpenID:
      type: openIdConnect
      openIdConnectUrl: https://auth.example.com/.well-known/openid-configuration
```

### Combining schemes
```yaml
# Either API key OR OAuth (alternatives = separate items)
security:
  - ApiKeyAuth: []
  - OAuth2:
      - read:users

# Both API key AND OAuth required (same item)
security:
  - ApiKeyAuth: []
    OAuth2:
      - read:users
```

Operation-level `security` overrides global. Use empty array `security: []` to make an operation public.

---

## Tags

Group and organize operations:

```yaml
tags:
  - name: Users
    description: User management operations
  - name: Orders
    description: Order processing operations

paths:
  /users:
    get:
      tags: [Users]
      summary: List users
```

Order tags in the root `tags` array to control documentation ordering. Operations can have multiple tags.

---

## Documentation Fields

### summary vs description
- `summary` — brief, single-sentence (for list views)
- `description` — detailed, supports CommonMark markdown (for expanded views)

### CommonMark in descriptions
```yaml
description: |
  ## Overview
  This endpoint retrieves user data.

  **Important:** Requires authentication.

  ### Response fields
  - `id` — unique identifier
  - `name` — display name

  ```json
  {"id": "abc", "name": "Jane"}
  ```
```

### YAML multi-line strings
- `|` (literal) — preserves line breaks
- `>` (folded) — collapses lines into single line, empty lines become breaks
- Use `|` for descriptions with markdown formatting

### Examples
```yaml
# Single example
schema:
  type: string
  example: "jane@example.com"

# Multiple named examples
content:
  application/json:
    schema:
      $ref: "#/components/schemas/User"
    examples:
      admin:
        summary: Admin user
        value:
          id: "1"
          name: "Admin"
          role: admin
      regular:
        summary: Regular user
        value:
          id: "2"
          name: "Jane"
          role: user
```
