---
alwaysApply: true
---
# API Conventions

Standard conventions for consuming REST APIs in a React SPA. See `project-structure.md` for file locations.

## Request Flow

```
Component (hook call)
    |
React Query (useQuery / useMutation)
    |
Endpoint function (src/lib/api/endpoints/*.ts)
    |
parseRequest (Zod), validate outgoing data
    |
ky client (src/lib/api/client.ts), HTTP request + auth headers
    |
parseResponse / unwrap (Zod), validate + extract incoming data
    |
Typed data returned to component
```

## ky HTTP Client

Source: `src/lib/api/client.ts`

- Base URL: `VITE_API_URL` or `https://api.staging.example.com`
- Timeout: 30 seconds
- Auto-injected headers:
  - `Content-Type: application/json`
  - `Accept-Language` (from i18next current language)
  - `Authorization: Bearer <token>` (from PKCE OAuth)

```typescript
import { apiClient } from '@/lib/api/client'

// GET with query params
const response = await apiClient.get('api/v1/items', { searchParams: { filter } })

// POST with body
const response = await apiClient.post('api/v1/items', { json: body })

// With abort signal (React Query cancellation)
const response = await apiClient.get('api/v1/items/123', { signal })
```

**Never use raw `fetch`**, always use the ky `apiClient` for consistent auth, headers, and error handling.

## V2 JSON Envelope Pattern

Source: `src/lib/api/envelope.ts`

Every backend API response follows the V2 envelope format:

```typescript
// Success response
{
  success: true,
  status: "ok",
  data: T  // the actual payload
}

// Error response
{
  success: false,
  status: "failed",
  message: "Human-readable error",
  errorCode: 4001,
  errors: [{ field: "email", message: "Invalid format" }]  // optional
}
```

### Parsing Responses

```typescript
import { unwrap, ApiError } from '@/lib/api/envelope'

// unwrap() extracts data from envelope or throws ApiError
const data = unwrap(ItemSchema, rawJson, response.status)
```

### Error Handling

```typescript
import { ApiError } from '@/lib/api/envelope'

try {
  const data = await itemsApi.search(params)
} catch (error) {
  if (error instanceof ApiError) {
    console.error(error.body.message)      // "Item not found"
    console.error(error.body.errorCode)    // 4001
    console.error(error.body.errors)       // field-level errors
  }
}
```

## Validation at Boundaries

Source: `src/lib/api/validation.ts`

**Always validate data crossing trust boundaries:**

```typescript
import { parseRequest, parseResponse } from '@/lib/api/validation'

// Validate outgoing request data
const body = parseRequest(CreateItemSchema, formData)

// Validate incoming response data
const result = parseResponse(ItemSchema, json, status)
```

**Validation errors:**
- `RequestValidationError`, outgoing data doesn't match schema
- `ResponseValidationError`, incoming data doesn't match schema
- `ApiError`, backend returned an error envelope

## Endpoint Pattern

Source: `src/lib/api/endpoints/`

Each domain has its own endpoint file exporting an API object:

```typescript
// src/lib/api/endpoints/items.ts
import { apiClient } from '@/lib/api/client'
import { unwrap } from '@/lib/api/envelope'
import { ItemSchema, ItemListSchema } from '@/schemas/api/items'

export const itemsApi = {
  async list(signal?: AbortSignal) {
    const response = await apiClient.get('api/v1/items', { signal })
    const json = await response.json()
    return unwrap(ItemListSchema, json, response.status)
  },

  async get(id: string, signal?: AbortSignal) {
    const response = await apiClient.get(`api/v1/items/${id}`, { signal })
    const json = await response.json()
    return unwrap(ItemSchema, json, response.status)
  },

  async create(data: CreateItemInput) {
    const body = parseRequest(CreateItemSchema, data)
    const response = await apiClient.post('api/v1/items', { json: body })
    const json = await response.json()
    return unwrap(ItemSchema, json, response.status)
  },
}
```

**Key rules:**
- One file per domain
- Export a named API object (not default export)
- Always use `unwrap()` to parse responses
- Always pass `signal` for GET requests (React Query cancellation)
- Use `parseRequest()` for POST/PATCH/PUT bodies
- Return typed, unwrapped data (never raw envelope)

## React Query Integration

### Queries (GET)

```typescript
import { useQuery } from '@tanstack/react-query'
import { itemsApi } from '@/lib/api/endpoints/items'

const useItems = () => {
  return useQuery({
    queryKey: ['items'],
    queryFn: ({ signal }) => itemsApi.list(signal),
  })
}
```

### Mutations (POST/PATCH/DELETE)

```typescript
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { itemsApi } from '@/lib/api/endpoints/items'

const useCreateItem = () => {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (data: CreateItemInput) => itemsApi.create(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['items'] })
    },
  })
}
```

### Query Defaults

Configured in `AppProviders.tsx`:

| Setting | Value | Purpose |
|---------|-------|---------|
| `staleTime` | 1 minute | Cache freshness window |
| `gcTime` | 5 minutes | Garbage collection timeout |
| `retry` | 2 | Retry failed requests |
| `refetchOnWindowFocus` | false | No refetch on tab focus |

Tests override: `retry: false`, `staleTime: 0`

### Query Key Conventions

- Use descriptive, hierarchical arrays: `['items', id]`
- Include all parameters that affect the data: `['items', { filter, sort }]`
- Keep consistent across queries and invalidations

## Schema Organization

- **API response schemas:** `src/schemas/api/`, match backend contracts
- **Form validation schemas:** `src/schemas/forms.ts`, with i18n error message keys
- **Common/shared:** `src/schemas/api/common.ts`, V2 envelope, enums, reusable types

```typescript
// src/schemas/api/items.ts
import { z } from 'zod'

export const ItemSchema = z.object({
  id: z.string(),
  name: z.string(),
  description: z.string(),
  createdAt: z.string(),
})

export type Item = z.infer<typeof ItemSchema>
```

## Security Checklist

- [ ] All API responses validated through Zod schemas
- [ ] Auth tokens in localStorage, never logged or exposed
- [ ] 401 responses trigger auth state clear + redirect
- [ ] No raw data from external sources used without validation
- [ ] Environment variables used for API URLs (never hardcoded)
- [ ] `parseRequest` used for outgoing data, `parseResponse`/`unwrap` for incoming
