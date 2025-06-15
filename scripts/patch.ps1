# This script patches the PJSIP project file to add the correct Opus include path.
# Version 5 - Fixed PowerShell parsing of MSBuild variables in target condition.

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$ProjFile
)

Write-Host "Loading project file to patch: $ProjFile"

# Load the XML content of the project file
$xml = [xml](Get-Content $ProjFile)

# Define the exact condition string we are looking for.
# Corrected: Escaped '$' before (Configuration) and (Platform) so PowerShell treats them as literal characters.
$targetCondition = "'`$(Configuration)`|`$(Platform)'=='Release|Win32'"

$patched = $false

# Iterate through all item definition groups in the project
foreach ($group in $xml.Project.ItemDefinitionGroup) {
    # If the group's condition matches what we are looking for
    if ($group.Condition -eq $targetCondition) {
        Write-Host "Found 'Release|Win32' configuration. Patching..."

        # Ensure the <ClCompile> node exists.
        $clCompileNode = $group.SelectSingleNode("ClCompile")
        if ($null -eq $clCompileNode) {
            Write-Host "ClCompile node not found. Creating it."
            # Use the parent element's namespace to create the new node
            $clCompileNode = $xml.CreateElement("ClCompile", $group.NamespaceURI)
            $group.AppendChild($clCompileNode) | Out-Null
        }

        # Ensure the <AdditionalIncludeDirectories> node exists within <ClCompile>.
        $includeDirsNode = $clCompileNode.SelectSingleNode("AdditionalIncludeDirectories")
        if ($null -eq $includeDirsNode) {
            Write-Host "Creating missing 'AdditionalIncludeDirectories' node."
            $includeDirsNode = $xml.CreateElement("AdditionalIncludeDirectories", $clCompileNode.NamespaceURI)
            $clCompileNode.AppendChild($includeDirsNode) | Out-Null
        }

        # Now that we are sure the node exists, we can safely modify it.
        $currentIncludes = $includeDirsNode.InnerText
        # This is the new relative path from pjmedia/build/pjmedia_codec.vcxproj to pjproject/pjlib/include/pj/
        # where the 'opus' subdirectory now resides.
        $newIncludePath = ";../../../pjlib/include/pj"

        # Check if the patch has already been applied to avoid duplicates
        if ($currentIncludes -notlike "*$newIncludePath*") {
            # Add the new value
            $includeDirsNode.InnerText = ($currentIncludes + $newIncludePath)
            Write-Host "Successfully patched include path: $newIncludePath"
        } else {
            Write-Host "Include path already exists. No patch needed."
        }
        
        $patched = $true
        break # Exit the loop
    }
}

if (-not $patched) {
    Write-Host "##[error]FATAL: Could not find 'Release|Win32' configuration in $ProjFile to patch."
    exit 1
}

# Save the modified .vcxproj file
$xml.Save($ProjFile)
Write-Host "Saved updated project file: $ProjFile"

exit 0
