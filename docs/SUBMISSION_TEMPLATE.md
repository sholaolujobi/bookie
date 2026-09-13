# Submission Template

Fill in the placeholders below before submitting. This file is safe to
commit as a template (no real values), but the **filled-in copy with the
real Jenkins password should only be turned into a PDF/document kept
outside git** — never commit real credentials, even temporary ones.

---

## 1. Screenshot: deployed frontend showing SUCCESS + GUID

`[ attach screenshot here — browser window open to the ALB URL, showing
the "SUCCESS" label and GUID rendered by the React app ]`

## 2. Screenshot: successful Jenkins pipeline

`[ attach screenshot here — Jenkins Stage View for a green bookie-deploy
build, showing all stages passed ]`

## 3. GitHub repository URL

<https://github.com/sholaolujobi/bookie>

## 4. Public frontend URL

<http://bookie-dev-alb-889895501.us-east-1.elb.amazonaws.com>

(Also available via `terraform output application_url` — the ALB DNS name
is stable for the life of this deployment; it will change if the ALB is
ever recreated.)

## 5. Jenkins server URL

`http://<JENKINS_PUBLIC_IP>:8080` — from `terraform output jenkins_url`.
Not filled in as a fixed value here: the Jenkins EC2 instance's public IP
is not an Elastic IP, so it changes if the instance is ever replaced (this
happened a few times during initial setup while debugging the boot
script — see `PROJECT_STATUS.md`). Always get the current value from
`terraform output jenkins_url` rather than relying on a value written down
here.

## 6. Temporary Jenkins username and password

> **Do not commit this section filled in.** Fill it in only in the private
> copy prepared for submission.

- Username: `grader`
- Password: `[ insert here, private copy only ]`
- **This account must be deleted or have its password rotated immediately
  after grading is complete.**

## 7. Short testing instructions

1. Open the public frontend URL (item 4) in a browser — it should show
   `SUCCESS` and a GUID within a second or two.
2. Curl the backend directly through the ALB:
   `curl http://<ALB_DNS_NAME>/api/status` — expect
   `{"status":"SUCCESS","guid":"...","timestamp":"..."}`.
3. Open the Jenkins URL (item 5), log in with the temporary credentials
   (item 6), and open the `bookie-deploy` job to see pipeline history.

## 8. Short deployment instructions

1. `cd terraform && terraform init && terraform apply` (see
   `docs/DEPLOYMENT.md` for the full sequence, including the one-time
   initial image push).
2. Set up Jenkins per `docs/JENKINS_SETUP.md` and run the `bookie-deploy`
   job — it builds, tests, scans, and deploys both services end to end.

## 9. AWS architecture summary

Internet → internet-facing ALB (path-based routing: `/api/*` → backend,
else → frontend) → two ECS Fargate services (frontend, backend) in public
subnets across two AZs, each behind its own security group that only
accepts traffic from the ALB. A separate Jenkins EC2 instance (IAM
instance role, no static AWS credentials) builds and pushes images to two
ECR repositories and drives ECS deployments. See the README's Mermaid
diagram for the full picture.

## 10. Security summary

Least-privilege IAM throughout (scoped Jenkins pipeline policy, AWS-managed
ECS execution role, empty per-service task roles); IMDSv2 enforced;
encrypted EBS; ECR scan-on-push with immutable tags; non-root, multi-stage,
read-only-root-filesystem, all-capabilities-dropped containers; ECS
deployment circuit breaker plus explicit Jenkins rollback; CORS restricted
to the deployed origin; HTTP security headers on the frontend; secret
scanning (`gitleaks`) and container scanning (`trivy`) gating every
pipeline run. Full detail in `SECURITY_CHECKLIST.md` and
`docs/SECURITY.md`.
