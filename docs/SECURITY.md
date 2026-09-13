# Security Details

This document expands on `/SECURITY_CHECKLIST.md` with the reasoning behind
each control and the full list of known/accepted findings.

## Vulnerability scan results (point-in-time, local verification)

### Backend Docker image (`bookie-backend:local`)

```
trivy image --severity HIGH,CRITICAL bookie-backend:local
# 0 vulnerabilities
```

Achieved by stripping the bundled `npm` CLI (and its vendored `tar`/
`pacote`/`sigstore`/`minimatch` dependency tree) out of the runtime image —
the container only ever execs `node`, never `npm` — and running `apk
upgrade` for the latest OpenSSL patches. See `backend/Dockerfile`.

### Frontend Docker image (`bookie-frontend:local`)

```
trivy image --severity HIGH,CRITICAL bookie-frontend:local
# 0 vulnerabilities
```

Achieved with `apk upgrade` on the `nginxinc/nginx-unprivileged:1.27-alpine`
base before dropping to the non-root user. See `frontend/Dockerfile`.

### `npm audit` (backend, production dependencies)

2 moderate findings, both in `qs` (a transitive dependency of Express
4.22.x). No fixed version exists yet on the Express 4.x line. Low real-world
impact: this app never parses complex/attacker-controlled query strings.
Tracked via Dependabot; the Jenkins pipeline gates on `--audit-level=critical`
so this does not block deployments.

### `npm audit` (frontend, all dependencies)

30 findings, all inside Create React App's `react-scripts` dev-tooling
chain (`webpack-dev-server` → `sockjs` → `uuid`; `bfj` → `jsonpath` →
`underscore`). These packages run only during `npm start` / `npm run
build`; the production Docker image copies just the static `build/` output
into an Nginx container and never includes `node_modules`. Tracked via
Dependabot; not gated in CI beyond `--audit-level=critical`.

## Terraform static analysis (`trivy config`)

```
trivy config --severity HIGH,CRITICAL terraform/
```

Findings and their disposition:

| Finding | Disposition |
|---|---|
| `AWS-0164` Subnet associates public IP address | **Accepted.** Deliberate: no NAT Gateway is used (cost constraint), so ECS tasks need public IPs to reach ECR/CloudWatch. Mitigated by security groups restricting inbound to ALB-only. |
| `AWS-0104` Security group allows unrestricted egress (×4 SGs) | **Accepted.** Restricting egress would require VPC interface endpoints (ECR API, ECR DKR, S3, CloudWatch Logs, STS) — an always-on cost not approved for this challenge. Inbound rules remain tightly scoped. |

## Defense in depth for ECS tasks

Verified locally before deployment (see `PROJECT_STATUS.md` verification
table):

```
docker run --read-only --tmpfs /tmp --tmpfs /var/cache/nginx --tmpfs /var/run \
  --cap-drop ALL bookie-frontend:local   # → healthy, serves 200s

docker run --read-only --tmpfs /tmp --cap-drop ALL bookie-backend:local  # → healthy
```

Both images run correctly with a read-only root filesystem and every Linux
capability dropped, matching the ECS task definition configuration in
`terraform/ecs.tf`.

## CORS and same-origin design

The ALB routes both the frontend (default action) and backend (`/api/*`
path rule) from the same DNS name and port, so the browser sees them as the
same origin — CORS is not actually exercised by the deployed app. The
backend still enforces an allow-list (`CORS_ORIGIN` env var, set to
`http://<alb-dns-name>` in `terraform/ecs.tf`) as defense in depth for any
direct API access, e.g. from a script rather than a browser page.

## Jenkins hardening

- Authentication required; anonymous access and public self-registration
  disabled (Jenkins' own security realm, configured in the setup wizard —
  see `docs/JENKINS_SETUP.md`).
- CSRF protection (crumb issuer) left enabled (Jenkins default).
- No static AWS credentials anywhere in Jenkins — the EC2 instance role
  (`terraform/iam.tf`) is the only AWS identity Jenkins ever uses.
- GitHub access for the private repo uses a Jenkins Credential (username/
  PAT or SSH key), never a literal token in the `Jenkinsfile` or job
  config.
- SSH is closed by default (`enable_jenkins_ssh = false`); access is via
  AWS Systems Manager Session Manager, which requires no open inbound port
  and is authorized entirely through IAM.
