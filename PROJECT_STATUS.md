# Project Status

Last updated: 2026-09-13 (session 1, ~21:20 UTC)

## Summary

Full CI/CD platform build for the `bookie` project: React frontend + Express
backend, containerized, deployed to ECS Fargate behind an ALB, provisioned
with Terraform. **Infrastructure is live on AWS and the app is confirmed
working end to end.** Jenkins is up; the pipeline job itself has not yet
been created/run (next step below).

**Important deviation from the original brief:** the starter repository URL
given (`https://github.com/pakurumo/techpathway-2`) does not exist (the
`pakurumo` GitHub account does not exist). A corrected guess
(`sholaolujobi/techpathway-2`) also does not exist. Per explicit user
confirmation, the application was **built from scratch** in this repo rather
than forked from a starter. `upstream` remote points at the originally-given
(nonexistent) URL for reference only; nothing has been or will be pushed to
it.

## Completed work

- [x] Confirmed git identity, remotes (`origin` → `sholaolujobi/bookie.git`,
      push access verified), working tree, branch (`main`).
- [x] Built and locally verified the Express backend and React frontend
      (see "Verification results" below) — tests, builds, and manual
      end-to-end curl checks all passed.
- [x] Dockerized both services (multi-stage, non-root, read-only-rootfs-
      compatible, all-capabilities-dropped). Trivy: 0 HIGH/CRITICAL in both
      final images.
- [x] Wrote full Terraform under `terraform/` (networking, security groups,
      ECR, IAM, ALB, ECS, Jenkins EC2, logging, outputs). `fmt`, `init
      -backend=false`, and `validate` all pass. `trivy config` run with 2
      classes of accepted findings documented (public IPs on ECS subnets,
      egress-all security groups — both deliberate cost trade-offs).
- [x] Wrote `Jenkinsfile` (19-stage declarative pipeline per spec) and all
      required docs/security files (README, docs/*, SECURITY*.md,
      CODEOWNERS, dependabot.yml).
- [x] Pushed 2 commits to `origin/main` (baseline app, terraform+jenkins+docs).
- [x] **`terraform apply` completed successfully** — 36 resources created.
- [x] Pushed initial images to both ECR repos, tagged `:initial`.
      **Important**: first push was built on this machine's native arm64
      and failed to run on Fargate (`CannotPullContainerError: ... does not
      contain descriptor matching platform 'linux/amd64'`). Fixed by
      deleting the bad `:initial` tags (immutable tags block overwrite, not
      delete) and rebuilding with `docker buildx build --platform
      linux/amd64 --push`. **Anyone rebuilding images from an Apple
      Silicon/ARM machine must use `--platform linux/amd64`** — Jenkins
      itself runs on an x86_64 EC2 instance so its builds don't need this
      flag.
- [x] Both ECS services reached steady state (1/1 running, target groups
      healthy).
- [x] **Verified live**: `curl http://<alb-dns>/api/status` returns
      `{"status":"SUCCESS","guid":"...","timestamp":"..."}`; headless
      Chrome screenshot of `http://<alb-dns>/` confirms the frontend visibly
      renders **SUCCESS** and a GUID (sent to the user).
- [x] Checked CloudWatch logs for both services — no errors, normal
      startup/request logs only.

## Not yet done

- [ ] Retrieve Jenkins initial admin password and complete the setup wizard
      (blocked mid-session on SSM agent registration — see "Known
      problems")
- [ ] Create GitHub credential in Jenkins for the private repo checkout
- [ ] Create the `bookie-deploy` pipeline job
- [ ] Run the pipeline end-to-end and verify it deploys new versioned
      images (replacing the `:initial` bootstrap tag)
- [ ] Take a screenshot of a successful Jenkins pipeline run
- [ ] Fill in real URLs/values in `docs/SUBMISSION_TEMPLATE.md`
- [ ] Final `git push` of any remaining doc updates

## Current infrastructure / AWS resources (LIVE)

- Account ID: `288761770474`, IAM identity `arn:aws:iam::288761770474:user/try1`, region `us-east-1`
- VPC `vpc-0f590707c7db43569`, public subnets `subnet-03bc93aa0c17f3eee` (us-east-1a), `subnet-02d2d45b334f849bb` (us-east-1b)
- ALB: `bookie-dev-alb-889895501.us-east-1.elb.amazonaws.com`
- ECS cluster: `bookie-dev-cluster`; services `bookie-dev-frontend`, `bookie-dev-backend` (both 1/1 running, healthy)
- ECR: `288761770474.dkr.ecr.us-east-1.amazonaws.com/bookie-dev-frontend`, `.../bookie-dev-backend` (currently only the `:initial` tag; Jenkins will add commit-sha-tagged images)
- Jenkins EC2: `i-051525e4226220d8c`, public IP `18.212.219.90`, URL `http://18.212.219.90:8080` — instance running, user-data bootstrap was still completing as of last check (installs Jenkins/Docker/AWS CLI/Terraform/Trivy/hadolint/gitleaks — this takes several minutes)
- CloudWatch log groups: `/ecs/bookie-dev-frontend`, `/ecs/bookie-dev-backend`

`terraform.tfvars` exists locally (copied from `.example`, defaults
unchanged) and is git-ignored, as intended.

## Verification results

### Local (pre-deploy)

| Check | Result |
|---|---|
| Backend `npm install`/`npm test` (Jest) | ✅ 4/4 passing |
| Frontend `npm install`/`npm test` (RTL) | ✅ 2/2 passing |
| Frontend `npm run build` | ✅ |
| Both Docker images build | ✅ |
| Both containers run, Docker `HEALTHCHECK` healthy | ✅ |
| Both containers work `--read-only --cap-drop ALL` | ✅ |
| Trivy scan (HIGH,CRITICAL) both images | ✅ 0 findings each |
| `terraform fmt/validate` | ✅ |
| `trivy config` on terraform/ | 2 accepted-risk finding classes (documented in `docs/SECURITY.md`) |
| `hadolint` both Dockerfiles | ✅ 0 findings (after inline suppressions for 2 intentional style-only notices) |
| `gitleaks detect` whole repo | ✅ no leaks |

### Deployed (post-apply)

| Check | Result |
|---|---|
| `terraform apply` | ✅ 36 added, 0 errors |
| ECS services reach desired count | ✅ 1/1 both |
| ALB target groups healthy | ✅ both `healthy` |
| `curl http://<alb>/api/status` | ✅ `{"status":"SUCCESS","guid":"...",...}` |
| `curl -I http://<alb>/` | ✅ `200 OK` |
| Headless-Chrome screenshot of frontend | ✅ visibly shows SUCCESS + GUID (sent to user) |
| CloudWatch logs, both services | ✅ no errors |
| ECR has the initial images | ✅ `:initial` tag present in both repos |
| Jenkins reachable / pipeline run | ⏳ not yet done |

## Deployed URLs

- Frontend: <http://bookie-dev-alb-889895501.us-east-1.elb.amazonaws.com>
- Backend API: <http://bookie-dev-alb-889895501.us-east-1.elb.amazonaws.com/api/status>
- Jenkins: <http://18.212.219.90:8080> (setup wizard not yet completed)

## Remaining manual actions

- Complete the Jenkins setup wizard (retrieve initial admin password via
  SSM — see below), add the GitHub credential, create the pipeline job.
- After grading, delete the temporary Jenkins grader account / rotate its
  password (see `docs/JENKINS_SETUP.md`).
- Consider `terraform destroy` when not actively using/grading this, to
  avoid ongoing cost (~$55-60/month if left running).

## Known problems

- Fixed during local verification: nginx `add_header` inheritance bug
  (dropped security headers on `/` and `/static/*`) — fixed by repeating
  headers in every location block that sets its own `Cache-Control`.
- Fixed during local verification: `npm ci` lockfile/peer-dependency
  mismatch on `typescript` in the frontend build — fixed by pinning
  `typescript: ^4.9.5` as an explicit devDependency.
- Fixed during deployment: initial ECR images were built for arm64 (this
  machine's native architecture) and failed to pull on Fargate (amd64).
  Fixed by rebuilding with `docker buildx build --platform linux/amd64`.
  **Jenkins builds on its own x86_64 EC2 instance, so this only affected
  the manual bootstrap push, not the pipeline going forward.**
- **In progress / not yet resolved**: the SSM Session Manager plugin
  couldn't be installed locally (`brew install --cask
  session-manager-plugin` needs an interactive sudo password this
  environment can't supply). Working around it with `aws ssm
  send-command`/`get-command-invocation` (Run Command API) instead of
  `aws ssm start-session`, which doesn't need the local plugin. As of the
  last check, the Jenkins EC2 instance had not yet registered as an SSM
  managed instance (`aws ssm describe-instance-information` returned
  empty) — likely still finishing its user-data bootstrap (installs many
  packages sequentially: Docker, Java, Jenkins, AWS CLI v2, Terraform,
  Trivy, hadolint, gitleaks). A background monitor was watching for SSM
  registration when this file was last updated.

## Exact next step

1. Confirm the Jenkins EC2 instance has registered with SSM
   (`aws ssm describe-instance-information --region us-east-1`).
2. Retrieve the initial admin password via `aws ssm send-command`
   (document `AWS-RunShellScript`, command `sudo cat
   /var/lib/jenkins/secrets/initialAdminPassword`) + `get-command-invocation`
   — **do not print this to any committed file**.
3. Complete the Jenkins setup wizard via its REST API/UI, install the
   suggested plugin set, create a throwaway admin/grader account.
4. Add the `github-bookie-credentials` credential (GitHub PAT) so Jenkins
   can clone the private `bookie` repo.
5. Create the `bookie-deploy` pipeline job (Pipeline script from SCM,
   `main` branch, `Jenkinsfile` at repo root).
6. Trigger a build, watch it through to a green run, screenshot it.
7. Confirm the pipeline's deployed image tags (commit-sha + build number)
   show up in both ECR repos and that both ECS services picked them up.
8. Fill in `docs/SUBMISSION_TEMPLATE.md` with the real URLs (keep the
   Jenkins password out of the committed copy — only in a private/local
   copy prepared for actual submission).
9. Final commit + push to `origin/main`.
