#!/bin/bash
# Jenkins EC2 bootstrap for Amazon Linux 2023.
#
# Intentionally contains no secrets: Jenkins generates its own initial admin
# password on first boot at /var/lib/jenkins/secrets/initialAdminPassword,
# retrieved later via SSM Session Manager (see docs/JENKINS_SETUP.md) - it
# is never written here, logged, or embedded in any Terraform output.
set -euxo pipefail

exec > >(tee /var/log/user-data.log) 2>&1

dnf update -y

echo "export AWS_DEFAULT_REGION=${aws_region}" >/etc/profile.d/aws-region.sh

# --- Docker -----------------------------------------------------------------
dnf install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user

# --- Java (required by Jenkins) ---------------------------------------------
dnf install -y java-17-amazon-corretto-headless

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

# --- Git, jq ------------------------------------------------------------------
dnf install -y git jq

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

# --- Start Jenkins ------------------------------------------------------------
systemctl enable --now jenkins

echo "Jenkins bootstrap complete." >> /var/log/user-data.log
