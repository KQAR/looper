#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

tuist generate >/dev/null

PROJECT_FILE="Looper.xcodeproj/project.pbxproj"
SCHEME_DIR="Looper.xcodeproj/xcshareddata/xcschemes"
SCHEME_PATH="$SCHEME_DIR/Looper-Testing.xcscheme"

app_blueprint="$(
  awk '
    /Begin PBXNativeTarget section/ { in_section = 1 }
    /End PBXNativeTarget section/ { in_section = 0 }
    in_section && /\/\* Looper \*\// {
      gsub(/^[[:space:]]+/, "", $0)
      print $1
      exit
    }
  ' "$PROJECT_FILE"
)"
test_blueprint="$(
  awk '
    /Begin PBXNativeTarget section/ { in_section = 1 }
    /End PBXNativeTarget section/ { in_section = 0 }
    in_section && /\/\* LooperTests \*\// {
      gsub(/^[[:space:]]+/, "", $0)
      print $1
      exit
    }
  ' "$PROJECT_FILE"
)"

if [[ -z "$app_blueprint" || -z "$test_blueprint" ]]; then
  echo "Failed to resolve Looper or LooperTests target identifiers from $PROJECT_FILE" >&2
  exit 1
fi

mkdir -p "$SCHEME_DIR"

cat > "$SCHEME_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1010"
   version = "1.3">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "$app_blueprint"
               BuildableName = "Looper.app"
               BlueprintName = "Looper"
               ReferencedContainer = "container:Looper.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "$test_blueprint"
               BuildableName = "LooperTests.xctest"
               BlueprintName = "LooperTests"
               ReferencedContainer = "container:Looper.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <MacroExpansion>
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "$app_blueprint"
            BuildableName = "Looper.app"
            BlueprintName = "Looper"
            ReferencedContainer = "container:Looper.xcodeproj">
         </BuildableReference>
      </MacroExpansion>
      <Testables>
         <TestableReference
            skipped = "NO"
            parallelizable = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "$test_blueprint"
               BuildableName = "LooperTests.xctest"
               BlueprintName = "LooperTests"
               ReferencedContainer = "container:Looper.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "$app_blueprint"
            BuildableName = "Looper.app"
            BlueprintName = "Looper"
            ReferencedContainer = "container:Looper.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "$app_blueprint"
            BuildableName = "Looper.app"
            BlueprintName = "Looper"
            ReferencedContainer = "container:Looper.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
EOF

xcodebuild -workspace Looper.xcworkspace -scheme Looper-Testing test "$@"
