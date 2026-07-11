---
alwaysApply: true
---

# React SPA Project Structure

Standard directory layout for React SPAs. Adapt to your project's specific domain and features.

## Core Directories

```
src/
├── components/      # React components (UI primitives, domain components)
├── hooks/           # Custom React hooks (data fetching, business logic)
├── lib/
│   ├── api/        # API layer (client, endpoints, validation)
│   └── utils/      # Utility functions
├── routes/          # Page/route components
├── schemas/         # Zod schemas (API responses, form validation)
├── stores/          # Zustand stores (client-side state)
├── contexts/        # React Context providers (rarely-changing global state)
├── i18n/            # Translations (if multi-language)
├── mocks/           # MSW handlers (if using MSW)
├── test/            # Test setup and utilities
├── index.css        # Design tokens + global styles
├── main.tsx         # App entry point
└── router.tsx       # Route definitions
```

## Key Patterns

### API Layer (`src/lib/api/`)
- **`client.ts`** - HTTP client (ky) with base URL and auth headers
- **`endpoints/`** - One file per domain, exports typed API objects
- **`validation.ts`** - Zod helpers: `parseRequest()`, `parseResponse()`

### State Management
- **React Query** - Server state (API data, caching, mutations)
- **Zustand** - Client/UI state (selections, UI flags, app state)
- **React Hook Form** - Form state (values, validation, submission)
- **Context** - Global config (locale, theme, rarely-changing values)

### Schemas (`src/schemas/`)
- **`api/`** - Response schemas matching backend contracts
- **`forms.ts`** - Form validation with i18n error keys

### Components (`src/components/`)
- Organize by function: primitives (Button, Dialog), forms (FormField), layout
- Use design tokens from `index.css`, not arbitrary values

### Routes (`src/routes/`)
- Page components, lazy-loaded in `router.tsx`
- Consume hooks, stores, and endpoints

**For project-specific structure details**, create `docs/project-structure.md` in your project.
