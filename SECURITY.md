# Security Policy

## Reporting a vulnerability

This is a training/demo repository (a DevOps technical challenge), not a
production service handling real user data. If you find a security issue:

1. **Do not** open a public GitHub issue for anything sensitive (credential
   leaks, exposed infrastructure, RCE-class findings).
2. Email the repository owner directly (see the GitHub profile of
   [sholaolujobi](https://github.com/sholaolujobi)) with a description of
   the issue, steps to reproduce, and its potential impact.
3. Expect an initial response within a few days. This is a personal/
   educational project, not a company with an SLA.

## Scope

In scope: the application code (`frontend/`, `backend/`), Dockerfiles,
Terraform (`terraform/`), and the Jenkins pipeline (`Jenkinsfile`) in this
repository.

Out of scope: the underlying AWS account, third-party services (GitHub,
Docker Hub, npm registry), and anything not committed to this repository.

## Known accepted risks

Documented in detail in [docs/SECURITY.md](docs/SECURITY.md), including:

- CRA's dev-only build tooling (`webpack-dev-server`/`sockjs`) carries known
  moderate `npm audit` findings that do not ship in the production Nginx
  image.
- Express's `qs` dependency has an open moderate advisory with no upstream
  fix yet on the 4.x line.
- ECS security groups allow unrestricted egress (needed for ECR/CloudWatch
  access without VPC endpoints) and ECS tasks run with public IPs (needed
  to avoid a NAT Gateway) — both are deliberate, cost-conscious trade-offs;
  inbound access to the tasks is restricted to the ALB security group only.

## Supported versions

Only the `main` branch is maintained.
