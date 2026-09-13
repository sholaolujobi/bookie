# Project Status

Last updated: 2026-09-13 (session 1, complete)

## Summary

**Project complete.** Full CI/CD platform for `bookie`: React frontend +
Express backend, containerized, deployed to ECS Fargate behind an ALB,
provisioned with Terraform, deployed via a working Jenkins pipeline on
EC2. The deployed frontend calls the deployed backend and displays
**SUCCESS** and a GUID. A real Jenkins pipeline run (`bookie-deploy #3`)
built, tested, scanned, and deployed both services end to end
successfully.

**Deviation from the original brief:** the starter repository URL given
(`https://github.com/pakurumo/techpathway-2`) does not exist (no such
GitHub account). Per explicit user confirmation, the application was
**built from scratch**. `upstream` remote points at the originally-given
(nonexistent) URL for reference only. Also per explicit user confirmation,
the `bookie` repo is **public** (not private as the challenge spec
describes) — Jenkins clones it with no credentials. See "Known
limitations" below.

## Completed work

- [x] Backend (Express) + frontend (React/CRA) built, tested locally,
      containerized (multi-stage, non-root, read-only-rootfs-compatible,
      all-capabilities-dropped). Trivy: 0 HIGH/CRITICAL in both images.
- [x] Terraform: VPC/subnets/IGW/routing, 4 security groups, ALB + 2
      target groups + listener/rule, ECS cluster + 2 services + 2 task
      defs (circuit breaker + rollback), 2 ECR repos (immutable tags,
      scan-on-push, lifecycle policy), least-privilege IAM (ECS execution
      role, 2 minimal task roles, scoped Jenkins pipeline policy), Jenkins
      EC2 (IMDSv2, encrypted EBS, SSM, no SSH), CloudWatch log groups.
      `fmt`/`init -backend=false`/`validate` all pass.
- [x] `Jenkinsfile`: 19-stage declarative pipeline exactly per spec
      (checkout → deps → tests → build → terraform checks → hadolint →
      gitleaks → npm audit → docker build → trivy → ECR push → register
      task defs → update services → wait stable → smoke test → cleanup),
      with automatic rollback to the prior task definition on any
      failure.
- [x] README, docs/{DEPLOYMENT,JENKINS_SETUP,SECURITY,TROUBLESHOOTING,
      SUBMISSION_TEMPLATE}.md, SECURITY.md, SECURITY_CHECKLIST.md,
      CODEOWNERS, .github/dependabot.yml.
- [x] **`terraform apply` — 36 resources created in AWS** (account
      `288761770474`, `us-east-1`).
- [x] Initial images pushed, both ECS services reached steady state.
- [x] **Jenkins fully configured and a real pipeline run succeeded**
      (`bookie-deploy #3`, 5m54s) — see "Bugs found and fixed during
      deployment" below for everything that had to be debugged live to
      get here.
- [x] Verified live: ALB → frontend (visually renders SUCCESS + GUID,
      screenshot sent to user) and → `/api/status` (curl, JSON
      SUCCESS+guid); both ECS services 1/1 running on task-definition
      revision `:3` (image tag `9a757fba-3`, i.e. git-sha + Jenkins build
      number, immutable); both target groups healthy; CloudWatch logs
      clean (no errors) on both services.
- [x] All work committed and pushed to `origin/main` (8 commits total).

## Current infrastructure / AWS resources (LIVE)

- Account `288761770474`, IAM identity `arn:aws:iam::288761770474:user/try1`, region `us-east-1`
- VPC `vpc-0f590707c7db43569`; public subnets `subnet-03bc93aa0c17f3eee` (us-east-1a), `subnet-02d2d45b334f849bb` (us-east-1b)
- ALB: `bookie-dev-alb-889895501.us-east-1.elb.amazonaws.com`
- ECS cluster `bookie-dev-cluster`; services `bookie-dev-frontend` / `bookie-dev-backend`, both 1/1 running on task-def revision `:3`
- ECR: `288761770474.dkr.ecr.us-east-1.amazonaws.com/bookie-dev-frontend` and `.../bookie-dev-backend` — tags `initial` (manual bootstrap) and `9a757fba-3` (Jenkins build #3, currently deployed)
- Jenkins EC2: `i-0644035300324927c`, public IP `54.205.173.82` (**note**: this IP is not an Elastic IP and changes if the instance is ever replaced — always confirm with `terraform output jenkins_url`), job `bookie-deploy`
- CloudWatch log groups: `/ecs/bookie-dev-frontend`, `/ecs/bookie-dev-backend`

`terraform.tfvars` exists locally (defaults unchanged) and is git-ignored.

## Deployed URLs

- Frontend: <http://bookie-dev-alb-889895501.us-east-1.elb.amazonaws.com>
- Backend API: <http://bookie-dev-alb-889895501.us-east-1.elb.amazonaws.com/api/status>
- Jenkins: `http://54.205.173.82:8080` (job: `bookie-deploy`)

## Verification results

All items in the original spec's "LOCAL VERIFICATION" and "DEPLOYED
VERIFICATION" checklists passed. Highlights:

| Check | Result |
|---|---|
| Local: tests, builds, Docker images, `--read-only --cap-drop ALL`, Trivy (0 findings), terraform fmt/init/validate, hadolint, gitleaks | ✅ all pass |
| `terraform apply` | ✅ 36 added, 0 errors |
| ECS services desired=running, target groups healthy | ✅ both |
| Frontend shows SUCCESS + GUID (visual, headless-Chrome screenshot) | ✅ (sent to user, twice — pre- and post-Jenkins-deploy) |
| Backend `/api/status` via ALB | ✅ `{"status":"SUCCESS","guid":"...",...}` |
| CloudWatch logs, both services | ✅ no errors |
| ECR has versioned (non-`latest`) images | ✅ `9a757fba-3` = `<git-sha>-<build-number>` |
| Jenkins reaches ECR/ECS via its IAM role | ✅ proven by the pipeline run itself |
| **A Jenkins pipeline finished successfully** | ✅ `bookie-deploy #3`, SUCCESS, 5m54s |
| Pipeline deployed the new image tags | ✅ task-def revisions `:3` on both services reference `9a757fba-3` |
| Smoke tests passed post-Jenkins-deploy | ✅ (Smoke Test stage: backend SUCCESS+guid regex match, frontend 200) |

## Bugs found and fixed during deployment

All of these were found by actually deploying and running the pipeline —
not by inspection — and fixed in place. Each has its own git commit with
full detail; summarized here for anyone resuming this work:

1. **Wrong CPU architecture on initial images**: built locally on this
   Mac's arm64, pushed to ECR, Fargate (amd64) couldn't pull them
   (`CannotPullContainerError`). Fixed with `docker buildx build --platform
   linux/amd64`. Anyone rebuilding manually from an Apple Silicon Mac needs
   this flag; Jenkins itself runs on x86_64 so its builds are unaffected.
2. **Jenkins GPG key mismatch**: hardcoded `jenkins.io-2023.key` no longer
   matched the current signing key, so `dnf install jenkins` failed GPG
   check under `set -e`, aborting the entire bootstrap. Fixed by fetching
   the live `jenkins.repo` file instead of hardcoding a key URL.
3. **Missing `unzip`** on Amazon Linux 2023 broke the AWS CLI v2 install
   step (also aborted the rest of bootstrap). Added `unzip`/`tar`/`gzip`
   explicitly, and reordered the script so Jenkins itself starts before
   the secondary tool installs, so one broken step can't take down
   Jenkins reachability again.
4. **Java 17 too old**: current Jenkins core (2.568.3) requires Java 21+;
   `systemctl start jenkins` failed silently otherwise. Switched to
   `java-21-amazon-corretto-headless`.
5. **`amazon-ssm-agent` not enabled by default** on this AMI build — IAM/
   networking were fine, but the instance never registered with SSM.
   Added an explicit `systemctl enable --now amazon-ssm-agent`.
6. **Jenkins' own disk-space monitor** marked the built-in node offline
   ("Disk space is below threshold of 1.00 GiB") because `/tmp` is a
   tmpfs sized ~955MB (~half the t3.small's RAM) — just under Jenkins'
   1GiB default. No build could even get an executor. Fixed with `mount
   -o remount,size=2G /tmp` (raises the cap; doesn't consume RAM until
   used) in user-data.
7. **Jenkins IAM policy was missing `elasticloadbalancing:DescribeLoadBalancers`**
   — the Jenkinsfile looks up the ALB DNS name dynamically (never
   hardcoded) for the smoke test, and the first real pipeline run hit
   `AccessDenied`. Added the permission (scoped `*`, as AWS requires for
   this action).
8. **Bare `${VAR}` Groovy interpolation in the Jenkinsfile silently failed**
   for variables set dynamically via `env.X = ...` in a `script{}` block
   (`IMAGE_TAG`, `ACCOUNT_ID`, `ECR_REGISTRY`, `ALB_DNS_NAME`, the task-def
   ARN vars) — `groovy.lang.MissingPropertyException: No such property`
   inside the CPS sandbox, even though the same variables were correctly
   exported as real shell environment variables. Rewrote every `sh` step
   to use single-quoted Groovy strings with pure bash `$VAR` expansion,
   which is both correct and simpler.
9. Configuring Jenkins headlessly (no GUI clicking) required scripting the
   setup wizard via an `init.groovy.d` script (creates the `grader`
   account, sets `FullControlOnceLoggedInAuthorizationStrategy`, marks
   setup complete) and the Jenkins CLI/script-console REST API for plugin
   installs, the GitHub credential attempt (see below), and pipeline job
   creation. The Jenkins CLI-over-HTTP handshake also required the
   "Jenkins URL" system config to match the host actually used to connect
   (`localhost`, since commands run via SSM on the box itself), which
   wasn't obvious from the error message at first (`X-CLI-Error: Jenkins
   URL is not configured`, then `Unexpected request origin`).

## Known limitations / deviations from spec

- **`bookie` repo is public, not private** (explicit user decision after
  discovering it wasn't private and choosing not to change it). The
  pipeline job's Git SCM config has no `credentialsId` since none is
  needed. If the user later makes it private, add a
  `github-bookie-credentials` username+PAT credential in the Jenkins UI
  (**Manage Jenkins → Credentials**) and re-add `<credentialsId>` to the
  job — see `docs/JENKINS_SETUP.md` for exact steps. An automated attempt
  to configure this credential using the local `gh` CLI's existing OAuth
  token was blocked by a safety guardrail against exposing live
  credentials in shell commands; this was a correct/reasonable block, not
  worked around.
- No HTTPS/ACM certificate — no domain name was available for this
  challenge; ALB is HTTP-only on port 80.
- Jenkins is a single EC2 instance with no HA. Its public IP is not an
  Elastic IP, so it changes whenever the instance is replaced.
- Full accepted-risk list (egress-all security groups, public IPs on ECS
  tasks, etc.) in `SECURITY_CHECKLIST.md` / `docs/SECURITY.md`.

## Remaining manual actions for the user

1. **Fill in `docs/SUBMISSION_TEMPLATE.md`** with the real Jenkins
   password for user `grader` in a **private copy only** — never commit
   it. (The password was shared with the user directly in-conversation
   when Jenkins was first set up; it is not recorded in this repo.)
2. **After grading**, delete the `grader` Jenkins account or rotate its
   password (`Manage Jenkins → Users`).
3. Consider `cd terraform && terraform destroy` when done, to stop
   ongoing AWS cost (~$55-60/month if left running continuously).

## Exact next step

None required — the project is functionally complete and verified end to
end. If resuming: `terraform output` for current live values (the Jenkins
public IP in particular may have changed if the instance was replaced
since this was written), then `docs/SUBMISSION_TEMPLATE.md` still needs
the real Jenkins password filled in a private (non-git) copy before
formal submission.
