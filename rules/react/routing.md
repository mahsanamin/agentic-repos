# Routing

Client-side routing conventions with React Router v7.

## Stack

- React Router v7 (client-side only, no SSR)
- Lazy-loaded route components
- Locale-aware URL prefix (optional)

## URL Structure

```
/:lang?/*
```

| Segment | Description | Example |
|---------|-------------|---------|
| `/:lang?` | Optional locale prefix | `/ar/...` or `/...` |
| `/*` | Feature-specific path | `/dashboard`, `/items/:id` |

**Example routes:**
```
/                    → landing page
/:lang/              → landing page with locale
/dashboard           → dashboard
/:lang/items/:id     → item detail with locale
```

## Locale Handling

### LocaleLayout

The `LocaleLayout` component wraps all routes and:
1. Reads `/:lang?` from the URL
2. Sets i18next language
3. Sets document direction (`dir="ltr"` or `dir="rtl"`)
4. Redirects to default locale if needed

### Preserving Language on Navigation

**Always preserve the `lang` param when navigating:**

```typescript
// Good, preserve lang
const { lang } = useParams()
navigate(`/${lang}/dashboard`)

// Good, use navigation helpers
const { goToDashboard } = useAppNavigation()
goToDashboard()

// Bad, loses language prefix
navigate('/dashboard')
```

### Navigation Helpers

Use `useAppNavigation` hook and routing helpers from `src/lib/routing/` for path building. These automatically preserve the locale prefix.

## Adding a New Route

1. Create route component in `src/routes/`
2. Add route entry in `src/router.tsx` with lazy loading
3. Add translations for page title (if using i18n)
4. Update analytics/monitoring view names if needed
