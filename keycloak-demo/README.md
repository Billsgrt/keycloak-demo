# Keycloak Demo — DevPortal on Kubernetes

A production-grade Keycloak SSO demo with a React DevPortal app, deployed on AWS EKS.

## What This Demo Shows
- Keycloak running on Kubernetes as the Identity Provider
- React app protected by OIDC / Authorization Code Flow
- JWT token inspection — see exactly what Keycloak issues
- Role-based access (admin, developer, viewer)
- Full K8s deployment: StatefulSets, Deployments, Services, Ingress

## Architecture
```
Browser → NGINX Ingress → /auth  → Keycloak Pod → PostgreSQL
                        → /      → DevPortal Pod (React)
```

## Quick Start

### Prerequisites
- AWS CLI configured (`aws configure`)
- eksctl, kubectl, helm, docker installed

### Deploy Step by Step
```bash
# Clone
git clone https://github.com/Billsgrt/keycloak-demo.git
cd keycloak-demo

# Run steps in order
bash deploy.sh 1   # Create EKS cluster (~15 min)
bash deploy.sh 2   # Install NGINX Ingress
bash deploy.sh 3   # Build & push Docker image
bash deploy.sh 4   # Deploy all K8s resources
bash deploy.sh 5   # Import Keycloak realm + users
bash deploy.sh 6   # Get your public URL
```

### After Your Demo — STOP BILLING
```bash
bash deploy.sh 7
```

## Demo Credentials
| Username | Password | Roles |
|----------|----------|-------|
| bilal | Demo@1234 | admin, developer |
| lead | Lead@1234 | viewer |

## Project Structure
```
keycloak-demo/
├── app/                    # React DevPortal
│   ├── src/App.jsx         # Main app with Keycloak integration
│   ├── src/App.css         # Dark theme styling
│   ├── Dockerfile          # Multi-stage build
│   ├── nginx.conf          # SPA serving config
│   └── docker-entrypoint.sh # Runtime env injection
├── k8s/
│   ├── 00-namespace.yaml   # keycloak-demo namespace
│   ├── 01-secrets.yaml     # DB + Keycloak credentials
│   ├── 02-postgres.yaml    # PostgreSQL StatefulSet
│   ├── 03-keycloak.yaml    # Keycloak Deployment
│   ├── 04-devportal.yaml   # React app Deployment
│   └── 05-ingress.yaml     # NGINX Ingress routing
├── keycloak-config/
│   └── realm-export.json   # Pre-configured realm, client, roles, users
└── deploy.sh               # Master deploy script
```

## Key Concepts Learned
- **Keycloak Realm** — isolated security domain for your app
- **OIDC Client** — registers your app with Keycloak
- **Authorization Code Flow** — how login redirects work
- **JWT Token** — what Keycloak issues after login
- **K8s StatefulSet** — for stateful apps like DBs and Keycloak
- **K8s Ingress** — single entry point, routes by path
- **ECR** — AWS private container registry

## Estimated Cost
- EKS Control Plane: ~₹8/hr
- 2x t3.medium nodes: ~₹14/hr  
- Load Balancer: ~₹7/hr
- **Total 4hrs: ~₹120**
- After `bash deploy.sh 7`: **₹0**
