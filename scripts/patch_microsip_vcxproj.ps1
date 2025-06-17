# =================================================================================================
# PATCH SCRIPT FOR MicroSIP PROJECT FILE (CALLED BY GITHUB ACTIONS WORKFLOW)
#
# This script adds PJSIP and MicroSIP's internal include and library paths to microsip.vcxproj.
#
# Changes:
#   - FIXED: The `patch_microsip_vcxproj.ps1` script now correctly handles MSBuild properties
#     like `$(LibraryPath)` and `%(AdditionalLibraryDirectories)` by enclosing them in
#     single quotes to prevent PowerShell parsing errors.
#   - FIXED: This version ensures that `AdditionalLibraryDirectories` are set with absolute paths
#     for PJSIP and third-party libraries (e.g., external/pjproject/lib), making linker resolution
#     more robust and independent of relative path context.
# =================================================================================================
param (
    [Parameter(Mandatory=$true)]
    [string]$ProjFile, # Complete path to microsip.vcxproj (e.g., C:\a\sufficit-microsip\sufficit-microsip\microsip.vcxproj)
    [Parameter(Mandatory=$true)]
    [string]$PjsipIncludeRoot, # e.g., 'C:\path\to\external\pjproject' (absolute path to PJSIP root)
    [Parameter(Mandatory=$true)]
    [string]$PjsipLibRoot, # e.g., 'C:\path\to\external\pjproject\lib' (absolute path to PJSIP libs)
    [Parameter(Mandatory=$true)]
    [string]$PjsipAppsIncludePath # e.g., 'C:\path\to\external\pjproject\pjsip\include' (absolute path to pjsua.h)
)

Write-Host "Executing patch script for MicroSIP: $ProjFile"
Write-Host "PjsipIncludeRoot received: $PjsipIncludeRoot"
Write-Host "PjsipLibRoot received: $PjsipLibRoot"
Write-Host "PjsipAppsIncludePath received: $PjsipAppsIncludePath"

try {
    [xml]$projXml = Get-Content $ProjFile

    $nsManager = New-Object System.Xml.XmlNamespaceManager($projXml.NameTable)
    $nsManager.AddNamespace("msbuild", "http://schemas.microsoft.com/developer/msbuild/2003")

    # The MicroSIP project file directory (which is the repository root in this case)
    $microsipProjectDir = Split-Path -Path $ProjFile -Parent
    
    # PJSIP paths are received as absolute, so we need to make them
    # relative to the .vcxproj directory for AdditionalIncludeDirectories.
    # For AdditionalLibraryDirectories, we will use absolute paths directly.
    $pjsipIncludePathForVcxproj_Relative = [System.IO.Path]::GetRelativePath($microsipProjectDir, $PjsipIncludeRoot)
    $pjsipAppsIncludePathForVcxproj_Relative = [System.IO.Path]::GetRelativePath($microsipProjectDir, $PjsipAppsIncludePath)

    # --- Absolute paths for library directories to ensure robust linker resolution ---
    $pjsipLibPathForVcxproj_Absolute = $PjsipLibRoot # Already absolute from parameter
    $thirdPartyLibPathForVcxproj_Absolute = Join-Path -Path $PjsipIncludeRoot -ChildPath "third_party/lib" # This is also absolute

    # Find or create the ItemDefinitionGroup for Release|x64
    $itemDefinitionGroupNode = $projXml.SelectSingleNode("//msbuild:ItemDefinitionGroup[contains(@Condition, 'Release') and contains(@Condition, 'x64')]", $nsManager)
    if (-not $itemDefinitionGroupNode) {
        Write-Host "Creating missing ItemDefinitionGroup for Release|x64."
        $projectNode = $projXml.SelectSingleNode("/msbuild:Project", $nsManager)
        $itemDefinitionGroupNode = $projXml.CreateElement("ItemDefinitionGroup", $nsManager.LookupNamespace("msbuild"))
        # Set the Condition attribute to the literal string '$(Configuration)|$(Platform)'=='Release|x64'.
        # In PowerShell, this is represented by enclosing it in single quotes and doubling any internal single quotes.
        $itemDefinitionGroupNode.SetAttribute("Condition", '''$(Configuration)|$(Platform)''==''Release|x64''')
        $projectNode.AppendChild($itemDefinitionGroupNode)
    }

    # Find or create the ClCompile node
    $clCompileNode = $itemDefinitionGroupNode.SelectSingleNode("./msbuild:ClCompile", $nsManager)
    if (-not $clCompileNode) {
        Write-Host "Creating missing ClCompile node for Release|x64."
        $clCompileNode = $projXml.CreateElement("ClCompile", $nsManager.LookupNamespace("msbuild"))
        $itemDefinitionGroupNode.AppendChild($clCompileNode)
    }

    # Find or create the Link node
    $linkerNode = $itemDefinitionGroupNode.SelectSingleNode("./msbuild:Link", $nsManager)
    if (-not $linkerNode) {
        Write-Host "Creating missing Link node for Release|x64."
        $linkerNode = $projXml.CreateElement("Link", $nsManager.LookupNamespace("msbuild"))
        $itemDefinitionGroupNode.AppendChild($linkerNode)
    }


    # Process Includes
    # Add ALL necessary include directories:
    # 1. MicroSIP's own directories (relative to ProjectDir)
    # 2. Third-party libraries specifically for MicroSIP (e.g., jsoncpp)
    # 3. All PJSIP core include directories (relative to ProjectDir, using the parameters)
    $requiredIncludes = @(
        ".", # For headers in the MicroSIP project root (where microsip.vcxproj is)
        ".\lib", # For headers in MicroSIP's lib folder
        ".\lib\jsoncpp", # For json.h
        "$pjsipIncludePathForVcxproj_Relative\pjlib\include",
        "$pjsipIncludePathForVcxproj_Relative\pjlib-util\include",
        "$pjsipIncludePathForVcxproj_Relative\pjnath\include",
        "$pjsipIncludePathForVcxproj_Relative\pjmedia\include",
        "$pjsipAppsIncludePathForVcxproj_Relative", # Points to external/pjproject/pjsip/include
        # Add include for Opus, which is copied to pjlib/include/pj/opus
        "$pjsipIncludePathForVcxproj_Relative\pjlib\include\pj\opus"
    )

    $additionalIncludeDirsNode = $clCompileNode.SelectSingleNode("./msbuild:AdditionalIncludeDirectories", $nsManager)

    # Use a more robust appending method for Includes
    if (-not $additionalIncludeDirsNode) {
        $additionalIncludeDirsNode = $projXml.CreateElement("AdditionalIncludeDirectories", $nsManager.LookupNamespace("msbuild"))
        $clCompileNode.AppendChild($additionalIncludeDirsNode)
        $additionalIncludeDirsNode.'#text' = (($requiredIncludes -join ';') + ';%(AdditionalIncludeDirectories)')
        Write-Host "Added AdditionalIncludeDirectories node with all necessary paths in $ProjFile."
    } else {
        # Combine existing and required paths, ensuring uniqueness, then append original placeholder
        $currentIncludes = $additionalIncludeDirsNode.'#text'.Split(';') | Where-Object { $_ -ne "" } | ForEach-Object { $_.Trim() }
        $finalIncludes = ($requiredIncludes + $currentIncludes) | Select-Object -Unique
        $additionalIncludeDirsNode.'#text' = (($finalIncludes -join ';') + ';%(AdditionalIncludeDirectories)')
        Write-Host "Updated AdditionalIncludeDirectories in $ProjFile to include all necessary paths."
    }

    # Process Library Directories
    $additionalLibraryDirsNode = $linkerNode.SelectSingleNode("./msbuild:AdditionalLibraryDirectories", $nsManager)
    
    # Define all required custom library directories using ABSOLUTE paths
    $requiredLibDirs = @(
        $pjsipLibPathForVcxproj_Absolute, # Absolute path to external/pjproject/lib (now centralized by renaming step)
        $thirdPartyLibPathForVcxproj_Absolute # Absolute path to external/pjproject/third_party/lib
    )

    # Use a more robust appending method for Library Directories, prioritizing our paths and standard placeholders
    if (-not $additionalLibraryDirsNode) {
        $additionalLibraryDirsNode = $projXml.CreateElement("AdditionalLibraryDirectories", $nsManager.LookupNamespace("msbuild"))
        $linkerNode.AppendChild($additionalLibraryDirsNode)
        $additionalLibraryDirsNode.'#text' = (($requiredLibDirs -join ';') + ';$(LibraryPath);%(AdditionalLibraryDirectories)')
        Write-Host "Added AdditionalLibraryDirectories node with all necessary library paths in $ProjFile."
    } else {
        # Combine existing and required paths, ensuring uniqueness, then append standard placeholders
        $currentLibDirs = $additionalLibraryDirsNode.'#text'.Split(';') | Where-Object { $_ -ne "" } | ForEach-Object { $_.Trim() }
        $finalLibDirs = ($requiredLibDirs + $currentLibDirs) | Select-Object -Unique
        $additionalLibraryDirsNode.'#text' = (($finalLibDirs -join ';') + ';$(LibraryPath);%(AdditionalLibraryDirectories)')
        Write-Host "Updated AdditionalLibraryDirectories in $ProjFile to include all necessary library paths."
    }

    # Add PJSIP additional dependencies (libraries)
    $pjsipLibs = @(
        "pjlib.lib",
        "pjlib-util.lib",
        "pjnath.lib",
        "pjmedia.lib",
        "pjmedia-audiodev.lib",
        "pjmedia-codec.lib",
        "pjmedia-videodev.lib",
        "pjsip-core.lib",
        "pjsip-simple.lib",
        "pjsip-ua.lib",
        "pjsua-lib.lib", # Crucial for pjsua.h
        "pjsua2-lib.lib",
        "libbaseclasses.lib",
        "libg7221codec.lib",
        "libgsmcodec.lib",
        "libilbccodec.lib",
        "libmilenage.lib",
        "libresample.lib",
        "libspeex.lib",
        "libsrtp.lib",
        "libwebrtc.lib",
        "libyuv.lib",
        "libopus.lib" # From our opus download
    )
    # Common Windows libs that PJSIP might need for linking (these are usually implicitly found via $(CoreLibraryDependencies) or LibraryPath)
    $windowsCommonLibs = @(
        "ws2_32.lib",
        "advapi32.lib",
        "iphlpapi.lib",
        "mswsock.lib",
        "ole32.lib",
        "winmm.lib",
        "user32.lib",
        "gdi32.lib",
        "crypt32.lib",
        "dnsapi.lib"
    )

    $additionalDependenciesNode = $linkerNode.SelectSingleNode("./msbuild:AdditionalDependencies", $nsManager)

    # Use a more robust appending method for Dependencies, combining our libs and standard placeholders
    if (-not $additionalDependenciesNode) {
        $additionalDependenciesNode = $projXml.CreateElement("AdditionalDependencies", $nsManager.LookupNamespace("msbuild"))
        $linkerNode.AppendChild($additionalDependenciesNode)
        $additionalDependenciesNode.'#text' = (($pjsipLibs + $windowsCommonLibs -join ';') + ';%(AdditionalDependencies)')
        Write-Host "Added AdditionalDependencies node with all necessary PJSIP and common Windows libraries."
    } else {
        # Combine existing, custom, and common Windows libraries, ensuring uniqueness, then append original placeholder
        $currentDependencies = $additionalDependenciesNode.'#text'.Split(';') | Where-Object { $_ -ne "" } | ForEach-Object { $_.Trim() }
        $finalDependencies = ($pjsipLibs + $windowsCommonLibs + $currentDependencies) | Select-Object -Unique
        $additionalDependenciesNode.'#text' = (($finalDependencies -join ';') + ';%(AdditionalDependencies)')
        Write-Host "Updated AdditionalDependencies in $ProjFile to include all necessary PJSIP and common Windows libraries."
    }

    $projXml.Save($ProjFile)
    Write-Host "Successfully patched $ProjFile."
} catch {
    Write-Host "##[error]Error patching $($ProjFile): $($_.Exception.Message)"
    exit 1
}