# Forms

Form handling conventions with React Hook Form + Zod.

## Stack

- **React Hook Form v7**, form state management
- **Zod v3**, schema-based validation
- **`zodResolver`**, connects Zod schemas to RHF

## Form Pattern

```tsx
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'

const UserProfileSchema = z.object({
  name: z.string().min(1, 'validation.required'),
  email: z.string().email('validation.invalidEmail'),
  bio: z.string().optional(),
})

type UserProfileForm = z.infer<typeof UserProfileSchema>

const UserProfilePage = () => {
  const { t } = useTranslation()
  const { control, handleSubmit, formState: { errors } } = useForm<UserProfileForm>({
    resolver: zodResolver(UserProfileSchema),
    defaultValues: { name: '', email: '', bio: '' },
  })

  const onSubmit = (data: UserProfileForm) => {
    // data is fully typed and validated
    updateProfile.mutate(data)
  }

  return (
    <form onSubmit={handleSubmit(onSubmit)} noValidate>
      <FormField name="name" control={control} label={t('forms.name')} error={errors.name?.message} />
      <FormField name="email" control={control} label={t('forms.email')} error={errors.email?.message} />
      <Button type="submit">{t('common.save')}</Button>
    </form>
  )
}
```

## Key Rules

### Form Element

- **Always wrap inputs in `<form noValidate>`**, let Zod handle validation, not browser
- Connect off-form buttons via `form` attribute if needed

### FormField Component

Source: `src/components/forms/FormField`

- Use `FormField` + RHF `Controller` for labels, errors, and loading states
- Input primitives stay dumb (no validation logic)
- FormField handles the connection between RHF and the input

### Button Types

| Type | Use Case |
|------|----------|
| `type="submit"` | Primary form action (save, continue, next) |
| `type="button"` | Secondary actions (cancel, back, add another) |

**Never omit the `type` attribute** on buttons inside forms.

### Form Sections

Use `<fieldset>` + `<legend>` for grouping related fields:

```tsx
<fieldset>
  <legend>{t('forms.personalInfo')}</legend>
  <FormField name="firstName" ... />
  <FormField name="lastName" ... />
</fieldset>
```

Use the `FormSection` component when available.

## Validation

### Zod Schemas

- Define schemas in `src/schemas/forms.ts` or alongside the route component
- Use i18n keys as error messages (not hardcoded strings)
- Compose schemas with `.merge()`, `.extend()`, or `.and()` for shared fields

```typescript
// Good, i18n key as message
const schema = z.object({
  email: z.string().email('validation.invalidEmail'),
  age: z.number().min(18, 'validation.minAge'),
})

// Bad, hardcoded message
const schema = z.object({
  email: z.string().email('Please enter a valid email'),
})
```

### Testing Schemas

```typescript
describe('UserProfileSchema', () => {
  it('should accept valid data', () => {
    const result = UserProfileSchema.safeParse(validData)
    expect(result.success).toBe(true)
  })

  it('should reject invalid email', () => {
    const result = UserProfileSchema.safeParse({ ...validData, email: 'invalid' })
    expect(result.success).toBe(false)
  })
})
```

Use `safeParse()` in tests, it returns success/error without throwing.

## Auto-Save Pattern

```typescript
// Store-based auto-save with debouncing
const { saveData } = useDataStore((s) => s.actions)

useEffect(() => {
  const timer = setTimeout(() => saveData(), 500)
  return () => clearTimeout(timer)
}, [formValues])
```

## Common Mistakes

- Omitting `noValidate` on `<form>` (causes browser validation to interfere)
- Omitting `type` attribute on buttons (defaults to `submit`, causing unintended submits)
- Hardcoding error messages instead of using i18n keys
- Putting validation logic in components instead of Zod schemas
- Forgetting `defaultValues` in `useForm` (causes uncontrolled → controlled warnings)
