# =================================================================================================
# PATCH SCRIPT FOR MicroSIP PROJECT FILE (CALLED BY GITHUB ACTIONS WORKFLOW)
#
# Author: Hugo Castro de Deco, Sufficit
# Collaboration: Gemini AI for Google
# Date: June 18, 2025 - 01:45:00 AM -03
# Version: 1.0.76
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
#   - ADDED: Version and timestamp to script header for traceability.
#   - FIXED: Corrected the handling of `$(LibraryPath)` in AdditionalLibraryDirectories to ensure
#     it's passed as an MSBuild macro, not a PowerShell variable. This was the root cause of
#     "The term 'LibraryPath' is not recognized" error.
#   - FIXED: Added 'PJMEDIA_AUD_MAX_DEVS=4' to PreprocessorDefinitions in microsip.vcxproj to resolve
#     'undeclared identifier' errors.
#   - FIXED: Enhanced handling of `AdditionalDependencies` to explicitly remove existing nodes
#     before adding the new set, preventing leftover old library references.
#   - NEW: Implemented an aggressive string replacement for the problematic library name
#     (`libpjproject-x86_64-x64-vc14-Release-Static.lib`) across the entire `.vcxproj` file
#     as plain text, as a preliminary step before XML parsing. This is a "force brute"
#     approach to ensure it's removed wherever it might appear, even in unexpected places.
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
    # AGGRESSIVE PRE-PROCESSING: Remove problematic library name as plain text first
    # This addresses cases where the string might be in unexpected XML attributes or parts
    # not easily targeted by XPath or InnerText.
    $oldProblematicLibName = "libpjproject-x86_64-x64-vc14-Release-Static.lib"
    Write-Host "Attempting aggressive text replacement for '$oldProblematicLibName' in $ProjFile..."
    $fileContent = Get-Content $ProjFile -Raw
    if ($fileContent -like "*$oldProblematicLibName*") {
        $fileContent = $fileContent.Replace($oldProblematicLibName, "")
        $fileContent = $fileContent.Replace(";;", ";").Trim(';') # Clean up double semicolons
        Set-Content $ProjFile -Value $fileContent -Encoding UTF8 # Ensure UTF8 encoding
        Write-Host "Aggressive text replacement successful for '$oldProblematicLibName'."
    } else {
        Write-Host "Aggressive text replacement: '$oldProblematicLibName' not found (expected)."
    }

    # Now, proceed with XML parsing and structured updates
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
    $additionalIncludeDirsNode.InnerText = ($includePaths | Select-Object -Unique) -join ';'
    Write-Host "Set AdditionalIncludeDirectories in $ProjFile to: $($additionalIncludeDirsNode.InnerText)"

    # --- Patching Preprocessor Definitions ---
    $preprocessorDefinitionsNode = $clCompileNode.SelectSingleNode("./msbuild:PreprocessorDefinitions", $nsManager)
    if (-not $preprocessorDefinitionsNode) {
        $preprocessorDefinitionsNode = $projXml.CreateElement("PreprocessorDefinitions", $nsManager.LookupNamespace("msbuild"))
        $clCompileNode.AppendChild($preprocessorDefinitionsNode)
    }

    # Ensure PJMEDIA_AUD_MAX_DEVS is defined, along with other common definitions
    $currentDefinitions = $preprocessorDefinitionsNode.InnerText
    # Splitting and filtering out potential duplicates of common definitions added by VS or other means
    $existingList = $currentDefinitions.Split(';') | Where-Object { $_ -ne "" } | ForEach-Object { $_.Trim() }

    $requiredDefinitions = @(
        "WIN32",
        "_WINDOWS",
        "NDEBUG",
        "_UNICODE",
        "UNICODE",
        "PJMEDIA_AUD_MAX_DEVS=4" # Explicitly define this macro
    )

    # Combine existing unique definitions with required ones, and remove any duplicates
    $updatedDefinitions = ($existingList + $requiredDefinitions) | Select-Object -Unique
    $preprocessorDefinitionsNode.InnerText = ($updatedDefinitions | Where-Object { $_ -ne "" }) -join ';'
    Write-Host "Set PreprocessorDefinitions in $ProjFile to: $($preprocessorDefinitionsNode.InnerText)"


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
    $additionalLibDirsNode.InnerText = "${PjsipLibRoot};${PjsipLibRoot}\third_party;`$(LibraryPath)" # Using backtick to escape $ for PowerShell
    Write-Host "Set AdditionalLibraryDirectories in $ProjFile to: $($additionalLibDirsNode.InnerText)"

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
    
    # Get the existing AdditionalDependencies node. If it doesn't exist, create it.
    $additionalDependenciesNode = $linkerNode.SelectSingleNode("./msbuild:AdditionalDependencies", $nsManager)
    if (-not $additionalDependenciesNode) {
        $additionalDependenciesNode = $projXml.CreateElement("AdditionalDependencies", $nsManager.LookupNamespace("msbuild"))
        $linkerNode.AppendChild($additionalDependenciesNode)
    }

    # Set the content. This will *overwrite* any existing content in InnerText.
    $additionalDependenciesNode.InnerText = ($pjsipLibs + $windowsCommonLibs | Select-Object -Unique) -join ';'
    Write-Host "Set AdditionalDependencies in $ProjFile to: $($additionalDependenciesNode.InnerText)"

    # The previous explicit removal of "libpjproject-x86_64-x64-vc14-Release-Static.lib" is now largely redundant
    # because we are overwriting the entire InnerText content. Keeping it commented for reference.
    # $oldPjsipLibNodes = $linkerNode.SelectNodes("child::*[normalize-space(.)='libpjproject-x86_64-x64-vc14-Release-Static.lib']", $nsManager)
    # foreach ($oldNode in $oldPjsipLibNodes) {
    #     Write-Host "Removing old PJSIP static library reference (now redundant): $($oldNode.'#text')"
    #     $oldNode.ParentNode.RemoveChild($oldNode)
    # }

    $projXml.Save($ProjFile)
    Write-Host "Successfully patched $ProjFile."

} catch {
    Write-Host "##[error]Error patching $($ProjFile): $($_.Exception.Message)"
    exit 1
}