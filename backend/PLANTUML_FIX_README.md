# PlantUML Java Configuration Fix

## Problem
The PlantUML extension in VS Code is trying to use a corrupted or incomplete JDK 21 installation, causing the error:
```
Bad "plantuml.java" config: c:\Program Files\Java\jdk-21\bin\java.exe
Error: could not open `c:\Program Files\Java\jdk-21\lib\jvm.cfg'
```

## Solution Options

### Option 1: Configure VS Code PlantUML Extension (Recommended)

1. **Open VS Code User Settings** (Ctrl+Shift+P → "Preferences: Open User Settings (JSON)")

2. **Add these settings** to configure PlantUML to use JDK 17:
```json
{
    "plantuml.java": "C:\\Program Files\\Java\\jdk-17\\bin\\java.exe",
    "plantuml.exportFormat": "png",
    "plantuml.previewAutoUpdate": true
}
```

3. **Restart VS Code** completely

### Option 2: Use the Batch Script

Run the provided `fix_plantuml_java.bat` script to set the correct Java path for the current session.

### Option 3: System Environment Variables

1. **Set system JAVA_HOME**:
   - Open System Properties → Advanced → Environment Variables
   - Set `JAVA_HOME` to `C:\Program Files\Java\jdk-17`
   - Update PATH to include `%JAVA_HOME%\bin`

2. **Restart VS Code**

### Option 4: Remove Problematic Java Installation

If you don't need JDK 21, you can:
1. Uninstall JDK 21 from Windows Settings → Apps
2. Keep only JDK 17
3. Restart VS Code

## Verification

After applying any solution, verify that PlantUML works by:
1. Opening a `.puml` file
2. Right-clicking and selecting "Preview current PlantUML diagram"
3. Or using Ctrl+Shift+P → "PlantUML: Preview Current Diagram"

## Current Status

✅ **JDK 17 is properly installed** at `C:\Program Files\Java\jdk-17\bin\java.exe`
✅ **Java version confirmed working**: 17.0.12 LTS
✅ **Batch script tested successfully**

The diagrams (`BACKEND_ARCHITECTURE_DIAGRAM.puml` and `DATABASE_SCHEMA_DIAGRAM.puml`) should now render correctly once the PlantUML extension is configured to use JDK 17.