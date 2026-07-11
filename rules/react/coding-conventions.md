---
alwaysApply: true
---
# Coding Conventions (TypeScript / React)

Unified coding standards for React SPA development with TypeScript.

---

## Formatting (Biome)

- Line width: **120** characters
- Indentation: **2 spaces** (no tabs)
- Line endings: LF
- Quotes: **single quotes** preferred
- Trailing commas: **all** (functions, arrays, objects)
- Semicolons: as needed (Biome default)
- Arrow functions preferred over function expressions
- Import organization is automatic (Biome handles sorting)

**Tool:** Biome 2 (not ESLint/Prettier). Run `pnpm lint` to check, `pnpm format` to auto-format.

## TypeScript

- **Strict mode** enabled (`strict: true` in tsconfig)
- `noUnusedLocals: true`, no unused variables
- `noUnusedParameters: true`, no unused function parameters
- `noFallthroughCasesInSwitch: true`, switch cases must break/return
- JSX: React 19 automatic runtime (`react-jsx`)
- Module: ESNext with bundler resolution
- Path alias: `@/*` maps to `src/*`

```typescript
// Good, use path alias
import { Button } from '@/components/Button'
import { useAuth } from '@/hooks/useAuth'

// Bad, relative paths for deep imports
import { Button } from '../../../components/Button'
```

## Zod vs Plain Types

- **Use Zod for:** API response parsing, form validation, anything crossing a trust boundary
- **Plain types are fine for:** component props, internal function signatures, React context values, hook return types

```typescript
// Zod, API boundary
const ItemSchema = z.object({
  id: z.string(),
  name: z.string(),
  price: z.number(),
})

// Plain type, component props
interface ItemCardProps {
  item: Item
  onSelect: (id: string) => void
}
```

## File Naming

| Type | Convention | Extension | Example |
|------|-----------|-----------|---------|
| Components | PascalCase | `.tsx` | `ItemCard.tsx` |
| Hooks | camelCase, `use` prefix | `.ts` | `useAuth.ts` |
| Utils/libs | camelCase | `.ts` | `formatCurrency.ts` |
| Schemas | camelCase | `.ts` | `forms.ts`, `items.ts` |
| Tests | match source + `.test` | `.test.ts(x)` | `ItemCard.test.tsx` |
| Browser tests | match source + `.browser.test` | `.browser.test.tsx` | `Login.browser.test.tsx` |
| Stores | camelCase + `Store` | `.ts` | `itemsStore.ts` |
| Constants | camelCase | `.ts` | `constants.ts` |

## Naming Conventions

- **Components:** PascalCase, `ItemCard`, `PageLayout`
- **Hooks:** camelCase with `use` prefix, `useAuth`, `useItems`
- **Functions/variables:** camelCase, `formatPrice`, `isLoading`
- **Constants:** UPPER_SNAKE_CASE for true constants, `MAX_ITEMS`, `API_TIMEOUT`
- **Types/interfaces:** PascalCase, `User`, `ItemSearchParams`
- **Enums:** PascalCase name, PascalCase members, `Status.Active`
- **Translation keys:** dot-separated, hierarchical, `users.firstName`, `common.save`

## Imports

- Use `@/*` path alias for all imports from `src/`
- Biome handles import sorting automatically
- Group conceptually: React → third-party → internal → relative
- Remove unused imports (Biome will flag them)

```typescript
// React and third-party
import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { z } from 'zod'

// Internal (via path alias)
import { apiClient } from '@/lib/api/client'
import { useAuth } from '@/hooks/useAuth'
import { Text } from '@/components/Text'

// Relative (same module)
import { ItemCard } from './ItemCard'
```

## Component Patterns

- Prefer function components with arrow syntax
- Use destructured props
- Prefer HTML/CSS over JS for UI states (hover, focus, disabled)
- Use `<form>` with proper button types (`submit` for primary, `button` for others)
- Use `cn()` (clsx) for conditional class names

```typescript
// Good, clean component with destructured props
const ItemCard = ({ item, onSelect }: ItemCardProps) => {
  const { t } = useTranslation()

  return (
    <div className="rounded-lg border border-line-primary p-4">
      <Text variant="title-md">{item.name}</Text>
      <Text variant="body-sm" color="muted">{item.description}</Text>
      <Button type="button" onClick={() => onSelect(item.id)}>
        {t('common.select')}
      </Button>
    </div>
  )
}
```

## Error Handling

- Use `ApiError` from `src/lib/api/envelope.ts` for API errors
- Access error details: `error.body.message`, `error.body.errorCode`
- Handle 401 responses with automatic auth state clear + redirect
- All API responses must be validated through Zod before use
- Never trust raw data from external sources

## Constants Rule

Same as Java convention: only extract constants if used **3+ times**. Inline values used 1-2 times.

## Pre-Commit Checks

All three must pass before committing:

```bash
pnpm test    # Tests pass
pnpm lint    # Biome check
pnpm check   # tsc --noEmit (type check)
```

## Common Mistakes to Avoid

- Using raw `fetch` instead of the ky `apiClient`
- Skipping `unwrap()` / `parseResponse()` for API responses
- Hardcoding user-facing strings instead of using `t()`
- Adding translations to `en.json` but forgetting `ar.json`
- Using inline styles or arbitrary Tailwind values instead of design tokens
- Creating new typography classes instead of using `Text` component variants
- Committing directly to main instead of a feature branch
- Fabricating data, URLs, or config values, always ask the user
