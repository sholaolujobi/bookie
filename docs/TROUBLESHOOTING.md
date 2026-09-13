# Troubleshooting

## ECS tasks stuck in PROVISIONING / stopping repeatedly

**Symptom**: `aws ecs describe-services` shows `runningCount` never
reaching `desiredCount`; tasks appear and disappear.

**Check**:

```bash
aws ecs describe-services --region us-east-1 --cluster bookie-dev-cluster --services bookie-dev-backend \
  --query 'services[0].events[0:5]'
```

Common causes:

- **`CannotPullContainerError`**: the image tag referenced by the task
  definition doesn't exist in ECR yet. Right after the very first
  `terraform apply`, this is expected — see `docs/DEPLOYMENT.md` step 2
  (push the initial image).
- **Health check failing**: the container starts but `/healthz` (frontend)
  or `/api/health` (backend) doesn't return 200 within the configured
  grace period. Check container logs (below).
- **`ResourceInitializationError` pulling from ECR**: usually a networking
  issue — confirm the task's subnet has `map_public_ip_on_launch = true`
  and the task actually got a public IP (`assign_public_ip = true` in the
  service's `network_configuration`), since there's no NAT Gateway in this
  architecture.

## Viewing container logs

```bash
aws logs tail /ecs/bookie-dev-backend --region us-east-1 --follow
aws logs tail /ecs/bookie-dev-frontend --region us-east-1 --follow
```

## Target group shows unhealthy targets

```bash
aws elbv2 describe-target-health --region us-east-1 \
  --target-group-arn "$(cd terraform && terraform output -raw backend_target_group_arn)"
```

Check the `Reason` field: `Target.FailedHealthChecks` usually means the
health check path is returning a non-200, `Target.Timeout` means the app is
too slow to respond within the health check timeout.

## Frontend loads but shows "Failed to reach backend"

The React app's `App.js` calls `fetch('/api/status')` relative to its own
origin. This only works if the ALB listener rule for `/api/*` is correctly
forwarding to the backend target group. Verify:

```bash
curl -v "http://<alb-dns>/api/status"
```

If this 404s or times out, check `aws_lb_listener_rule.backend_api` in
`terraform/alb.tf` — priority, path pattern, and that it targets
`aws_lb_target_group.backend`.

## Jenkins pipeline fails at "ECR Auth & Push"

Almost always an IAM permissions issue. Confirm the instance is actually
using its instance profile:

```bash
# from a Jenkins SSM session
curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/
aws sts get-caller-identity
```

If `get-caller-identity` returns the Jenkins role ARN, IAM is fine — check
`terraform/iam.tf`'s `jenkins_pipeline` policy document for the exact ECR
repo ARNs (a repo name typo there is the most common cause of `AccessDenied`
on `ecr:PutImage` etc.).

## Jenkins pipeline fails at "Wait For Stability" / times out

`aws ecs wait services-stable` polls for up to ~10 minutes by default. If a
newly registered task definition has a bad image or misconfigured health
check, the deployment circuit breaker will trigger an ECS-side rollback,
which itself takes a few minutes — the wait may still time out. Check the
service's deployment status:

```bash
aws ecs describe-services --region us-east-1 --cluster bookie-dev-cluster --services bookie-dev-backend \
  --query 'services[0].deployments'
```

The `Jenkinsfile`'s `post { failure { ... } }` block still runs in this
case and explicitly restores the previous task definition.

## `terraform apply` fails with a naming/quota error

- **ALB/target group name too long**: AWS limits these to 32 characters.
  If you change `project_name`/`environment` to something longer, shorten
  it or the resource names in `terraform/*.tf` will need adjusting.
- **VPC/EIP/ALB limits**: default AWS account limits are usually generous
  enough for this architecture (1 VPC, 1 ALB, 2 ECS services), but a
  heavily-used sandbox account can hit them — request a limit increase or
  clean up unused resources.

## Can't reach Jenkins UI at all

- Confirm `jenkins_allowed_cidrs` includes your current public IP.
- Confirm the instance passed its user-data bootstrap:
  `aws ssm start-session --target <id>` then
  `sudo tail -100 /var/log/user-data.log` and
  `sudo systemctl status jenkins`.
- Confirm the security group actually attached (`terraform output` doesn't
  show SG changes if you edited `jenkins_allowed_cidrs` without re-running
  `terraform apply`).

## Known limitations (not bugs)

- HTTP only, no TLS — no domain name/ACM certificate is configured. See the
  README's "Known limitations" section.
- Single AZ redundancy for Jenkins — it's a single EC2 instance with no
  auto-recovery beyond EC2's own instance status checks. This is
  intentionally out of scope for a `t3.small` demo Jenkins box.
