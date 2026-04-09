# Portal Merge Checklist

## Goal
Serve the DCapX public site and authenticated portal from one domain:

- `/` -> Next.js
- `/api/*` -> Express API

## Required routes to verify
- `/login`
- `/register`
- `/forgot-password`
- `/reset-password`
- `/app/onboarding`
- `/app/verify-contact`
- `/app/consents`
- `/app/kyc`

## Browser API calls
Use same-origin in production:
- `NEXT_PUBLIC_API_BASE_URL=` (empty)

## Internal server-side API calls
Use:
- `API_INTERNAL_URL=http://127.0.0.1:4010`

## Build commands
```bash
pnpm --filter api build
pnpm --filter web build
