# =================================================================================================
# BUILD SCRIPT FOR PJSIP SOLUTION (CALLED BY GITHUB ACTIONS WORKFLOW)
#
# Author: Hugo Castro de Deco, Sufficit
# Collaboration: Gemini AI for Google
# Date: June 18, 2025
# Version: 2 (Added debug logging for $baseProjectName issue)
#
# This script builds the PJSIP solution using MSBuild, ensuring the correct configuration
# and platform are applied.
# =================================================================================================

param (
    [string]$SlnFile # Path to the PJSIP solution file, e.g., pjproject/pjproject-vs14.sln
)

# Enforce stricter parsing and error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

# Define the list of PJSIP projects to build
$pjsipProjectsToBuild = @(
    "pjlib/build/pjlib.vcxproj",
    "pjlib-util/build/pjlib_util.vcxproj",
    "pjnath/build/pjnath.vcxproj",
    "pjmedia/build/pjmedia.vcxproj",
    "pjmedia/build/pjmedia_audiodev.vcxproj",
    "pjmedia/build/pjmedia_codec.vcxproj",
    "pjmedia/build/pjmedia_videodev.vcxproj",
    "pjsip/build/pjsip_core.vcxproj",
    "pjsip/build/pjsip_simple.vcxproj",
    "pjsip/build/pjsip_ua.vcxproj",
    "pjsip/build/pjsua_lib.vcxproj",
    "pjsip/build/pjsua2_lib.vcxproj",
    "third_party/build/baseclasses/libbaseclasses.vcxproj",
    "third_party/build/g7221/libg7221codec.vcxproj",
    "third_party/build/gsm/libgsmcodec.vcxproj",
    "third_party/build/ilbc/libilbccodec.vcxproj",
    "third_party/build/milenage/libmilenage.vcxproj",
    "third_party/build/resample/libresample.vcxproj",
    "third_party/build/speex/libspeex.vcxproj",
    "third_party/build/srtp/libsrtp.vcxproj",
    "third_party/build/webrtc/libwebrtc.vcxproj",
    "third_party/build/yuv/libyuv.vcxproj"
)

# Mapping of base project names (from vcxproj, normalized) to desired simple names.
# The keys here are the base name of the project, standardized to hyphens if original has them,
# or the simple name if no hyphen/underscore issue.
# The values are the final names that MicroSIP expects.
# Opus is already handled separately.
$libRenames = @{
    "pjlib" = "pjlib.lib";
    "pjlib-util" = "pjlib-util.lib"; # pjlib_util.vcxproj -> pjlib-util.lib
    "pjnath" = "pjnath.lib";
    "pjmedia" = "pjmedia.lib";
    "pjmedia-audiodev" = "pjmedia-audiodev.lib";
    "pjmedia-codec" = "pjmedia-codec.lib";
    "pjmedia-videodev" = "pjmedia-videodev.lib";
    "pjsip-core" = "pjsip-core.lib";
    "pjsip-simple" = "pjsip-simple.lib";
    "pjsip-ua" = "pjsip-ua.lib";
    "pjsua-lib" = "pjsua-lib.lib";
    "pjsua2-lib" = "pjsua2-lib.lib";
    "libbaseclasses" = "libbaseclasses.lib";
    "libg7221codec" = "libg7221codec.lib";
    "libgsmcodec" = "libgsmcodec.lib";
    "libilbccodec" = "libilbccodec.lib";
    "libmilenage" = "libmilenage.lib";
    "libresample" = "libresample.lib";
    "libspeex" = "libspeex.lib";
    "libsrtp" = "libsrtp.lib";
    "libwebrtc" = "libwebrtc.lib";
    "libyuv" = "libyuv.lib"
}

try {
    # Define the central PJSIP lib directory outside the loop
    $centralPjsipLibDir = Join-Path -Path $env:GITHUB_WORKSPACE -ChildPath "external/pjproject/lib"
    New-Item -ItemType Directory -Path $centralPjsipLibDir -Force | Out-Null

    foreach ($projectFile in $pjsipProjectsToBuild) {
        $fullProjectPath = Join-Path -Path $env:GITHUB_WORKSPACE -ChildPath "external/pjproject/$projectFile"
        Write-Host "Compiling project: $fullProjectPath"

        # Debugging: Show the current project file and calculated base name
        Write-Host "DEBUG: Processing projectFile: '$projectFile'"
        $baseProjectName = [System.IO.Path]::GetFileNameWithoutExtension($projectFile).Replace('_', '-').Replace('.vcxproj', '')
        Write-Host "DEBUG: Calculated baseProjectName: '$baseProjectName'"
        
        # Check if baseProjectName is null or empty after processing
        if ([string]::IsNullOrEmpty($baseProjectName)) {
            Write-Host "##[error]Error: Calculated baseProjectName is null or empty for projectFile '$projectFile'. This indicates an unexpected path format or processing issue."
            exit 1
        }

        $rawMsbuildOutput = & $msbuildPath "$fullProjectPath" /p:Configuration=$configuration /p:Platform=$platform /m /t:Rebuild /p:ExcludeRestorePackageFolders=true /nologo
        Write-Host ($rawMsbuildOutput | Out-String)

        if ($LASTEXITCODE -ne 0) {
            Write-Host "##[error]PJSIP project compilation failed for $projectFile."
            exit 1
        }
        
        $actualOutputLibPath = $null
        foreach ($line in $rawMsbuildOutput) {
            # Capture both static (.lib) and dynamic (.dll) library outputs if they appear
            if ($line -match "(?i)\.vcxproj -> (.*\.lib)" -or $line -match "(?i)\.vcxproj -> (.*\.dll)") {
                $match = $matches[1]
                $actualOutputLibPath = $match.Trim()
                Write-Host "DEBUG: Extracted actual output .lib/.dll path from MSBuild output: $actualOutputLibPath"
                break
            }
        }

        if ([string]::IsNullOrEmpty($actualOutputLibPath)) {
            Write-Host "##[error]Error: Could not determine actual output .lib/.dll path from MSBuild log for $projectFile. This project might not produce a .lib or .dll, or the output format changed. Failing workflow."
            exit 1
        }
        
        $sourceLibPath = $actualOutputLibPath
        $actualLibFileName = [System.IO.Path]::GetFileName($sourceLibPath) # e.g., pjlib_util-x86_64-x64-vc14-Release.lib
        
        Write-Host "Contents of source directory of '$actualLibFileName':"
        Get-ChildItem -Path (Split-Path -Path $sourceLibPath -Parent) -ErrorAction SilentlyContinue | Format-List FullName, Name, Length, CreationTimeUtc, LastWriteTimeUtc
        Write-Host "--------------------------------------------------------"

        $foundLibFile = $null
        $maxRetries = 5
        $retryDelaySec = 2

        # Wait for the .lib/.dll file to exist at the *exact* path reported by MSBuild
        for ($i = 0; $i -lt $maxRetries; $i++) {
            Write-Host "Attempting to find freshly compiled library '$($actualLibFileName)' at '$($sourceLibPath)' (Attempt $($i + 1)/$maxRetries)..."
            if (Test-Path -Path $sourceLibPath -PathType Leaf -ErrorAction SilentlyContinue) {
                $foundLibFile = Get-Item -Path $sourceLibPath -ErrorAction SilentlyContinue
                if ($null -ne $foundLibFile) {
                    Write-Host "Found compiled file at exact path."
                    break
                }
            }
            if ($i -lt ($maxRetries - 1)) {
                Write-Host "File not found at exact path, retrying in ${retryDelaySec} seconds..."
                Start-Sleep -Seconds $retryDelaySec
            }
        }

        if ($null -eq $foundLibFile) {
            Write-Host "##[error]Error: Compiled library file '$($actualLibFileName)' was reported by MSBuild but not found at '$($sourceLibPath)' after all retries for processing. Failing workflow."
            exit 1
        }

        # Determine target name based on mapping or fallback to actual file name
        $targetLibName = $null
        if ($libRenames.ContainsKey($baseProjectName)) { # This is the line 144
            $targetLibName = $libRenames[$baseProjectName]
            Write-Host "DEBUG: Found rename mapping for base project name '$($baseProjectName)'. Target name: '$targetLibName'."
        } else {
            # Fallback: if no explicit rename mapping for the base project name, use the actual compiled file name.
            $targetLibName = $actualLibFileName
            Write-Host "##[warning]Warning: No specific rename mapping found for base project name '$($baseProjectName)'. Using original compiled file name as target: '$targetLibName'."
        }

        $targetLibPath = Join-Path -Path $centralPjsipLibDir -ChildPath $targetLibName
        
        Write-Host "Moving '$($foundLibFile.Name)' from '$($foundLibFile.FullName)' to '$($targetLibPath)'."
        Move-Item -Path $foundLibFile.FullName -Destination $targetLibPath -Force
    }
    Write-Host "PJSIP compilation completed."
    Set-Location $env:GITHUB_WORKSPACE
    Write-Host "Returning to MicroSIP root directory: $(Get-Location)"

} catch {
    Write-Host "##[error]Error during PJSIP compilation: $($_.Exception.Message)"
    exit 1
}