# =================================================================================================
# PATCH SCRIPT FOR PJSIP PROJECT FILES (CALLED BY GITHUB ACTIONS WORKFLOW)
#
# Author: Hugo Castro de Deco, Sufficit
# Collaboration: Gemini AI for Google
# Date: June 15, 2025
# Version: 6 (Corrected SelectSingleNode with XmlNamespaceManager)
#
# This script is intended to apply specific patches to PJSIP project files,
# such as adjusting include paths or build settings.
# =================================================================================================

param (
    [Parameter(Mandatory=$true)]
    [string]$ProjFile
)

Write-Host "Executing patch script for: $ProjFile"

try {
    # Load the XML content of the .vcxproj file
    [xml]$projXml = Get-Content $ProjFile

    # Create an XmlNamespaceManager and add the MSBuild namespace
    $nsManager = New-Object System.Xml.XmlNamespaceManager($projXml.NameTable)
    $nsManager.AddNamespace("msbuild", "http://schemas.microsoft.com/developer/msbuild/2003")

    # Select the ClCompile node for Release|x64 configuration using the namespace manager
    $clCompileNode = $projXml.SelectSingleNode("//msbuild:ItemDefinitionGroup[contains(@Condition, 'Release') and contains(@Condition, 'x64')]/msbuild:ClCompile", $nsManager)

    if ($clCompileNode) {
        # Find or create PreprocessorDefinitions node
        $preprocessorDefinitionsNode = $clCompileNode.SelectSingleNode("./msbuild:PreprocessorDefinitions", $nsManager)

        if ($preprocessorDefinitionsNode) {
            # Prepend _M_X64 and _WIN64 to existing definitions
            $existingDefinitions = $preprocessorDefinitionsNode.'#text'
            $newDefinitions = "_M_X64;_WIN64;$existingDefinitions" # Prepend them
            $preprocessorDefinitionsNode.'#text' = $newDefinitions
            Write-Host "Updated PreprocessorDefinitions for Release|x64 in $ProjFile."
            Write-Host "New definitions: $($preprocessorDefinitionsNode.'#text')"
        } else {
            # If PreprocessorDefinitions node doesn't exist, create it
            $newDefNode = $projXml.CreateElement("PreprocessorDefinitions", $nsManager.LookupNamespace("msbuild"))
            $newDefNode.'#text' = "_M_X64;_WIN64"
            $clCompileNode.AppendChild($newDefNode)
            Write-Host "Added PreprocessorDefinitions for Release|x64 in $ProjFile."
        }

        # Save the modified XML back to the file
        $projXml.Save($ProjFile)
        Write-Host "Successfully patched $ProjFile."
    } else {
        Write-Host "##[warning]Warning: Could not find Release|x64 configuration in $ProjFile. No patch applied."
    }

} catch {
    # Corrected variable interpolation in the error message for robustness
    Write-Host "##[error]Error patching $($ProjFile): $($_.Exception.Message)"
    exit 1
}