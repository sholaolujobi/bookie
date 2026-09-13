#!/bin/bash
# Jenkins EC2 bootstrap for Amazon Linux 2023.
#
# Intentionally contains no secrets: Jenkins generates its own initial admin
# password on first boot at /var/lib/jenkins/secrets/initialAdminPassword,
# retrieved later via SSM Session Manager (see docs/JENKINS_SETUP.md) - it
# is never written here, logged, or embedded in any Terraform output.
#
# Ordering note: Docker/Java/Jenkins are installed and started FIRST, before
# the supporting CLI tools (AWS CLI, Terraform, Trivy, hadolint, gitleaks).
# That way, if one of those secondary installs breaks (a moved download URL,
# a missing base package, an upstream repo change), Jenkins itself is still
# reachable and the specific broken step can be fixed and re-run instead of
# blocking the whole instance.
set -euxo pipefail

exec > >(tee /var/log/user-data.log) 2>&1

dnf update -y

echo "export AWS_DEFAULT_REGION=${aws_region}" >/etc/profile.d/aws-region.sh

# --- Docker -----------------------------------------------------------------
dnf install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user

# --- Java (required by Jenkins) ---------------------------------------------
# Current Jenkins core requires Java 21+ (Java 17 is no longer sufficient
# as of recent Jenkins releases - a java-17 install here previously caused
# `systemctl start jenkins` to fail with a non-zero control-process exit).
dnf install -y java-21-amazon-corretto-headless

# --- Jenkins ------------------------------------------------------------------
# Fetch the live repo definition (rather than hardcoding a gpgkey URL/repo
# path) so this keeps working across Jenkins' periodic signing-key/repo
# rotations.
curl -fsSL https://pkg.jenkins.io/redhat-stable/jenkins.repo -o /etc/yum.repos.d/jenkins.repo
jenkins_gpg_key=$(grep '^gpgkey=' /etc/yum.repos.d/jenkins.repo | head -1 | cut -d= -f2-)
rpm --import "$jenkins_gpg_key"
dnf install -y jenkins

# Let Jenkins run docker builds without needing a service restart later.
usermod -aG docker jenkins

# Start Jenkins as early as possible so it's usable even if a later,
# non-essential tool install below fails. Don't let a start failure abort
# the whole script (set -e is temporarily relaxed) - log diagnostics either
# way so a failure is debuggable from /var/log/user-data.log via SSM
# instead of only through EC2 console output.
systemctl enable jenkins
set +e
systemctl start jenkins
jenkins_start_rc=$?
set -e
systemctl status jenkins --no-pager || true
journalctl -xeu jenkins --no-pager -n 200 || true
if [ "$jenkins_start_rc" -ne 0 ]; then
  echo "WARNING: jenkins.service failed to start (see journalctl output above). Continuing with the rest of the bootstrap." >&2
fi

# --- Supporting CLI tools -----------------------------------------------------
dnf install -y git jq unzip tar gzip

# --- AWS CLI v2 -----------------------------------------------------------
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws

# --- Terraform --------------------------------------------------------------
dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
dnf install -y terraform

# --- Trivy (container image scanning) ---------------------------------------
cat >/etc/yum.repos.d/trivy.repo <<'EOF'
[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://aquasecurity.github.io/trivy-repo/rpm/public.key
EOF
dnf install -y trivy

# --- hadolint (Dockerfile linting) -------------------------------------------
curl -fsSL "https://github.com/hadolint/hadolint/releases/download/v2.12.0/hadolint-Linux-x86_64" -o /usr/local/bin/hadolint
chmod +x /usr/local/bin/hadolint

# --- gitleaks (secret scanning) ----------------------------------------------
curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v8.18.4/gitleaks_8.18.4_linux_x64.tar.gz" -o /tmp/gitleaks.tar.gz
tar -xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks
chmod +x /usr/local/bin/gitleaks
rm -f /tmp/gitleaks.tar.gz

echo "Jenkins bootstrap complete." >> /var/log/user-data.log
