# PlantUML Diagram Fix

## ✅ Issue Resolved

The PlantUML diagram error was caused by an outdated AWS icons URL that returned a 404 error:

**Problem URL:** `https://raw.githubusercontent.com/awslabs/aws-icons-for-plantuml/v18.0/dist`

## 🔧 Solutions Applied

### 1. Fixed Original Diagram (`BACKEND_ARCHITECTURE_DIAGRAM.puml`)
- ✅ Removed problematic AWS icon includes
- ✅ Replaced AWS-specific components with standard PlantUML rectangles
- ✅ Maintained all architectural information and connections

### 2. Created Simplified Version (`SIMPLIFIED_ARCHITECTURE_DIAGRAM.puml`)
- ✅ Clean, minimal design using only standard PlantUML elements
- ✅ All essential architectural components included
- ✅ Easier to render and understand

## 📊 Diagram Features

Both diagrams show:
- **Frontend Layer**: React/Angular applications
- **API Gateway**: Spring Cloud Gateway with routing and security
- **Microservices**: Auth Service (port 8081) and Social Service (port 8082)
- **Data Layer**: MySQL RDS and Redis ElastiCache
- **External Services**: AWS S3, Agora RTC, SMTP
- **Infrastructure**: AWS components (Load Balancer, EC2, RDS, etc.)
- **Data Flow**: All connections and relationships

## 🚀 Testing

To test the diagrams:
1. Open either `.puml` file in VS Code
2. Right-click → "Preview current PlantUML diagram"
3. Or use Ctrl+Shift+P → "PlantUML: Preview Current Diagram"

The diagrams should now render correctly without any 404 errors!

## 📁 Files Updated
- `BACKEND_ARCHITECTURE_DIAGRAM.puml` - Fixed original diagram
- `SIMPLIFIED_ARCHITECTURE_DIAGRAM.puml` - New simplified version