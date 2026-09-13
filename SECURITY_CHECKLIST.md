# Security Checklist

Every control below maps to a specific file/line so it can be verified, not
just claimed.

| Control | Status | Where |
|---|---|---|
| Least-privilege IAM | ✅ | `terraform/iam.tf` — Jenkins policy scoped to exact ECR repo ARNs, ECS cluster/service ARNs, `iam:PassRole` limited to the 3 ECS roles with a `PassedToService` condition |
| EC2 IAM role instead of static credentials | ✅ | `terraform/iam.tf` (`aws_iam_role.jenkins` + `aws_iam_instance_profile.jenkins`); Jenkinsfile never sets AWS keys |
| IMDSv2 enforcement | ✅ | `terraform/jenkins.tf` — `metadata_options { http_tokens = "required" }` |
| Encrypted Jenkins EBS | ✅ | `terraform/jenkins.tf` — `root_block_device { encrypted = true }` |
| ECR vulnerability scanning | ✅ | `terraform/ecr.tf` — `image_scanning_configuration { scan_on_push = true }` on both repos |
| Immutable container image tags | ✅ | `terraform/ecr.tf` — `image_tag_mutability = "IMMUTABLE"`; `Jenkinsfile` tags images `<git-sha>-<build-number>` |
| Non-root containers | ✅ | `backend/Dockerfile` (`USER node`), `frontend/Dockerfile` (`USER nginx`, nginx-unprivileged base) |
| Multi-stage Docker builds | ✅ | Both Dockerfiles: build stage vs. runtime stage |
| Restricted CORS | ✅ | `backend/config.js` + `backend/src/app.js` — allow-list via `CORS_ORIGIN`, set to the ALB origin in `terraform/ecs.tf` |
| HTTP security headers | ✅ | `frontend/nginx.conf` — CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy |
| No direct internet ingress to ECS tasks | ✅ | `terraform/security-groups.tf` — frontend/backend SGs only allow inbound from the ALB SG |
| ALB-to-ECS security-group references | ✅ | `terraform/security-groups.tf` — `security_groups = [aws_security_group.alb.id]` on both task SGs |
| Separate security groups for ALB, frontend, backend, Jenkins | ✅ | `terraform/security-groups.tf` — four distinct `aws_security_group` resources |
| Read-only root filesystem | ✅ | `terraform/ecs.tf` — `readonlyRootFilesystem = true` + `tmpfs` mounts on both task defs; verified locally with `docker run --read-only` |
| Drop unnecessary Linux capabilities | ✅ | `terraform/ecs.tf` — `linuxParameters.capabilities.drop = ["ALL"]`; verified locally with `--cap-drop ALL` |
| No privileged containers | ✅ | Never set; Fargate does not support privileged mode |
| CloudWatch logs with retention limits | ✅ | `terraform/logging.tf` — `retention_in_days = var.log_retention_days` (default 14) |
| ECS deployment circuit breaker | ✅ | `terraform/ecs.tf` — `deployment_circuit_breaker { enable = true, rollback = true }` on both services |
| Automatic rollback | ✅ | ECS circuit breaker (infra level) + `Jenkinsfile` `post { failure { ... } }` restores the previous task definition revision (pipeline level) |
| Repository secret scanning | ✅ | `Jenkinsfile` "Secret Scan" stage runs `gitleaks detect` |
| Trivy container scanning | ✅ | `Jenkinsfile` "Trivy Image Scan" stage, `--severity HIGH,CRITICAL --exit-code 1`; also run manually pre-deploy (0 findings) |
| Dependency auditing for critical vulnerabilities | ✅ | `Jenkinsfile` "Dependency Vulnerability Scan" stage — `npm audit --audit-level=critical` on both apps |
| Dependabot: npm, Docker, Terraform | ✅ | `.github/dependabot.yml` |
| GitHub CODEOWNERS | ✅ | `/CODEOWNERS` |
| SECURITY.md with reporting instructions | ✅ | `/SECURITY.md` |
| Branch-protection recommendations | ✅ | `README.md` → "Branch protection" section |
| SSM Session Manager preferred over SSH | ✅ | `terraform/security-groups.tf` — port 22 closed unless `enable_jenkins_ssh = true`; `AmazonSSMManagedInstanceCore` attached in `terraform/iam.tf` |
| Dockerfile linting | ✅ | `Jenkinsfile` "Dockerfile Lint" stage — `hadolint` on both Dockerfiles |

## Accepted risks (documented, not fixed)

- **Egress-all security groups**: all four security groups allow outbound
  `0.0.0.0/0`. Restricting this would require VPC interface endpoints for
  ECR, S3, CloudWatch Logs, and STS — extra always-on cost, out of scope
  without explicit approval (see architecture constraints in
  `PROJECT_STATUS.md`).
- **ECS tasks have public IPs**: required to reach ECR/CloudWatch without a
  NAT Gateway (explicit cost constraint). Mitigated: task security groups
  only accept inbound traffic from the ALB security group, so the tasks are
  not reachable directly from the internet despite having public IPs.
- **No HTTPS/ACM certificate**: no domain name was provided for this
  challenge, so the ALB listens on HTTP (port 80) only. See
  `docs/TROUBLESHOOTING.md` / README "Known limitations" for how to add
  HTTPS if a domain becomes available.
- **`qs` (Express transitive dependency) moderate advisory**: no fixed
  version exists yet on the Express 4.x line as of this writing; low
  real-world impact for this app (no user-controlled complex query
  objects are parsed). Tracked via Dependabot.
- **CRA build-tooling `npm audit` findings**: `webpack-dev-server`/`sockjs`/
  `jsonpath` chain findings are dev-only (used by `npm start`/`npm run
  build`), never shipped into the production Nginx image, and are excluded
  from the CI gate accordingly (`--audit-level=critical`, not `moderate`).
