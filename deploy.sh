#!/bin/bash
##############################################################################
# deploy.sh — Full deployment pipeline for Voting App on AWS EKS
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
# Prerequisites:
#   - AWS CLI configured (aws configure)
#   - Terraform >= 1.5 installed
#   - kubectl installed
#   - Git repo URL set below
##############################################################################

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
AWS_REGION="eu-west-2"
CLUSTER_NAME="voting-app-eks"
GITHUB_REPO_URL="${GITHUB_REPO_URL:-https://github.com/<YOUR_USERNAME>/voting-app.git}"
INGRESS_NGINX_VERSION="controller-v1.10.0"
ARGOCD_VERSION="stable"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[STEP $1]${NC} $2"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || err "AWS CLI not configured. Run: aws configure"
echo -e "${GREEN}AWS Account:${NC} ${AWS_ACCOUNT_ID}"
echo -e "${GREEN}Region:${NC}      ${AWS_REGION}"
echo ""

##############################################################################
# STEP 1 — Provision AWS Infrastructure with Terraform
##############################################################################
log 1 "Provisioning AWS infrastructure (VPC, EKS, ECR, DynamoDB)..."

cd "$(dirname "$0")/infra"

terraform init -input=false

terraform apply -auto-approve \
  -var="aws_region=${AWS_REGION}"

# Capture Terraform outputs for later use
EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
ECR_FRONTEND_URL=$(terraform output -raw ecr_frontend_url)
ECR_BACKEND_URL=$(terraform output -raw ecr_backend_url)
ECR_AUTH_URL=$(terraform output -raw ecr_auth_url)

log 1 "Infrastructure provisioned successfully."
echo "   EKS Cluster:  ${EKS_CLUSTER_NAME}"
echo "   ECR Frontend: ${ECR_FRONTEND_URL}"
echo "   ECR Backend:  ${ECR_BACKEND_URL}"
echo "   ECR Auth:     ${ECR_AUTH_URL}"
echo ""

cd ..

##############################################################################
# STEP 2 — Connect kubectl to EKS Cluster
##############################################################################
log 2 "Configuring kubectl to connect to EKS cluster..."

aws eks update-kubeconfig \
  --name "${EKS_CLUSTER_NAME}" \
  --region "${AWS_REGION}"

# Verify connection
kubectl cluster-info || err "Cannot connect to EKS cluster"
echo ""
log 2 "kubectl connected. Nodes:"
kubectl get nodes
echo ""

##############################################################################
# STEP 3 — Install NGINX Ingress Controller
##############################################################################
log 3 "Installing NGINX Ingress Controller..."

kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_NGINX_VERSION}/deploy/static/provider/aws/deploy.yaml"

echo "Waiting for Ingress Controller pods to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s 2>/dev/null || warn "Ingress controller still starting — it may take a few minutes."

echo ""
log 3 "NGINX Ingress Controller installed."
echo ""

##############################################################################
# STEP 4 — Install ArgoCD
##############################################################################
log 4 "Installing ArgoCD..."

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "Waiting for ArgoCD server to be ready..."
kubectl wait --namespace argocd \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=argocd-server \
  --timeout=180s 2>/dev/null || warn "ArgoCD server still starting — it may take a few minutes."

# Retrieve the initial admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 -d) || ARGOCD_PASSWORD="(not yet available — retry in a minute)"

echo ""
log 4 "ArgoCD installed."
echo "   Username: admin"
echo "   Password: ${ARGOCD_PASSWORD}"
echo ""

##############################################################################
# STEP 5 — Build & Push Docker Images to ECR
##############################################################################
log 5 "Building and pushing Docker images to ECR..."

# Login to ECR
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

IMAGE_TAG="initial"

# -- Auth Service --
echo "  Building auth-service..."
docker build -t "${ECR_AUTH_URL}:${IMAGE_TAG}" \
             -t "${ECR_AUTH_URL}:latest" \
             ./auth-service
docker push "${ECR_AUTH_URL}:${IMAGE_TAG}"
docker push "${ECR_AUTH_URL}:latest"

# -- Backend API --
echo "  Building backend-api..."
docker build -t "${ECR_BACKEND_URL}:${IMAGE_TAG}" \
             -t "${ECR_BACKEND_URL}:latest" \
             ./backend-api
docker push "${ECR_BACKEND_URL}:${IMAGE_TAG}"
docker push "${ECR_BACKEND_URL}:latest"

# -- Frontend --
echo "  Building frontend..."
docker build -t "${ECR_FRONTEND_URL}:${IMAGE_TAG}" \
             -t "${ECR_FRONTEND_URL}:latest" \
             ./frontend
docker push "${ECR_FRONTEND_URL}:${IMAGE_TAG}"
docker push "${ECR_FRONTEND_URL}:latest"

# Update K8s manifests with real ECR image URLs
sed -i.bak "s|<AWS_ACCOUNT_ID>.dkr.ecr.eu-west-2.amazonaws.com/voting-app-auth:latest|${ECR_AUTH_URL}:${IMAGE_TAG}|g" k8s/auth-deployment.yaml
sed -i.bak "s|<AWS_ACCOUNT_ID>.dkr.ecr.eu-west-2.amazonaws.com/voting-app-backend:latest|${ECR_BACKEND_URL}:${IMAGE_TAG}|g" k8s/backend-deployment.yaml
sed -i.bak "s|<AWS_ACCOUNT_ID>.dkr.ecr.eu-west-2.amazonaws.com/voting-app-frontend:latest|${ECR_FRONTEND_URL}:${IMAGE_TAG}|g" k8s/frontend-deployment.yaml
rm -f k8s/*.bak

echo ""
log 5 "All images pushed to ECR and manifests updated."
echo ""

##############################################################################
# STEP 6 — Deploy ArgoCD Application (connects Git repo → EKS)
##############################################################################
log 6 "Deploying ArgoCD Application..."

# Update the repo URL in the ArgoCD application manifest
sed -i.bak "s|<YOUR_GITHUB_REPO_URL>|${GITHUB_REPO_URL}|g" k8s/argocd-app.yaml
rm -f k8s/*.bak

# Apply all K8s manifests directly for the initial deployment
echo "  Applying K8s manifests..."
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/frontend-env-configmap.yaml
kubectl apply -f k8s/auth-deployment.yaml
kubectl apply -f k8s/auth-service.yaml
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/backend-service.yaml
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/frontend-service.yaml
kubectl apply -f k8s/ingress.yaml

# Apply ArgoCD Application — from here ArgoCD takes over GitOps
echo "  Registering ArgoCD Application..."
kubectl apply -f k8s/argocd-app.yaml

echo ""
log 6 "ArgoCD Application deployed. Waiting for pods..."
echo ""

# Wait for pods to start
kubectl wait --namespace voting-app \
  --for=condition=ready pod \
  --selector=app=auth-service \
  --timeout=120s 2>/dev/null || warn "auth-service pods still starting"
kubectl wait --namespace voting-app \
  --for=condition=ready pod \
  --selector=app=backend-api \
  --timeout=120s 2>/dev/null || warn "backend-api pods still starting"
kubectl wait --namespace voting-app \
  --for=condition=ready pod \
  --selector=app=frontend \
  --timeout=120s 2>/dev/null || warn "frontend pods still starting"

##############################################################################
# DONE — Print summary
##############################################################################
echo ""
echo "============================================================"
echo -e "${GREEN}  DEPLOYMENT COMPLETE${NC}"
echo "============================================================"
echo ""

# Get the ingress external address
INGRESS_URL=$(kubectl get ingress voting-app-ingress -n voting-app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) || INGRESS_URL="(pending)"

echo "  Voting App:   http://${INGRESS_URL}"
echo ""
echo "  ArgoCD UI:    Run: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "                Then open: https://localhost:8080"
echo "                Username:  admin"
echo "                Password:  ${ARGOCD_PASSWORD}"
echo ""
echo "  Pods:"
kubectl get pods -n voting-app
echo ""
echo "  Services:"
kubectl get svc -n voting-app
echo ""
echo "  Ingress:"
kubectl get ingress -n voting-app
echo ""
echo "============================================================"
echo -e "${GREEN}  ArgoCD is now watching k8s/ — push changes and it auto-syncs${NC}"
echo "============================================================"
