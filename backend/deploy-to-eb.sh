#!/bin/bash

# Quick deployment script for AWS Elastic Beanstalk
# Usage: ./deploy-to-eb.sh [auth|social|gateway|all]

set -e

SERVICE=$1
REGION=${AWS_REGION:-us-east-1}

deploy_service() {
    local service_name=$1
    local service_dir=$2
    
    echo "📦 Deploying $service_name..."
    
    cd "$service_dir"
    
    # Check if EB is initialized
    if [ ! -d ".elasticbeanstalk" ]; then
        echo "⚠️  Elastic Beanstalk not initialized for $service_name"
        echo "Run: eb init -p corretto-17 ${service_name}-app --region $REGION"
        echo "Then: eb create ${service_name}-env"
        exit 1
    fi
    
    # Build JAR
    echo "Building $service_name..."
    mvn clean package -DskipTests
    
    # Deploy
    echo "Deploying $service_name to Elastic Beanstalk..."
    eb deploy
    
    echo "✅ $service_name deployed successfully!"
    cd - > /dev/null
}

case $SERVICE in
    auth)
        deploy_service "auth-service" "backend/auth-service"
        ;;
    social)
        deploy_service "social-service" "backend/social-service"
        ;;
    gateway)
        deploy_service "api-gateway" "backend/api-gateway"
        ;;
    all)
        deploy_service "auth-service" "backend/auth-service"
        deploy_service "social-service" "backend/social-service"
        deploy_service "api-gateway" "backend/api-gateway"
        ;;
    *)
        echo "Usage: $0 [auth|social|gateway|all]"
        echo ""
        echo "Examples:"
        echo "  $0 auth       - Deploy auth service only"
        echo "  $0 social     - Deploy social service only"
        echo "  $0 gateway    - Deploy API gateway only"
        echo "  $0 all        - Deploy all services"
        exit 1
        ;;
esac

echo ""
echo "🎉 Deployment complete!"
echo "Check status with: eb status"
echo "View logs with: eb logs"
