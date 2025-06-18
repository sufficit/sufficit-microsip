# =================================================================================================
# PATCH SCRIPT FOR MicroSIP PROJECT FILE (CALLED BY GITHUB ACTIONS WORKFLOW)
#
# Author: Hugo Castro de Deco, Sufficit, and Gemini AI for Google
# Date: June 18, 2025 - 01:50:00 AM -03
# Version: 1.0.77
#
# This script configures MicroSIP's vcxproj to link with PJSIP libraries.
#
# Changes:
#   - Aggressively removes any textual occurrences of the old problematic PJSIP static library name.
#   - Explicitly sets include directories to point to compiled PJSIP headers.
#   - Ensures correct preprocessor definitions, including PJMEDIA_AUD_MAX_DEVS.
#   - Sets absolute library directories for PJSIP and common Windows libraries.
#   - Explicitly defines all required PJSIP libraries in AdditionalDependencies.
#   - NEW: Adds `/NODEFAULTLIB:libpjproject-x86_64-x64-vc14-Release-Static.lib` to
#     Linker->AdditionalOptions to explicitly tell the linker to ignore any implicit
#     or inherited references to this problematic old library, as it appears to be
#     coming from an unknown implicit source.
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
    # AGGRESSIVE PRE-PROCESSING: Remove problematic library name as plain text first
    # This addresses cases where the string might be in unexpected XML attributes or parts
    # not easily targeted by XPath or InnerText.
    $oldProblematicLibName = "libpjproject-x86_64-x64-vc14-Release-Static.lib"
    Write-Host "Attempting aggressive text replacement for '$oldProblematicLibName' in $ProjFile..."
    $fileContent = Get-Content $ProjFile -Raw -Encoding UTF8 # Ensure reading as UTF8
    if ($fileContent -like "*$oldProblematicLibName*") {
        $fileContent = $fileContent.Replace($oldProblematicLibName, "")
        $fileContent = $fileContent.Replace(";;", ";").Trim(';') # Clean up double semicolons
        Set-Content $ProjFile -Value $fileContent -Encoding UTF8 # Ensure writing back as UTF8
        Write-Host "Aggressive text replacement successful for '$oldProblematicLibName'."
    } else {
        Write-Host "Aggressive text replacement: '$oldProblematicLibName' not found (expected, means it's coming from an implicit source)."
    }

    # Now, proceed with XML parsing and structured updates
    # Must re-read content as it might have changed from text replacement
    [xml]$projXml = Get-Content $ProjFile -Encoding UTF8

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
        ".", # For headers in the MicroSIP project root (where microsip.vcxproj is)
        ".\lib", # For headers in MicroSIP's lib folder
        ".\lib\jsoncpp\json", # Corrected path for json.h
        "external\pjproject\pjlib\include",
        "external\pjproject\pjlib-util\include",
        "external\pjproject\pjnath\include",
        "external\pjproject\pjmedia\include",
        "external\pjproject\pjsip\include",
        # Use the variable directly as it points to the correct location
        "external\pjproject\pjlib\include\pj\opus" 
        # Removed: '%(AdditionalIncludeDirectories)' for absolute control
    )

    $additionalIncludeDirsNode.'#text' = ($includePaths | Select-Object -Unique) -join ';'
    Write-Host "Set AdditionalIncludeDirectories in $ProjFile to: $($additionalIncludeDirsNode.'#text')"

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
    $additionalDependenciesNode.InnerText = ($pjsipLibs + $windowsCommonLibs | Select-Object -Unique) -join ';'
    Write-Host "Set AdditionalDependencies in $ProjFile to: $($additionalDependenciesNode.InnerText)"

    # NEW: Add /NODEFAULTLIB option for the problematic library if it's still being linked implicitly
    $additionalOptionsNode = $linkerNode.SelectSingleNode("./msbuild:AdditionalOptions", $nsManager)
    if (-not $additionalOptionsNode) {
        $additionalOptionsNode = $projXml.CreateElement("AdditionalOptions", $nsManager.LookupNamespace("msbuild"))
        $linkerNode.AppendChild($additionalOptionsNode)
    }

    $noDefaultLibOption = "/NODEFAULTLIB:$oldProblematicLibName"
    if ($additionalOptionsNode.InnerText -notlike "*$noDefaultLibOption*") {
        # Prepend the new option to ensure it takes precedence or is simply added.
        # Clean up any potential leading/trailing spaces or duplicate semicolons after adding.
        $additionalOptionsNode.InnerText = "$noDefaultLibOption $($additionalOptionsNode.InnerText)".Trim().Replace(";;", ";").Trim(';')
        Write-Host "Added '$noDefaultLibOption' to AdditionalOptions in $ProjFile."
    } else {
        Write-Host "'$noDefaultLibOption' already present in AdditionalOptions (expected)."
    }

    $projXml.Save($ProjFile)
    Write-Host "Successfully patched $ProjFile."

} catch {
    Write-Host "##[error]Error patching $($ProjFile): $($_.Exception.Message)"
    exit 1
}