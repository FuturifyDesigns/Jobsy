# Jobsy - Find Work or Hire Workers Near You

Built by [Futurify Designs](https://futurifydesigns.com)

## Quick Start (Flutter)

```bash
flutter pub get
flutter run
```

## Web app

```bash
cd web
npm install
cp .env.example .env   # add Supabase URL + anon key
npm run dev
```

## GitHub Pages

GitHub Pages serves the Vite marketing site from the repo root (`index.html` + `site-assets/`). Auth helpers: `email-verified.html`, `reset-password.html`. Deploy: push to `main` (workflow rebuilds) or run `GITHUB_PAGES=true npm run build` in `web/` and sync `dist/` to the root.
