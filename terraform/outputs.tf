output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer. This is the URL for the deployed application."
  value       = aws_lb.main.dns_name
}

output "application_url" {
  description = "Full URL of the deployed frontend."
  value       = "http://${aws_lb.main.dns_name}"
}

output "backend_api_url" {
  description = "Full URL of the deployed backend status endpoint, routed through the ALB."
  value       = "http://${aws_lb.main.dns_name}/api/status"
}

output "jenkins_url" {
  description = "Jenkins web UI URL."
  value       = "http://${aws_instance.jenkins.public_ip}:8080"
}

output "jenkins_instance_id" {
  description = "Jenkins EC2 instance ID (use with SSM Session Manager to connect)."
  value       = aws_instance.jenkins.id
}

output "jenkins_public_ip" {
  description = "Jenkins EC2 public IP address."
  value       = aws_instance.jenkins.public_ip
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.main.name
}

output "frontend_ecr_repository_url" {
  description = "ECR repository URL for the frontend image."
  value       = aws_ecr_repository.frontend.repository_url
}

output "backend_ecr_repository_url" {
  description = "ECR repository URL for the backend image."
  value       = aws_ecr_repository.backend.repository_url
}

output "frontend_service_name" {
  description = "ECS service name for the frontend."
  value       = aws_ecs_service.frontend.name
}

output "backend_service_name" {
  description = "ECS service name for the backend."
  value       = aws_ecs_service.backend.name
}

output "frontend_log_group" {
  description = "CloudWatch log group for frontend container logs."
  value       = aws_cloudwatch_log_group.frontend.name
}

output "backend_log_group" {
  description = "CloudWatch log group for backend container logs."
  value       = aws_cloudwatch_log_group.backend.name
}

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = aws_subnet.public[*].id
}

output "frontend_target_group_arn" {
  description = "ALB target group ARN for the frontend service."
  value       = aws_lb_target_group.frontend.arn
}

output "backend_target_group_arn" {
  description = "ALB target group ARN for the backend service."
  value       = aws_lb_target_group.backend.arn
}

output "jenkins_iam_role_arn" {
  description = "IAM role ARN assumed by the Jenkins EC2 instance."
  value       = aws_iam_role.jenkins.arn
}
