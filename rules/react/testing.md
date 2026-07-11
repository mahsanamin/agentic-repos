# Testing

Conventions for testing React SPAs.

## Stack

| Tool | Purpose |
|------|---------|
| **Vitest 4** | Test runner and assertion library |
| **happy-dom** | DOM environment for unit tests |
| **@vitest/browser-playwright** | Browser tests (real browser, viewport 1440x900) |
| **Testing Library** | Component rendering and accessible queries |
| **@testing-library/user-event** | User interaction simulation |
| **MSW v2** | API mocking (intercepts HTTP requests) |

## Test Types

| Type | File Pattern | Environment | Command |
|------|-------------|-------------|---------|
| Unit/Integration | `*.test.ts`, `*.test.tsx` | happy-dom | `pnpm test` |
| Browser | `*.browser.test.tsx` | Playwright | `pnpm test:e2e` |

## Commands

```bash
pnpm test                           # Watch mode (all tests)
pnpm test src/components/Button.test.tsx   # Specific file
pnpm test:run                       # Single run (CI)
pnpm test:coverage                  # With coverage report
pnpm test:ui                        # Interactive test UI
pnpm test:e2e                       # Playwright browser tests
```

## Test Structure

```typescript
import { describe, expect, it, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'

describe('ItemCard', () => {
  beforeEach(() => {
    // Reset stores, clear mocks
    useItemsStore.getState().actions.reset()
  })

  it('should render item details', () => {
    render(<ItemCard item={mockItem} />, { wrapper: AppProviders })

    expect(screen.getByText('Item Name')).toBeInTheDocument()
    expect(screen.getByText('Description')).toBeInTheDocument()
  })

  it('should call onSelect when clicked', async () => {
    const onSelect = vi.fn()
    const user = userEvent.setup()

    render(<ItemCard item={mockItem} onSelect={onSelect} />, { wrapper: AppProviders })

    await user.click(screen.getByRole('button', { name: /select/i }))

    expect(onSelect).toHaveBeenCalledWith('item-1')
  })
})
```

## Conventions

### Test Names

Use the pattern: `it('should {behavior} when {condition}')`

```typescript
it('should display error message when form is invalid')
it('should redirect to login when token expires')
it('should sort items by price when sort option is clicked')
```

### Queries

Use accessible queries in order of preference:

1. `screen.getByRole()`, buttons, headings, links (preferred)
2. `screen.getByText()`, visible text content
3. `screen.getByLabelText()`, form inputs
4. `screen.getByTestId()`, last resort only

```typescript
// Good, accessible queries
screen.getByRole('button', { name: /save/i })
screen.getByRole('heading', { name: /item details/i })
screen.getByLabelText(/name/i)

// Avoid, test IDs (only when no accessible alternative)
screen.getByTestId('item-card')
```

### Providers

Wrap components with `AppProviders` for full context (React Query, i18n, Router):

```typescript
import { AppProviders } from '@/providers/AppProviders'

render(<MyComponent />, { wrapper: AppProviders })
```

Create fresh `QueryClient` and router instances in tests to avoid state leaks.

### Zustand Store Tests

```typescript
import { useItemsStore } from '@/stores/itemsStore'

describe('itemsStore', () => {
  beforeEach(() => {
    useItemsStore.getState().actions.reset()
  })

  it('should select an item', () => {
    useItemsStore.getState().actions.selectItem('item-1')
    expect(useItemsStore.getState().selectedItemId).toBe('item-1')
  })
})
```

### Schema Tests

```typescript
import { UserProfileSchema } from '@/schemas/forms'

describe('UserProfileSchema', () => {
  it('should accept valid data', () => {
    const result = UserProfileSchema.safeParse(validProfile)
    expect(result.success).toBe(true)
  })

  it('should reject invalid email', () => {
    const result = UserProfileSchema.safeParse({ ...validProfile, email: 'bad' })
    expect(result.success).toBe(false)
  })
})
```

Use `safeParse()`, returns success/error without throwing.

## MSW (Mock Service Worker)

Source: `src/mocks/`

### Handler Pattern

```typescript
// src/mocks/handlers/items.ts
import { http, HttpResponse } from 'msw'
import { itemsSeed } from '@/mocks/seed/items'

export const itemsHandlers = [
  http.get('*/api/v1/items', () => {
    return HttpResponse.json({
      success: true,
      status: 'ok',
      data: itemsSeed.list(),
    })
  }),

  http.post('*/api/v1/items', async ({ request }) => {
    const body = await request.json()
    return HttpResponse.json({
      success: true,
      status: 'ok',
      data: itemsSeed.create(body),
    }, { status: 201 })
  }),
]
```

### Rules

- All mock data via MSW handlers, no hardcoded mock data in components
- Handlers validate responses with the same Zod schemas (`jsonResponse`/`jsonArrayResponse`)
- Keep CRUD parity with real endpoints to avoid silent test failures
- MSW node server is enabled in test setup (`src/test/setup.ts`)
- Use `src/mocks/seed/` for mock data generators (consistent, realistic data)

### Overriding Handlers in Tests

```typescript
import { server } from '@/mocks/server'
import { http, HttpResponse } from 'msw'

it('should show error state on API failure', async () => {
  server.use(
    http.get('*/api/v1/items', () => {
      return HttpResponse.json(
        { success: false, status: 'failed', message: 'Server error' },
        { status: 500 },
      )
    }),
  )

  render(<ItemsPage />, { wrapper: AppProviders })
  expect(await screen.findByText(/server error/i)).toBeInTheDocument()
})
```

## What to Test

- [ ] Component rendering (happy path)
- [ ] User interactions (clicks, form submissions, navigation)
- [ ] Edge cases (empty state, loading, error)
- [ ] API integration (success + error responses via MSW)
- [ ] Zod schema validation (valid + invalid inputs)
- [ ] Store behavior (state changes, selectors)
- [ ] i18n (text rendered from translation keys)
- [ ] RTL layout (if component has directional elements)

## Browser Tests

File pattern: `*.browser.test.tsx`

- Run in real Playwright browser (not happy-dom)
- Viewport: 1440x900
- Setup: `src/test/browser-setup.ts`
- Use for complex interactions, visual regression, and cross-browser testing
