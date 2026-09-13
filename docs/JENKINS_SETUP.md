# Jenkins Setup

## 1. Retrieve the initial admin password

Jenkins generates its own initial admin password on first boot at
`/var/lib/jenkins/secrets/initialAdminPassword`. It is never written to
Terraform outputs, EC2 user data, or any log — retrieve it via SSM Session
Manager (no SSH needed):

```bash
aws ssm start-session --target <jenkins_instance_id> --region us-east-1
# once connected:
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
exit
```

`<jenkins_instance_id>` is the `jenkins_instance_id` Terraform output.

## 2. Finish the setup wizard

1. Open `http://<jenkins_public_ip>:8080` (the `jenkins_url` Terraform
   output) and paste the initial admin password.
2. Choose **Install suggested plugins** — this covers Git, Credentials
   Binding, and Pipeline, which are all this project needs. Do not install
   extra plugins beyond what's listed below.
3. Create the first admin user. **For grading**, create a throwaway account
   (e.g. username `grader`) with a strong generated password rather than
   reusing a personal one — see "Temporary grading access" below.
4. Keep the default Jenkins URL.

## 3. Required plugins

Only these are needed (the "suggested plugins" set installed above already
includes all of them):

- **Git** — SCM checkout
- **Pipeline** (workflow-aggregator) — declarative `Jenkinsfile` support
- **Credentials Binding** — private repo GitHub credential
- **Pipeline: Stage View** — visualizing stage progress (usually bundled with Pipeline)

The `Jenkinsfile` intentionally shells out to `docker`, `aws`, `terraform`,
`trivy`, `hadolint`, and `gitleaks` directly rather than using their Jenkins
plugin wrappers, so no Docker Pipeline / AWS Steps / Terraform plugins are
required.

## 4. Add GitHub credentials for the private repo

1. **Manage Jenkins → Credentials → System → Global credentials → Add
   Credentials**.
2. Kind: **Username with password** (use a GitHub Personal Access Token as
   the password, scope `repo`) or **SSH Username with private key** if you
   prefer deploy keys.
3. ID: `github-bookie-credentials` (the `Jenkinsfile`/job configuration
   references this ID — never hardcode the token itself anywhere in the
   repo).

## 5. Create the pipeline job

1. **New Item → Pipeline**, name it `bookie-deploy`.
2. Under **Pipeline**, set **Definition** to *Pipeline script from SCM*.
3. **SCM**: Git, **Repository URL**:
   `https://github.com/sholaolujobi/bookie.git`, **Credentials**: the
   `github-bookie-credentials` entry from step 4.
4. **Branch**: `*/main`.
5. **Script Path**: `Jenkinsfile` (default, already correct).
6. Save.

## 6. Trigger a deployment

Manually: open the `bookie-deploy` job → **Build Now**.

To trigger automatically on push, add a GitHub webhook (**Settings →
Webhooks** on the repo) pointing at
`http://<jenkins_public_ip>:8080/github-webhook/`, or simply poll SCM via
the job's build triggers if a public webhook endpoint isn't desirable for
this environment.

## 7. Temporary grading access

For the private submission:

1. Create a dedicated Jenkins account (e.g. `grader`) with **Read** +
   **Job/Build** permissions on the `bookie-deploy` job only (Matrix-based
   security, or simply share the admin account temporarily if Jenkins'
   default security realm is in use).
2. Record the username/password **only** in the final private submission
   document (`docs/SUBMISSION_TEMPLATE.md`), never in the git repository.
3. **After grading is complete**, delete the `grader` account or rotate its
   password immediately — treat it as compromised the moment grading ends.

## 8. Keeping Jenkins available after a reboot

`systemctl enable --now jenkins` is run by the Terraform user-data script
(`terraform/templates/jenkins-user-data.sh.tpl`), so Jenkins restarts
automatically on instance reboot. Verify with:

```bash
aws ssm start-session --target <jenkins_instance_id> --region us-east-1
sudo systemctl status jenkins
```
