---
alwaysApply: false
---
# Styling

Styling conventions with Tailwind CSS.

## Stack

- **Tailwind CSS v4** with `@theme` block for design tokens
- **CVA** (class-variance-authority) for component variants
- **`cn()`** (clsx) for conditional class composition

## Design Tokens

Source of truth: `src/index.css`

All colors, fonts, and spacing are defined as CSS custom properties in the `@theme` block. **Never use arbitrary Tailwind values**, always reference design tokens.

### Token Naming Convention

Double-prefix pattern (synced with Figma):

| Category | Prefix | Example Tailwind Class |
|----------|--------|----------------------|
| Text colors | `txt-*` | `text-txt-primary`, `text-txt-secondary` |
| Backgrounds | `bg-*` | `bg-bg-primary`, `bg-bg-secondary-warm` |
| CTA/buttons | `cta-*` | `bg-cta-primary`, `bg-cta-disabled` |
| Icons | `ic-*` | `text-ic-primary`, `text-ic-destructive` |
| Lines/borders | `line-*` | `border-line-primary`, `border-line-destructive` |

```tsx
// Good, using design tokens
<div className="bg-bg-primary text-txt-primary border border-line-primary">
  <Text variant="body-md" color="muted">Description</Text>
</div>

// Bad, arbitrary values
<div className="bg-[#f5f5f5] text-[#333] border-[#ddd]">
  <span className="text-sm text-gray-500">Description</span>
</div>
```

## Typography, Text Component

Source: `src/components/Text.tsx`

**Always use the `Text` component** for typography. Never create custom typography classes.

### Variants

| Variant | HTML Tag | Use Case |
|---------|----------|----------|
| `heading-1` | `h1` | Page titles |
| `heading-2` | `h2` | Section titles |
| `heading-3` | `h3` | Subsection titles |
| `title-lg` | `p` | Large titles |
| `title-md` | `p` | Card titles |
| `title-sm` | `p` | Small titles |
| `title-xs` | `p` | Compact titles |
| `body-lg` | `p` | Large body text |
| `body-md` | `p` | Default body text |
| `body-sm` | `p` | Small body text |
| `body-xs` | `p` | Fine print |
| `label-md` | `span` | Form labels |
| `label-sm` | `span` | Small labels |

### Usage

```tsx
import { Text } from '@/components/Text'

// Basic usage, auto-selects HTML tag
<Text variant="heading-1">Page Title</Text>
<Text variant="body-md">Description paragraph</Text>
<Text variant="label-sm" color="muted">Helper text</Text>

// Override HTML tag when needed
<Text variant="title-md" as="h2">Card Title</Text>

// With color variants
<Text variant="body-sm" color="muted">Secondary text</Text>
<Text variant="body-sm" color="destructive">Error message</Text>
```

## Fonts

| Font | Purpose | Variable |
|------|---------|----------|
| Plus Jakarta Sans | Display / headings | `--font-display` |
| Inter | Body text | `--font-body` |
| Noto Sans Arabic | Arabic text | `--font-arabic-display`, `--font-arabic-body` |

**Arabic text uses increased line-height** (1.5-1.8x vs 1.2-1.4x for Latin scripts).

## Layout

### Shared Components

Create reusable layout components in `src/components/layout/` for consistent page structure across your app.

### Conditional Classes

Use `cn()` for conditional class composition:

```tsx
import { cn } from '@/lib/utils'

<div className={cn(
  'rounded-lg border p-4',
  isSelected && 'border-cta-primary bg-bg-secondary-warm',
  isDisabled && 'opacity-50 cursor-not-allowed',
)}>
```

## RTL-Aware Styling

See `i18n-rtl.md` for complete RTL rules (logical properties, directional icons, flex direction).

## Best Practices

- **Prefer CSS over JS** for interaction states (hover, focus, disabled)
- **Use design tokens**, never hardcode colors or arbitrary values
- **Use `Text` component**, never create custom typography with raw className
- **Use layout components**, avoid hardcoded widths in feature components
- **Use `cn()`** for conditional classes, never string concatenation
- **Use logical properties**, never physical margin/padding for directional layout
- **Avoid custom CSS**, Tailwind utilities should cover 99% of cases
