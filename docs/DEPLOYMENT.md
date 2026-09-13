# Deployment Guide

## Prerequisites

- AWS CLI v2, authenticated (`aws sts get-caller-identity` succeeds)
- Terraform >= 1.5.0
- Docker
- An AWS account with permission to create VPC/ALB/ECS/ECR/IAM/EC2
  resources in `us-east-1`

## 1. Review and apply Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # edit if you want non-default values
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
```

Review the plan output carefully — it creates real, billed AWS resources
(ALB, EC2, ECS Fargate tasks, EBS volume). See the README's "Estimated AWS
costs" section before proceeding.

```bash
terraform apply tfplan
```

Save the outputs:

```bash
terraform output
```

## 2. Push the initial application images

Terraform creates the ECR repositories and ECS services/task definitions,
but does **not** build or push any application image — the task
definitions reference an `:initial` tag that does not exist yet, and the
ECS services will show failed task launches (`CannotPullContainerError`)
until an image is pushed. This is expected. Push the first images
manually right after `apply`:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"

docker build -t bookie-dev-frontend:initial ./frontend
docker build -t bookie-dev-backend:initial ./backend

docker tag bookie-dev-frontend:initial "$ECR_REGISTRY/bookie-dev-frontend:initial"
docker tag bookie-dev-backend:initial  "$ECR_REGISTRY/bookie-dev-backend:initial"

docker push "$ECR_REGISTRY/bookie-dev-frontend:initial"
docker push "$ECR_REGISTRY/bookie-dev-backend:initial"
```

ECS will retry automatically and the services should reach steady state
within a couple of minutes:

```bash
aws ecs wait services-stable --region us-east-1 --cluster bookie-dev-cluster \
  --services bookie-dev-frontend bookie-dev-backend
```

## 3. Verify

```bash
ALB_DNS=$(cd terraform && terraform output -raw alb_dns_name)
curl -s "http://$ALB_DNS/api/status"     # expect {"status":"SUCCESS","guid":"...","timestamp":"..."}
curl -sI "http://$ALB_DNS/"              # expect HTTP/1.1 200
```

Open `http://$ALB_DNS` in a browser — you should see `SUCCESS` and a GUID
rendered by the React app.

## 4. Set up Jenkins and run the pipeline

See `docs/JENKINS_SETUP.md`. Once the `bookie-deploy` job runs
successfully, it registers new task definition revisions (tagged with the
git commit SHA + Jenkins build number) and updates both services — from
that point on, Terraform's `:initial` tag is no longer in use in either
running service (Terraform's `lifecycle.ignore_changes = [task_definition]`
on both `aws_ecs_service` resources means future `terraform apply` runs
will not revert Jenkins-managed deployments).

## Rollback

Automatic: the Jenkins pipeline records each service's task definition ARN
before deploying and restores it on any pipeline failure (`post { failure
{ ... } }` in `Jenkinsfile`). ECS's own deployment circuit breaker
(`terraform/ecs.tf`) provides a second layer — if a newly-registered
revision fails to stabilize, ECS itself rolls the service back.

Manual rollback to a specific revision:

```bash
aws ecs update-service --region us-east-1 --cluster bookie-dev-cluster \
  --service bookie-dev-backend --task-definition bookie-dev-backend:<revision-number>
aws ecs wait services-stable --region us-east-1 --cluster bookie-dev-cluster --services bookie-dev-backend
```

## Cleanup / teardown

```bash
cd terraform
terraform destroy
```

This removes every AWS resource created by Terraform (VPC, ALB, ECS,
Jenkins EC2, ECR repos and their images, log groups). ECR repos with
images require `force_delete` or manual image cleanup first if
`terraform destroy` fails on a non-empty repository:

```bash
aws ecr batch-delete-image --region us-east-1 --repository-name bookie-dev-frontend \
  --image-ids "$(aws ecr list-images --region us-east-1 --repository-name bookie-dev-frontend --query 'imageIds' --output json)"
```
