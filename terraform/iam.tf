# ---------------------------------------------------------------------------
# ECS task execution role: used by the ECS agent itself to pull images from
# ECR and ship container logs to CloudWatch. AWS-managed policy is scoped
# tightly to exactly those actions.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "${local.name_prefix}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = {
    Name = "${local.name_prefix}-ecs-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------------------------------------------------------------------------
# ECS task roles (minimal): assumed by the application containers
# themselves. Neither app calls AWS APIs at runtime, so these carry no
# permissions beyond the trust relationship required for ECS to assume them.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "frontend_task" {
  name               = "${local.name_prefix}-frontend-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = {
    Name = "${local.name_prefix}-frontend-task-role"
  }
}

resource "aws_iam_role" "backend_task" {
  name               = "${local.name_prefix}-backend-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = {
    Name = "${local.name_prefix}-backend-task-role"
  }
}

# ---------------------------------------------------------------------------
# Jenkins EC2 instance role: least privilege for exactly what the pipeline
# does (ECR auth + push, register task definitions, update the two ECS
# services, pass the ECS execution/task roles to ECS) plus SSM Session
# Manager so the instance never needs an open SSH port.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "jenkins" {
  name               = "${local.name_prefix}-jenkins-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name = "${local.name_prefix}-jenkins-role"
  }
}

resource "aws_iam_role_policy_attachment" "jenkins_ssm" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "jenkins_pipeline" {
  # ECR authentication is only available as a wildcard resource action.
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Image push/pull operations scoped to exactly the two project repos.
  statement {
    sid = "EcrPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:ListImages",
    ]
    resources = [
      aws_ecr_repository.frontend.arn,
      aws_ecr_repository.backend.arn,
    ]
  }

  # ECS describe/register actions that AWS does not support scoping with
  # resource-level permissions.
  statement {
    sid = "EcsDescribeAndRegister"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeClusters",
    ]
    resources = ["*"]
  }

  # The Jenkinsfile looks up the ALB's DNS name dynamically at build time
  # (never hardcoded) so it can run the post-deploy smoke test against the
  # real deployed URL. elasticloadbalancing:Describe* actions do not
  # support resource-level permissions.
  statement {
    sid       = "AlbDescribe"
    actions   = ["elasticloadbalancing:DescribeLoadBalancers"]
    resources = ["*"]
  }

  # Describe/update actions scoped to this project's cluster and services.
  statement {
    sid = "EcsServiceOperations"
    actions = [
      "ecs:DescribeServices",
      "ecs:DescribeTasks",
      "ecs:ListTasks",
      "ecs:UpdateService",
    ]
    resources = [
      aws_ecs_cluster.main.arn,
      aws_ecs_service.frontend.id,
      aws_ecs_service.backend.id,
    ]
  }

  # Required so ECS can assume the execution/task roles on Jenkins' behalf
  # when it registers task definitions and updates services; scoped to
  # exactly those three roles and to the ECS tasks service only.
  statement {
    sid     = "PassEcsRoles"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.ecs_execution.arn,
      aws_iam_role.frontend_task.arn,
      aws_iam_role.backend_task.arn,
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "jenkins_pipeline" {
  name   = "${local.name_prefix}-jenkins-pipeline-policy"
  role   = aws_iam_role.jenkins.id
  policy = data.aws_iam_policy_document.jenkins_pipeline.json
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${local.name_prefix}-jenkins-instance-profile"
  role = aws_iam_role.jenkins.name
}
