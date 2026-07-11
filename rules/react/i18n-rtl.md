---
alwaysApply: false
---
# Internationalization (i18n) & RTL Support

Conventions for multilingual support with RTL.

## Overview

- **Languages:** English (`en`) + Arabic (`ar`)
- **Framework:** react-i18next with i18next
- **RTL:** Arabic is right-to-left; English is left-to-right
- **Locale source:** URL parameter `/:lang?` drives language selection

## Translation Files

| File | Language |
|------|----------|
| `src/i18n/locales/en.json` | English |
| `src/i18n/locales/ar.json` | Arabic |

**All user-facing strings MUST exist in both files.** This is non-negotiable.

## Adding Translations

### Step 1: Add keys to both files

```json
// en.json
{
  "items": {
    "selectItem": "Select Item",
    "noResults": "No items found"
  }
}

// ar.json
{
  "items": {
    "selectItem": "اختر عنصر",
    "noResults": "لا توجد عناصر"
  }
}
```

### Step 2: Use in component

```tsx
const { t } = useTranslation()

<Text variant="title-md">{t('items.selectItem')}</Text>
<Text variant="body-sm">{t('items.noResults')}</Text>
```

## Key Structure

Use semantic, nested keys following existing patterns:

```
common.*         , Shared (buttons, actions: save, cancel, next, back)
forms.*          , Form labels, placeholders
errors.*         , Error messages
validation.*     , Validation messages
users.*          , User-related
items.*          , Item/product-related
```

## Rules

1. **Never hardcode** user-facing text, always use `t('key')`
2. **Never split sentences** across multiple `t()` calls, use interpolation
3. **Add translations in the same commit** as the component that uses them
4. **Validation messages** in Zod schemas use i18n keys as the message string
5. **Interpolation** for dynamic values: `t('common.welcome', { name: userName })`

```tsx
// Good, single t() call with interpolation
<Text>{t('common.itemCount', { count: items.length })}</Text>

// Bad, split sentence
<Text>{t('common.showing')} {items.length} {t('common.items')}</Text>
```

## RTL Support

### useLocale Hook

```tsx
import { useLocale } from '@/contexts/LocaleContext'

const MyComponent = () => {
  const { locale, dir, isRtl } = useLocale()

  return (
    <div dir={dir}>
      {/* Content automatically flows RTL for Arabic */}
    </div>
  )
}
```

### RTL Checklist for New Components

- [ ] Apply `dir={dir}` to container elements
- [ ] Use logical CSS properties (`ms-*`, `me-*`, `ps-*`, `pe-*`) instead of physical (`ml-*`, `mr-*`)
- [ ] Rotate directional icons: `cn(dir === 'rtl' && 'rotate-180')`
- [ ] Let `dir="rtl"` handle flex direction naturally
- [ ] Test component in both English and Arabic layouts
- [ ] Verify Arabic text has proper line-height (1.5-1.8x)

### Directional Icons

```tsx
const { dir } = useLocale()

// Arrows, chevrons, and directional indicators
<ChevronRight className={cn('h-4 w-4', dir === 'rtl' && 'rotate-180')} />
<ArrowRight className={cn('h-4 w-4', dir === 'rtl' && 'rotate-180')} />
```

### Logical Properties

```tsx
// Always use logical properties for directional spacing
<div className="ms-auto">     {/* margin-inline-start */}
<div className="me-4">        {/* margin-inline-end */}
<div className="ps-2">        {/* padding-inline-start */}
<div className="pe-2">        {/* padding-inline-end */}

// Use start/end for positioning
<div className="text-start">  {/* text-align: start */}
<div className="float-end">   {/* float: inline-end */}
```

## Common Mistakes

- Adding to `en.json` but forgetting `ar.json` (or vice versa)
- Using `isArabic` ternaries instead of translation keys
- Splitting sentences across multiple `t()` calls
- Using physical CSS properties (`ml-*`, `mr-*`) instead of logical
- Manually reversing flex with `flex-row-reverse` instead of using `dir` attribute
- Branching on locale for data fields (backend should localize)
- Not testing RTL layout after implementing a new component
