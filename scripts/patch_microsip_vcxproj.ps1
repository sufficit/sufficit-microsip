# =================================================================================================
# PATCH SCRIPT FOR MicroSIP PROJECT FILE (CALLED BY GITHUB ACTIONS WORKFLOW)
#
# This script adds PJSIP and MicroSIP's internal include and library paths to microsip.vcxproj.
#
# Changes:
#   - FIXED: Explicitly *replaces* `AdditionalLibraryDirectories` and `AdditionalDependencies`
#     with precisely controlled absolute paths and libraries. This eliminates potential conflicts
#     from existing relative paths or implicit default behaviors in the .vcxproj, addressing
#     persistent LNK1181 errors.
#   - FIXED: Corrected PowerShell parsing error "The term 'LibraryPath' is not recognized".
#     MSBuild variables like `$(LibraryPath)` and `%(AdditionalLibraryDirectories)` are now
#     correctly escaped or treated as literal strings within PowerShell, so they are passed
#     as-is into the XML.
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
        $itemDefinitionGroupNode = $projXml.CreateElement("ItemDefinitionGroup", <span class="math-inline">nsManager\.LookupNamespace\("msbuild"\)\)
\# Set the Condition attribute to the literal string '</span>(Configuration)|$(Platform)'=='Release|x64'.
        # In PowerShell, this is represented by enclosing it in single quotes and doubling any internal single quotes.
        <span class="math-inline">itemDefinitionGroupNode\.SetAttribute\("Condition", '''</span>(Configuration)|$(Platform)''==''Release|x64''')
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


    # Process AdditionalIncludeDirectories (Replace existing for full control)
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
        "<span class="math-inline">pjsipIncludePathForVcxproj\_Relative\\pjlib\\include\\pj\\opus",
\# Ensure MSBuild's default include paths are still present but at the end
'</span> (AdditionalIncludeDirectories)' # Escaped for PowerShell, literal in XML
    )

    $additionalIncludeDirsNode = $clCompileNode.SelectSingleNode("./msbuild:AdditionalIncludeDirectories", $nsManager)
    if (-not $additionalIncludeDirsNode) {
        $additionalIncludeDirsNode = $projXml.CreateElement("AdditionalIncludeDirectories", $nsManager.LookupNamespace("msbuild"))
        $clCompileNode.AppendChild($additionalIncludeDirsNode)
    }
    # Replace content, ensuring unique paths, with MSBuild's placeholder at the end
    # Note: Use -join ';' for string concatenation of array elements
    $additionalIncludeDirsNode.'#text' = ($requiredIncludes | Select-Object -Unique) -join ';'
    Write-Host "Set AdditionalIncludeDirectories in $ProjFile to: $($additionalIncludeDirsNode.'#text')"


    # Process AdditionalLibraryDirectories (Replace existing for full control)
    $requiredLibDirs = @(
        $pjsipLibPathForVcxproj_Absolute, # Absolute path to external/pjproject/lib (now centralized by renaming step)
        <span class="math-inline">thirdPartyLibPathForVcxproj\_Absolute, \# Absolute path to external/pjproject/third\_party/lib
\# Ensure MSBuild's default library paths are still present but at the end
'</span>(LibraryPath)', # Escaped for PowerShell, literal in XML
        '%(AdditionalLibraryDirectories)' # Escaped for PowerShell, literal in XML
    )

    $additionalLibraryDirsNode = $linkerNode.SelectSingleNode("./msbuild:AdditionalLibraryDirectories", $nsManager)
    if (-not $additionalLibraryDirsNode) {
        $additionalLibraryDirsNode = $projXml.CreateElement("AdditionalLibraryDirectories", $nsManager.LookupNamespace("msbuild"))
        $linkerNode.AppendChild($additionalLibraryDirsNode)
    }
    # Replace content, ensuring unique paths, with MSBuild's placeholders
    $additionalLibraryDirsNode.'#text' = ($requiredLibDirs | Select-Object -Unique) -join ';'
    Write-Host "Set AdditionalLibraryDirectories in $ProjFile to: $($additionalLibraryDirsNode.'#text')"


    # Add PJSIP additional dependencies (libraries) (Replace existing for full control)
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
    if (-not $additionalDependenciesNode) {
        $additionalDependenciesNode = $projXml.CreateElement("AdditionalDependencies", $nsManager.LookupNamespace("msbuild"))
        $linkerNode.AppendChild($additionalDependenciesNode)
    }
    # Replace content, ensuring unique libs, with MSBuild's placeholder
    # Note: Using Select-Object -Unique here to deduplicate combined lists.
    $finalDependenciesList = ($pjsipLibs + $windowsCommonLibs | Select-Object -Unique)
    # Append the MSBuild placeholder literally
    $additionalDependenciesNode.'#text' = ($finalDependenciesList -join ';') + ';%(AdditionalDependencies)'
    Write-Host "Set AdditionalDependencies in $ProjFile to: $($additionalDependenciesNode.'#text')"

    $projXml.Save($ProjFile)
    Write-Host "Successfully patched $ProjFile."
} catch {
    Write-Host "##[error]Error patching $($ProjFile): $($_.Exception.Message)"
    exit 1
}