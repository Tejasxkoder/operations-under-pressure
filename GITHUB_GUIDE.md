# Publishing to GitHub (step by step)

1. Create the repo on https://github.com/new — name it `newtonite-ops-<rollno>`, **Public**, do NOT add a README/.gitignore/licence (they already exist).
2. In a terminal, inside the project folder:
```bash
git init -b main
git add .gitignore .dockerignore .env.example docker-compose.yml Dockerfile
git commit -m "chore: project scaffold, docker compose, env example"
git add backend/package.json backend/tsconfig.json backend/vitest.config.ts backend/src/config.ts backend/src/db.ts backend/src/schema.sql backend/src/migrate.ts
git commit -m "feat(db): schema, indexes, append-only activity log, outbox tables"
git add backend/src/domain.ts backend/src/errors.ts backend/src/permissions.ts backend/src/auth.ts
git commit -m "feat(auth): JWT login and single server-side permission check"
git add backend/src/items.ts backend/src/idempotency.ts backend/src/jobs.ts backend/src/app.ts backend/src/index.ts backend/src/seed.ts
git commit -m "feat(api): work items, claim, versioned edits, workflow, idempotency, outbox worker"
git add backend/tests
git commit -m "test: concurrency, idempotency, workflow, authz and outbox tests"
git add frontend
git commit -m "feat(ui): login, dashboard views, item detail, activity timeline, optimistic actions"
git add README.md ENGINEERING_DECISIONS.md GITHUB_GUIDE.md
git commit -m "docs: README, engineering decisions, known limitations"
git remote add origin https://github.com/<your-username>/newtonite-ops-<rollno>.git
git push -u origin main
```
3. If asked to log in, use a GitHub Personal Access Token as the password (Settings → Developer settings → Tokens), or `gh auth login`.
4. Fresh-clone check: `git clone <url> /tmp/check && cd /tmp/check && docker compose up --build` → open http://localhost:3000.
5. Submit the Google Form with the repo URL.
