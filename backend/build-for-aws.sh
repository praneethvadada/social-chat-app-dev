#!/bin/bash

# Build all services
echo "Building all services..."
cd "$(dirname "$0")"
mvn clean package -DskipTests

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Build successful!"
    echo ""
    echo "JAR files created:"
    echo "  - api-gateway/target/api-gateway-1.0.0.jar"
    echo "  - auth-service/target/auth-service-1.0.0.jar"
    echo "  - social-service/target/social-service-1.0.0.jar"
    echo ""
    echo "Next steps:"
    echo "1. Review AWS_DEPLOYMENT_GUIDE.md"
    echo "2. Choose deployment method (Elastic Beanstalk or EC2)"
    echo "3. Set up AWS infrastructure (RDS, Redis)"
    echo "4. Deploy using chosen method"
else
    echo "✗ Build failed. Please fix errors and try again."
    exit 1
fi
