#!/bin/bash
# =============================================================================
# KEYCLOAK DEMO — COMPLETE DEPLOY SCRIPT
# Run each section one at a time. Read comments to understand what's happening.
# =============================================================================

# YOUR DETAILS — fill these in before running anything
AWS_ACCOUNT_ID="075729034361"
AWS_REGION="ap-south-1"
CLUSTER_NAME="keycloak-demo"
ECR_REPO="devportal"

echo "============================================"
echo " KEYCLOAK DEMO DEPLOY GUIDE"
echo "============================================"

# =============================================================================
# STEP 1 — CREATE EKS CLUSTER
# This creates a real Kubernetes cluster on AWS with 2 worker nodes.
# Takes ~15 minutes. Go make tea.
# =============================================================================
step1_create_cluster() {
  echo ""
  echo "STEP 1: Creating EKS cluster..."
  echo "This takes ~15 minutes. Do not close PowerShell."
  echo ""

  eksctl create cluster \
    --name $CLUSTER_NAME \
    --region $AWS_REGION \
    --nodegroup-name standard-workers \
    --node-type t3.medium \
    --nodes 2 \
    --nodes-min 1 \
    --nodes-max 3 \
    --managed

  echo ""
  echo "Cluster created! Verifying nodes..."
  kubectl get nodes
}

# =============================================================================
# STEP 2 — INSTALL NGINX INGRESS CONTROLLER
# This installs the NGINX ingress controller which gives us a public IP.
# Think of it as the front door of our entire cluster.
# =============================================================================
step2_install_ingress() {
  echo ""
  echo "STEP 2: Installing NGINX Ingress Controller..."

  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/aws/deploy.yaml

  echo "Waiting for ingress controller to start..."
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=120s

  echo ""
  echo "Getting your public IP (may take 2-3 minutes)..."
  echo "Run this command and wait until EXTERNAL-IP shows an IP, not <pending>:"
  echo ""
  echo "  kubectl get svc -n ingress-nginx ingress-nginx-controller"
}

# =============================================================================
# STEP 3 — BUILD AND PUSH DOCKER IMAGE TO ECR
# ECR = Elastic Container Registry = AWS's private Docker Hub.
# We build your React app into a Docker image and push it there.
# =============================================================================
step3_build_and_push() {
  echo ""
  echo "STEP 3: Building React app and pushing to ECR..."

  # Create ECR repository
  aws ecr create-repository \
    --repository-name $ECR_REPO \
    --region $AWS_REGION 2>/dev/null || echo "ECR repo already exists, continuing..."

  # Login to ECR
  aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin \
    $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

  # Build the Docker image
  cd app
  docker build -t $ECR_REPO:latest .

  # Tag and push
  docker tag $ECR_REPO:latest \
    $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest

  docker push \
    $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest

  cd ..
  echo ""
  echo "Image pushed to ECR successfully!"
  echo "Image: $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest"
}

# =============================================================================
# STEP 4 — DEPLOY EVERYTHING TO KUBERNETES
# Applies all our YAML files to the cluster.
# Order matters: namespace → secrets → postgres → keycloak → app → ingress
# =============================================================================
step4_deploy_k8s() {
  echo ""
  echo "STEP 4: Deploying all K8s resources..."

  # Get ingress IP first
  INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

  if [ -z "$INGRESS_IP" ]; then
    echo "ERROR: Ingress IP not ready yet. Run step2 and wait for EXTERNAL-IP."
    exit 1
  fi

  echo "Ingress IP/hostname: $INGRESS_IP"

  # Update image in devportal deployment
  sed -i "s|YOUR_AWS_ACCOUNT_ID|$AWS_ACCOUNT_ID|g" k8s/04-devportal.yaml
  sed -i "s|INGRESS_IP|$INGRESS_IP|g" k8s/04-devportal.yaml
  sed -i "s|INGRESS_IP|$INGRESS_IP|g" keycloak-config/realm-export.json

  # Apply all manifests in order
  kubectl apply -f k8s/00-namespace.yaml
  kubectl apply -f k8s/01-secrets.yaml
  kubectl apply -f k8s/02-postgres.yaml

  echo "Waiting for PostgreSQL to be ready..."
  kubectl wait --namespace keycloak-demo \
    --for=condition=ready pod \
    --selector=app=postgres \
    --timeout=120s

  kubectl apply -f k8s/03-keycloak.yaml

  echo "Waiting for Keycloak to start (this takes ~2 minutes)..."
  kubectl wait --namespace keycloak-demo \
    --for=condition=ready pod \
    --selector=app=keycloak \
    --timeout=180s

  kubectl apply -f k8s/04-devportal.yaml
  kubectl apply -f k8s/05-ingress.yaml

  echo ""
  echo "All resources deployed!"
  kubectl get all -n keycloak-demo
}

# =============================================================================
# STEP 5 — IMPORT KEYCLOAK REALM
# This auto-configures Keycloak with our realm, client, roles and users.
# No manual clicking in admin UI needed!
# =============================================================================
step5_import_realm() {
  echo ""
  echo "STEP 5: Importing Keycloak realm config..."

  # Get keycloak pod name
  KC_POD=$(kubectl get pod -n keycloak-demo -l app=keycloak -o jsonpath='{.items[0].metadata.name}')

  echo "Keycloak pod: $KC_POD"

  # Copy realm config into the pod
  kubectl cp keycloak-config/realm-export.json \
    keycloak-demo/$KC_POD:/tmp/realm-export.json

  # Import the realm using kcadm
  kubectl exec -n keycloak-demo $KC_POD -- \
    /opt/keycloak/bin/kcadm.sh config credentials \
    --server http://localhost:8080 \
    --realm master \
    --user admin \
    --password 'Admin@2024!'

  kubectl exec -n keycloak-demo $KC_POD -- \
    /opt/keycloak/bin/kcadm.sh create realms \
    -f /tmp/realm-export.json

  echo ""
  echo "Realm imported! Users created:"
  echo "  Username: bilal    Password: Demo@1234   Roles: admin, developer"
  echo "  Username: lead     Password: Lead@1234   Roles: viewer"
}

# =============================================================================
# STEP 6 — GET YOUR PUBLIC URL
# =============================================================================
step6_get_url() {
  echo ""
  echo "STEP 6: Getting your public URL..."

  INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

  echo ""
  echo "============================================"
  echo " YOUR DEMO IS LIVE!"
  echo "============================================"
  echo ""
  echo " App URL:      http://$INGRESS_IP"
  echo " Keycloak:     http://$INGRESS_IP/auth"
  echo " Admin UI:     http://$INGRESS_IP/auth/admin"
  echo ""
  echo " Share this link with your lead: http://$INGRESS_IP"
  echo ""
  echo " Login credentials:"
  echo "   bilal / Demo@1234   (admin + developer roles)"
  echo "   lead  / Lead@1234   (viewer role)"
  echo "============================================"
}

# =============================================================================
# STEP 7 — CLEANUP (RUN THIS AFTER YOUR DEMO TO STOP BILLING!)
# This deletes EVERYTHING. Run after your demo is done.
# After this command, billing stops completely.
# =============================================================================
step7_cleanup() {
  echo ""
  echo "CLEANUP: Deleting all AWS resources..."
  echo "This stops ALL billing."
  echo ""

  # Delete ECR images
  aws ecr batch-delete-image \
    --repository-name $ECR_REPO \
    --region $AWS_REGION \
    --image-ids imageTag=latest 2>/dev/null

  aws ecr delete-repository \
    --repository-name $ECR_REPO \
    --region $AWS_REGION \
    --force 2>/dev/null

  # Delete EKS cluster (this also deletes all nodes and load balancer)
  eksctl delete cluster \
    --name $CLUSTER_NAME \
    --region $AWS_REGION

  echo ""
  echo "All resources deleted. Billing stopped."
  echo "Verify in AWS Console > Cost Explorer tomorrow."
}

# =============================================================================
# USEFUL COMMANDS — reference these while debugging
# =============================================================================
show_useful_commands() {
  echo ""
  echo "USEFUL KUBECTL COMMANDS:"
  echo ""
  echo "# See all pods"
  echo "kubectl get pods -n keycloak-demo"
  echo ""
  echo "# See logs for keycloak"
  echo "kubectl logs -n keycloak-demo -l app=keycloak --tail=50"
  echo ""
  echo "# See logs for devportal"
  echo "kubectl logs -n keycloak-demo -l app=devportal --tail=50"
  echo ""
  echo "# Describe a pod (see events, errors)"
  echo "kubectl describe pod -n keycloak-demo -l app=keycloak"
  echo ""
  echo "# Get ingress IP"
  echo "kubectl get svc -n ingress-nginx ingress-nginx-controller"
  echo ""
  echo "# Watch pods starting up live"
  echo "kubectl get pods -n keycloak-demo -w"
  echo ""
  echo "# Port forward keycloak locally (for testing)"
  echo "kubectl port-forward -n keycloak-demo svc/keycloak 8080:8080"
}

# =============================================================================
# MAIN — uncomment the step you want to run
# =============================================================================
echo ""
echo "Which step do you want to run?"
echo "1) step1_create_cluster"
echo "2) step2_install_ingress"
echo "3) step3_build_and_push"
echo "4) step4_deploy_k8s"
echo "5) step5_import_realm"
echo "6) step6_get_url"
echo "7) step7_cleanup  <-- RUN THIS AFTER DEMO!"
echo "8) show_useful_commands"
echo ""
echo "Run: bash deploy.sh <step_number>"
echo "Example: bash deploy.sh 1"
echo ""

case "$1" in
  1) step1_create_cluster ;;
  2) step2_install_ingress ;;
  3) step3_build_and_push ;;
  4) step4_deploy_k8s ;;
  5) step5_import_realm ;;
  6) step6_get_url ;;
  7) step7_cleanup ;;
  8) show_useful_commands ;;
  *) echo "Usage: bash deploy.sh <1-8>" ;;
esac
