variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project name used as a prefix for resource names and tags."
  type        = string
  default     = "bookie"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.project_name))
    error_message = "project_name must be lowercase alphanumeric/hyphen, starting with a letter, 2-21 characters."
  }
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the two public subnets, one per Availability Zone."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "Exactly two public subnet CIDRs are required (one per AZ)."
  }
}

# ---------------------------------------------------------------------------
# ECS / application
# ---------------------------------------------------------------------------

variable "container_port" {
  description = "Port both the frontend and backend containers listen on inside their task."
  type        = number
  default     = 8080
}

variable "frontend_cpu" {
  description = "Fargate task CPU units for the frontend service."
  type        = number
  default     = 256
}

variable "frontend_memory" {
  description = "Fargate task memory (MiB) for the frontend service."
  type        = number
  default     = 512
}

variable "backend_cpu" {
  description = "Fargate task CPU units for the backend service."
  type        = number
  default     = 256
}

variable "backend_memory" {
  description = "Fargate task memory (MiB) for the backend service."
  type        = number
  default     = 512
}

variable "frontend_desired_count" {
  description = "Desired number of frontend tasks."
  type        = number
  default     = 1
}

variable "backend_desired_count" {
  description = "Desired number of backend tasks."
  type        = number
  default     = 1
}

variable "frontend_image_tag" {
  description = "Initial image tag for the frontend ECR repository used in the first task definition. Jenkins registers new revisions with immutable commit-sha/build-number tags after this; Terraform does not track those (see lifecycle.ignore_changes on the service)."
  type        = string
  default     = "initial"
}

variable "backend_image_tag" {
  description = "Initial image tag for the backend ECR repository used in the first task definition."
  type        = string
  default     = "initial"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days for ECS container logs."
  type        = number
  default     = 14

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value accepted by CloudWatch Logs retention settings."
  }
}

variable "ecr_max_image_count" {
  description = "Maximum number of tagged images to retain per ECR repository before older ones expire."
  type        = number
  default     = 15
}

# ---------------------------------------------------------------------------
# Jenkins EC2
# ---------------------------------------------------------------------------

variable "jenkins_instance_type" {
  description = "EC2 instance type for the Jenkins server."
  type        = string
  default     = "t3.small"
}

variable "jenkins_root_volume_size" {
  description = "Root EBS volume size (GiB) for the Jenkins instance."
  type        = number
  default     = 20
}

variable "jenkins_allowed_cidrs" {
  description = "CIDR blocks allowed to reach the Jenkins web UI (port 8080). Restrict this to your IP(s) where possible; document any temporary grader access in docs/SUBMISSION_TEMPLATE.md."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_jenkins_ssh" {
  description = "Whether to open port 22 on the Jenkins security group. SSM Session Manager is preferred and does not require this; leave false unless SSH is absolutely required."
  type        = bool
  default     = false
}

variable "jenkins_ssh_allowed_cidr" {
  description = "Single CIDR block allowed to SSH to Jenkins when enable_jenkins_ssh is true. Ignored otherwise."
  type        = string
  default     = "0.0.0.0/32"
}

variable "key_pair_name" {
  description = "Optional existing EC2 key pair name for SSH access to Jenkins. Leave null to rely solely on SSM Session Manager (recommended)."
  type        = string
  default     = null
}

variable "github_repo_url" {
  description = "HTTPS URL of the private GitHub repository Jenkins will clone (informational; Jenkins credentials are configured manually in the Jenkins UI, not via Terraform)."
  type        = string
  default     = "https://github.com/sholaolujobi/bookie.git"
}
