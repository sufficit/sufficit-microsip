# =================================================================================================
# BUILD SCRIPT FOR PJSIP SOLUTION (CALLED BY GITHUB ACTIONS WORKFLOW)
#
# Author: Hugo Castro de Deco, Sufficit
# Collaboration: Gemini AI for Google
# Date: June 15, 2025
# Version: 1
#
# This script builds the PJSIP solution using MSBuild, ensuring the correct configuration
# and platform are applied.
# =================================================================================================

param (
    [string]$SlnFile # Path to the PJSIP solution file, e.g., pjproject/pjproject-vs14.sln
)

$solutionPath = $SlnFile
$configuration = "Release"
$platform = "x64" # Changed from "Win32" to "x64"

# Path to msbuild.exe
# Ensure msbuild is in the PATH or provide a full path if necessary
# The 'microsoft/setup-msbuild@v2' action should add it to the PATH.
$msbuildPath = "msbuild.exe"

Write-Host "Building PJSIP solution: $solutionPath"
Write-Host "Configuration: $configuration"
Write-Host "Platform: $platform"

# Execute MSBuild
try {
    # Using /m for multi-core build, /p:Configuration and /p:Platform
    & $msbuildPath $solutionPath /p:Configuration=$configuration /p:Platform=$platform /m /t:Rebuild
    if ($LASTEXITCODE -ne 0) {
        Write-Host "##[error]MSBuild failed with exit code $LASTEXITCODE."
        exit 1
    }
} catch {
    Write-Host "##[error]An error occurred during MSBuild execution: $($_.Exception.Message)"
    exit 1
}