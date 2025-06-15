# This script patches the PJSIP project file to add the correct Opus include path and other essential PJSIP include paths.
# Version 6 - Added multiple essential PJSIP internal include paths to pjmedia_codec.vcxproj.

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$ProjFile
)

Write-Host "Loading project file to patch: $ProjFile"

# Load the XML content of the project file
$xml = [xml](Get-Content $ProjFile)

# Define the exact condition string we are looking for.
# Escaped '$' before (Configuration) and (Platform) so PowerShell treats them as literal characters.
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

        # Define all necessary include paths. These are relative to pjmedia/build/
        # - ../../pjlib/include/pj: Where config_site.h and Opus headers (under 'opus/') are copied
        # - ../include: The current project's (pjmedia_codec) own include folder
        # - ../../pjmedia/include: General pjmedia headers
        # - ../../pjlib/include: General pjlib headers
        $pathsToAdd = @(
            "../../../pjlib/include/pj", # For Opus, and general pjlib/include/pj specific headers like config_site.h
            "../include",                 # For pjmedia_codec's own headers (e.g., pjmedia-codec.h, amr_sdp_match.h etc.)
            "../../pjmedia/include",      # For general pjmedia headers (e.g., pjmedia/errno.h)
            "../../pjlib/include"         # For general pjlib headers
        )

        foreach ($path in $pathsToAdd) {
            # Check if the current path has already been added to avoid duplicates
            if ($currentIncludes -notlike "*$path*") {
                # Add the new value
                $currentIncludes = ($currentIncludes + ";" + $path)
                Write-Host "Successfully added include path: $path"
            } else {
                Write-Host "Include path already exists. No patch needed for: $path"
            }
        }
        
        $includeDirsNode.InnerText = $currentIncludes
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
