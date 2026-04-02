##############################################################################
# outputs.tf — Useful values for CI/CD pipelines and kubectl configuration
##############################################################################

# ── VPC ──────────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

# ── ECR ──────────────────────────────────────────────────────────────────────

output "ecr_frontend_url" {
  description = "ECR repository URL for the frontend service"
  value       = aws_ecr_repository.frontend.repository_url
}

output "ecr_backend_url" {
  description = "ECR repository URL for the backend API service"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_auth_url" {
  description = "ECR repository URL for the auth service"
  value       = aws_ecr_repository.auth.repository_url
}

# ── EKS ──────────────────────────────────────────────────────────────────────

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint URL of the EKS cluster API server"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_ca" {
  description = "Base64-encoded certificate authority data for the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "eks_node_role_arn" {
  description = "ARN of the IAM role attached to EKS worker nodes"
  value       = aws_iam_role.eks_nodes.arn
}

# ── DynamoDB ─────────────────────────────────────────────────────────────────

output "dynamodb_table_name" {
  description = "Name of the DynamoDB Votes table"
  value       = aws_dynamodb_table.votes.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB Votes table"
  value       = aws_dynamodb_table.votes.arn
}

# ── Convenience: kubeconfig update command ───────────────────────────────────

output "configure_kubectl" {
  description = "Run this command to configure kubectl for the cluster"
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.aws_region}"
}

# ── Convenience: AWS Account ID ─────────────────────────────────────────────

output "aws_account_id" {
  description = "AWS Account ID (used in ECR login and ARNs)"
  value       = data.aws_caller_identity.current.account_id
}
