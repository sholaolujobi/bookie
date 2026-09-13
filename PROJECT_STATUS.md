# Project Status

Last updated: 2026-09-13 (session 1)

## Summary

Full CI/CD platform build for the `bookie` project: React frontend + Express
backend, containerized, deployed to ECS Fargate behind an ALB, provisioned
with Terraform, deployed via a Jenkins pipeline on EC2.

**Important deviation from the original brief:** the starter repository URL
given (`https://github.com/pakurumo/techpathway-2`) does not exist (the
`pakurumo` GitHub account does not exist). A corrected guess
(`sholaolujobi/techpathway-2`) also does not exist. Per explicit user
confirmation, the application was **built from scratch** in this repo rather
than forked from a starter. There is no `upstream` remote with usable
content — `upstream` is configured pointing at the originally-given URL for
reference only, and nothing has been or will be pushed to it.

## Completed work

- [x] Confirmed git identity: authenticated GitHub CLI user is
      `sholaolujobi` (owner of the target repo), with push access verified.
- [x] Cloned `bookie` (was empty), added `origin` →
      `https://github.com/sholaolujobi/bookie.git` and `upstream` →
      `https://github.com/pakurumo/techpathway-2.git` (unusable, see above).
- [x] Built Express backend (`backend/`):
      - `GET /api/health` → `{status:"ok"}` (health probe)
      - `GET /api/status` → `{status:"SUCCESS", guid:<uuidv4>, timestamp}`
      - CORS restricted via `CORS_ORIGIN` env var (comma-separated allow-list)
      - Graceful `SIGTERM`/`SIGINT` shutdown
      - Jest + Supertest test suite (4 tests, passing)
- [x] Built React frontend (`frontend/`, Create React App):
      - Fetches `/api/status` on load, renders `SUCCESS` + the GUID
      - `src/config.js`: `API_BASE_URL` from `REACT_APP_API_BASE_URL`,
        defaults to `''` (same-origin) — `.env.development` sets it to
        `http://localhost:8080` for local dev only
      - React Testing Library test suite (2 tests, passing)
      - Production build verified (`npm run build`)
- [x] Dockerized both services:
      - `backend/Dockerfile`: multi-stage, `node:20-alpine`, non-root
        (`node` user), `npm ci --omit=dev`, healthcheck on `/api/health`,
        npm CLI stripped from runtime image, `apk upgrade` for OS patches
      - `frontend/Dockerfile`: multi-stage, CRA build →
        `nginxinc/nginx-unprivileged:1.27-alpine` runtime (non-root, uid
        101), healthcheck on `/healthz`, `apk upgrade` for OS patches
      - `frontend/nginx.conf`: SPA fallback, security headers (CSP, X-Frame-
        Options, X-Content-Type-Options, Referrer-Policy, Permissions-
        Policy), `/healthz`, static asset caching
      - Verified locally: both images build, both containers run and pass
        Docker `HEALTHCHECK`, both work with `--read-only` root filesystem
        (+ tmpfs for `/tmp` etc.) and `--cap-drop ALL`
      - Trivy scan: **0 HIGH/CRITICAL vulnerabilities** in both final images

## Not yet done

- [ ] Terraform infrastructure (`terraform/`)
- [ ] Jenkinsfile
- [ ] AWS deployment (nothing created in AWS yet — no cost incurred)
- [ ] Jenkins EC2 setup / pipeline job
- [ ] README.md and docs/*
- [ ] SECURITY.md, SECURITY_CHECKLIST.md, CODEOWNERS, dependabot.yml
- [ ] Push to `origin`

## Current infrastructure / AWS resources

None created yet. AWS identity confirmed for later use:
- Account ID: `288761770474`
- IAM identity: `arn:aws:iam::288761770474:user/try1`
- Region: `us-east-1`

## Verification results (local)

| Check | Result |
|---|---|
| `npm install` (backend) | ✅ |
| `npm test` (backend, Jest) | ✅ 4/4 passing |
| `npm start` (backend) → `curl /api/health`, `/api/status` | ✅ |
| `npm install` (frontend) | ✅ |
| `npm test` (frontend, RTL) | ✅ 2/2 passing |
| `npm run build` (frontend) | ✅ |
| `docker build` backend | ✅ |
| `docker build` frontend | ✅ |
| Both containers run + Docker healthcheck healthy | ✅ |
| Both containers work `--read-only --cap-drop ALL` | ✅ |
| `curl` backend `/api/status` through container | ✅ returns SUCCESS + guid |
| `curl` frontend `/`, `/healthz`, SPA fallback route | ✅ |
| Security headers present on `/`, `/static/*` | ✅ (fixed an nginx `add_header` inheritance bug — see below) |
| Trivy scan (HIGH,CRITICAL) backend image | ✅ 0 findings |
| Trivy scan (HIGH,CRITICAL) frontend image | ✅ 0 findings |
| `npm audit` backend (prod deps) | 2 moderate (`qs`, via `express`'s dependency tree — no upstream fix yet; low real-world impact, documented as accepted risk) |
| `npm audit` frontend | 30 findings, all in CRA's dev-only build tooling (`webpack-dev-server`/`sockjs`/`jsonpath` chain) — not shipped in the production Nginx image; accepted risk, documented in SECURITY.md |

## Deployed URLs

None yet — not deployed.

## Remaining manual actions

- Terraform apply requires explicit user approval before running (paid AWS
  resources: ALB, EC2, ECS Fargate, EBS). Will present AWS identity, plan
  summary, and cost estimate before asking.
- Jenkins initial admin password must be retrieved manually via SSM Session
  Manager (documented in docs/JENKINS_SETUP.md once written) — never
  committed or logged.

## Known problems

- Fixed during local verification: nginx `add_header` directives do not
  inherit into a location block that defines its own `add_header` — the
  original `nginx.conf` silently dropped security headers on `/` (served via
  the `location = /index.html` fallback) and on `/static/*`. Fixed by
  repeating the full header set in every location that sets its own
  `Cache-Control`.
- `npm ci` in the frontend Docker build initially failed with a lockfile/
  peer-dependency mismatch (`typescript@7.0.2` vs react-scripts' `^3.2.1 ||
  ^4` peer range) because `typescript` was an unpinned transitive/optional
  peer. Fixed by pinning `typescript: ^4.9.5` as an explicit devDependency
  and regenerating the lockfile.

## Exact next step

Write Terraform infrastructure under `terraform/` (networking, security
groups, ECR, IAM, ECS, ALB, Jenkins EC2, logging, outputs), run `fmt`/
`init -backend=false`/`validate`, then present the AWS account/plan/cost
summary to the user for approval before any `terraform apply`.
