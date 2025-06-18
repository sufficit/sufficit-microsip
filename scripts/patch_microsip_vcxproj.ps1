# =================================================================================================
# PATCH SCRIPT FOR MicroSIP PROJECT FILE (CALLED BY GITHUB ACTIONS WORKFLOW)
#
# Author: Hugo Castro de Deco, Sufficit
# Collaboration: Gemini AI for Google
# Date: June 18, 2025 - 00:35:00 AM -03
# Version: 1.0.71
#
# This script adds PJSIP and MicroSIP's internal include and library paths to microsip.vcxproj.
#
# Changes:
#   - FIXED: Explicitly *replaces* `AdditionalLibraryDirectories` and `AdditionalDependencies`
#     with precisely controlled absolute paths and libraries. This eliminates potential conflicts
#     from existing relative paths or implicit default behaviors in the .vcxproj, addressing
#     persistent LNK1181 errors.
#   - FIXED: Corrected PowerShell parsing error "No characters are allowed after a here-string header".
#     The here-string syntax for the XML "Condition" attribute is now correctly formatted.
#   - FIXED: Corrected the include path for 'json.h' from '.\lib\jsoncpp' to '.\lib\jsoncpp\json'.
#   - Removed the `%(AdditionalIncludeDirectories)` and `%(AdditionalLibraryDirectories)` placeholders
#     from the final XML output strings for absolute control over build paths, as all necessary
#     paths are now explicitly listed.
#   - ADDED: Explicitly removes any existing <AdditionalDependencies> nodes that might contain
#     the old 'libpjproject-x86_64-x64-vc14-Release-Static.lib' reference to prevent LNK1104.
#   - ADDED: Version and timestamp to script header for traceability.
#   - FIXED: Corrected the handling of `$(LibraryPath)` in AdditionalLibraryDirectories to ensure
#     it's passed as an MSBuild macro, not a PowerShell variable. This was the root cause of
#     "The term 'LibraryPath' is not recognized" error.
# =================================================================================================
param (
    [Parameter(Mandatory=$true)]
    [string]$ProjFile, # Complete path to microsip.vcxproj (e.g., C:\a\sufficit-microsip\sufficit-microsip\microsip.vcxproj)
    [Parameter(Mandatory=$true)]
    [string]$PjsipIncludeRoot, # e.g., 'C:\a\sufficit-microsip\sufficit-microsip\external\pjproject'
    [Parameter(Mandatory=$true)]
    [string]$PjsipLibRoot, # e.g., 'C:\a\sufficit-microsip\sufficit-microsip\external\pjproject\lib'
    [Parameter(Mandatory=$true)]
    [string]$PjsipAppsIncludePath # e.g., 'C:\a\sufficit-microsip\sufficit-microsip\external\pjproject\pjsip\include'
)

Write-Host "Executing patch script for MicroSIP: $ProjFile"
Write-Host "PjsipIncludeRoot received: $PjsipIncludeRoot"
Write-Host "PjsipLibRoot received: $PjsipLibRoot"
Write-Host "PjsipAppsIncludePath received: $PjsipAppsIncludePath"

try {
    [xml]$projXml = Get-Content $ProjFile

    $nsManager = New-Object System.Xml.XmlNamespaceManager($projXml.NameTable)
    $nsManager.AddNamespace("msbuild", "http://schemas.microsoft.com/developer/msbuild/2003")

    # Select the relevant ItemDefinitionGroup for Release|x64
    $itemDefinitionGroupNode = $projXml.SelectSingleNode("//msbuild:ItemDefinitionGroup[contains(@Condition, 'Release') and contains(@Condition, 'x64')]", $nsManager)

    if (-not $itemDefinitionGroupNode) {
        Write-Host "##[error]Error: Could not find Release|x64 ItemDefinitionGroup in $ProjFile."
        exit 1
    }

    # --- Patching Include Paths ---
    $clCompileNode = $itemDefinitionGroupNode.SelectSingleNode("./msbuild:ClCompile", $nsManager)
    if (-not $clCompileNode) {
        Write-Host "##[error]Error: Could not find ClCompile node within Release|x64 ItemDefinitionGroup in $ProjFile."
        exit 1
    }

    $additionalIncludeDirsNode = $clCompileNode.SelectSingleNode("./msbuild:AdditionalIncludeDirectories", $nsManager)
    if (-not $additionalIncludeDirsNode) {
        $additionalIncludeDirsNode = $projXml.CreateElement("AdditionalIncludeDirectories", $nsManager.LookupNamespace("msbuild"))
        $clCompileNode.AppendChild($additionalIncludeDirsNode)
    }

    # Define all required include paths relative to the project root
    $includePaths = @(
        ".",
        ".\lib",
        ".\lib\jsoncpp\json",
        "external\pjproject\pjlib\include",
        "external\pjproject\pjlib-util\include",
        "external\pjproject\pjnath\include",
        "external\pjproject\pjmedia\include",
        "external\pjproject\pjsip\include",
        "external\pjproject\pjlib\include\pj\opus" # For Opus headers
    )
    # Join paths with semicolon. Removed %(AdditionalIncludeDirectories) for absolute control.
    $additionalIncludeDirsNode.'#text' = ($includePaths | Select-Object -Unique) -join ';'
    Write-Host "Set AdditionalIncludeDirectories in $ProjFile to: $($additionalIncludeDirsNode.'#text')"

    # --- Patching Library Paths and Dependencies ---
    $linkerNode = $itemDefinitionGroupNode.SelectSingleNode("./msbuild:Link", $nsManager)
    if (-not $linkerNode) {
        Write-Host "##[error]Error: Could not find Link node within Release|x64 ItemDefinitionGroup in $ProjFile."
        exit 1
    }

    # Ensure absolute paths for Library Directories
    # IMPORTANT: $(LibraryPath) must remain as an MSBuild macro, not a PowerShell variable.
    $additionalLibDirsNode = $linkerNode.SelectSingleNode("./msbuild:AdditionalLibraryDirectories", $nsManager)
    if (-not $additionalLibDirsNode) {
        $additionalLibDirsNode = $projXml.CreateElement("AdditionalLibraryDirectories", $nsManager.LookupNamespace("msbuild"))
        $linkerNode.AppendChild($additionalLibDirsNode)
    }
    # Explicitly set the library directories.
    # Note the change: $(LibraryPath) is now a literal string to be inserted, NOT interpolated by PowerShell.
    $additionalLibDirsNode.'#text' = "${PjsipLibRoot};${PjsipLibRoot}\third_party;`$(LibraryPath)" # Using backtick to escape $ for PowerShell
    Write-Host "Set AdditionalLibraryDirectories in $ProjFile to: $($additionalLibDirsNode.'#text')"

    # List all PJSIP libraries that are being compiled/renamed
    $pjsipLibs = @(
        "pjlib.lib",
        "pjlib-util.lib", # pjlib_util.vcxproj -> pjlib-util.lib
        "pjnath.lib",
        "pjmedia.lib",
        "pjmedia-audiodev.lib",
        "pjmedia-codec.lib",
        "pjmedia-videodev.lib",
        "pjsip-core.lib",
        "pjsip-simple.lib",
        "pjsip-ua.lib",
        "pjsua-lib.lib",
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
    # Replace content, ensuring unique libs
    # Removed: ';%(AdditionalDependencies)' for absolute control
    $additionalDependenciesNode.'#text' = ($pjsipLibs + $windowsCommonLibs | Select-Object -Unique) -join ';'
    Write-Host "Set AdditionalDependencies in $ProjFile to: $($additionalDependenciesNode.'#text')"

    # Remove any specific old PJSIP static library references if they exist as separate nodes
    # This specifically targets the "libpjproject-x86_64-x64-vc14-Release-Static.lib" issue.
    $oldPjsipLibNodes = $linkerNode.SelectNodes("child::*[normalize-space(.)='libpjproject-x86_64-x64-vc14-Release-Static.lib']", $nsManager)
    foreach ($oldNode in $oldPjsipLibNodes) {
        Write-Host "Removing old PJSIP static library reference: $($oldNode.'#text')"
        $oldNode.ParentNode.RemoveChild($oldNode)
    }

    $projXml.Save($ProjFile)
    Write-Host "Successfully patched $ProjFile."

} catch {
    Write-Host "##[error]Error patching $($ProjFile): $($_.Exception.Message)"
    exit 1
}