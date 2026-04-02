##############################################################################
# eks.tf — EKS Cluster, Managed Node Group, and all IAM Roles/Policies
##############################################################################

# ══════════════════════════════════════════════════════════════════════════════
# 1. EKS CLUSTER CONTROL PLANE
# ══════════════════════════════════════════════════════════════════════════════

# ── IAM Role for the EKS Cluster (control plane) ────────────────────────────
# EKS assumes this role to manage Kubernetes control-plane components,
# networking, and to call AWS APIs on your behalf.

resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.project_name}-eks-cluster-role"
  }
}

# Attach the AWS-managed policies required by the EKS control plane
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

# ── Security Group for the EKS Cluster ──────────────────────────────────────

resource "aws_security_group" "eks_cluster" {
  name_prefix = "${var.project_name}-eks-cluster-"
  description = "Security group for EKS cluster control plane"
  vpc_id      = aws_vpc.main.id

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-eks-cluster-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── EKS Cluster ──────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-eks"
  version  = var.eks_cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    # Place control-plane ENIs in private subnets for security;
    # also include public subnets so public LBs can be created.
    subnet_ids = concat(
      aws_subnet.private[*].id,
      aws_subnet.public[*].id
    )

    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  # Ensure IAM policies are attached before creating the cluster
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
  ]

  tags = {
    Name = "${var.project_name}-eks"
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# 2. EKS MANAGED NODE GROUP (Worker Nodes)
# ══════════════════════════════════════════════════════════════════════════════

# ── IAM Role for Worker Nodes ────────────────────────────────────────────────
# Each EC2 instance in the node group assumes this role. It needs permissions
# to join the cluster, pull images from ECR, and access DynamoDB.

resource "aws_iam_role" "eks_nodes" {
  name = "${var.project_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.project_name}-eks-node-role"
  }
}

# Attach the AWS-managed policies required by EKS worker nodes
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

# ── DynamoDB Access Policy for Worker Nodes ──────────────────────────────────
# Inline policy granting PutItem, GetItem, Scan, Query on the Votes table.
# This allows pods running on these nodes to read/write vote data.

resource "aws_iam_role_policy" "eks_nodes_dynamodb" {
  name = "${var.project_name}-dynamodb-access"
  role = aws_iam_role.eks_nodes.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:Scan",
        "dynamodb:Query"
      ]
      Resource = aws_dynamodb_table.votes.arn
    }]
  })
}

# ── Security Group for Worker Nodes ──────────────────────────────────────────

resource "aws_security_group" "eks_nodes" {
  name_prefix = "${var.project_name}-eks-nodes-"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  # Nodes can talk to each other on all ports (inter-pod communication)
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # Control plane to nodes communication
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  # Allow all outbound (image pulls, NAT gateway, DynamoDB endpoints, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-eks-nodes-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Allow cluster → node communication (for kubectl exec, logs, etc.)
resource "aws_security_group_rule" "cluster_to_nodes" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_security_group.eks_cluster.id
  description              = "Allow nodes to communicate with cluster API"
}

# ── Managed Node Group ───────────────────────────────────────────────────────
# Nodes are launched in private subnets and auto-join the EKS cluster.

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn

  # Worker nodes live in private subnets only
  subnet_ids = aws_subnet.private[*].id

  instance_types = var.node_instance_types
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ecr_read_only,
    aws_iam_role_policy.eks_nodes_dynamodb,
  ]

  tags = {
    Name = "${var.project_name}-nodes"
  }
}
