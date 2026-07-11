# State Management

State management conventions for React SPAs.

## State Categories

| Category | Tool | Purpose |
|----------|------|---------|
| **Server state** | React Query v5 | API data (fetching, caching, invalidation) |
| **Client/UI state** | Zustand 5 | Application state (UI selections, flags, temporary data) |
| **Form state** | React Hook Form v7 | Form values, validation, submission |
| **Global config** | React Context | Locale, currency, DataDog |

## React Query (Server State)

### Defaults

Configured in `src/providers/AppProviders.tsx`:

```typescript
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 60_000,           // 1 minute
      gcTime: 300_000,             // 5 minutes
      retry: 2,
      refetchOnWindowFocus: false,
    },
  },
})
```

Tests override: `retry: false`, `staleTime: 0`

### Query Pattern

```typescript
const useItems = (filters: ItemFilters) => {
  return useQuery({
    queryKey: ['items', filters],
    queryFn: ({ signal }) => itemsApi.search(filters, signal),
    enabled: !!filters.category,
  })
}
```

**Rules:**
- Always pass `signal` for cancellation support
- Use `enabled` to prevent queries when dependencies are missing
- Include all parameters that affect data in `queryKey`

### Mutation Pattern

```typescript
const useUpdateItem = () => {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (data: UpdateItemInput) => itemsApi.update(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['items'] })
    },
  })
}
```

**Rules:**
- Invalidate related queries on mutation success
- Use `onError` for error handling when needed
- Keep mutation functions focused (one API call)

### Query Key Conventions

```typescript
// Domain-based, hierarchical
['items']
['items', itemId]
['items', { category, filter }]
['users', userId]
```

## Zustand (Client State)

### Store Pattern

Source: `src/stores/`

```typescript
// src/stores/itemsStore.ts
import { create } from 'zustand'

interface ItemsState {
  selectedItemId: string | null
  sortBy: 'name' | 'date' | 'price'
  actions: {
    selectItem: (id: string) => void
    setSortBy: (sort: ItemsState['sortBy']) => void
    reset: () => void
  }
}

const initialState = {
  selectedItemId: null,
  sortBy: 'name' as const,
}

export const useItemsStore = create<ItemsState>((set) => ({
  ...initialState,
  actions: {
    selectItem: (id) => set({ selectedItemId: id }),
    setSortBy: (sortBy) => set({ sortBy }),
    reset: () => set(initialState),
  },
}))
```

**Rules:**
- Expose mutations through `actions` object
- Define `initialState` separately for easy reset
- Export `reset()` action for test cleanup
- Name stores with `use` prefix + `Store` suffix: `useItemsStore`

### Using Stores in Components

```typescript
// Select specific state (prevents unnecessary re-renders)
const selectedItemId = useItemsStore((s) => s.selectedItemId)
const { selectItem } = useItemsStore((s) => s.actions)

// Bad, subscribes to entire store
const store = useItemsStore()
```

### Testing Zustand Stores

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

**Always reset store state in `beforeEach`** to prevent test pollution.

## React Context (Global Config)

### Available Contexts

| Context | Hook | Provides |
|---------|------|----------|
| `LocaleContext` | `useLocale()` | `locale`, `dir`, `isRtl` |
| `CurrencyContext` | `useCurrency()` | Current currency selection |
| `DatadogContext` |, | DataDog RUM integration |

### Usage

```typescript
const { locale, dir, isRtl } = useLocale()

return (
  <div dir={dir}>
    <Text>{isRtl ? 'Arabic layout' : 'English layout'}</Text>
  </div>
)
```

**Rules:**
- Context is for truly global, rarely-changing values
- Don't use Context for frequently-updated state (use Zustand)
- Don't use Context for server data (use React Query)

## State Decision Guide

```
Is it from the server (API)?
  → YES: React Query

Is it form input/validation?
  → YES: React Hook Form + Zod

Is it global config (locale, currency)?
  → YES: React Context

Is it UI/application state?
  → YES: Zustand store
```
