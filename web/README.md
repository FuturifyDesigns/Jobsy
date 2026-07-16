# Jobsy Web

React + Vite web client for Jobsy — marketing site + authenticated app against the same Supabase backend as the Flutter app.

## Run locally

```bash
cd web
npm install
npm run dev
```

Open the URL Vite prints (usually http://localhost:5173).

## Env

Copy `.env` values:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

In Supabase Auth → URL configuration, add:

- Site URL: `http://localhost:5173`
- Redirect: `http://localhost:5173/**`

## App routes

| Path | Role | Feature |
|------|------|---------|
| `/app` | worker | Find Jobs |
| `/app` | employer | My Jobs |
| `/app/post` | employer | Post job |
| `/app/jobs/:id/applications` | employer | Applications inbox |
| `/app/saved` | worker | Saved jobs |
| `/app/web-jobs` | worker | External listings |
| `/app/wallet` | both | Coming soon |
| `/app/messages` | both | Chat (+ image/file attach) |
| `/app/profile` | both | Edit + role switch |
| `/auth/callback` | — | Google OAuth return |

Google: enable Google provider in Supabase Auth and add `http://localhost:5173/auth/callback` to redirect URLs.

