# This script patches the PJSIP project file to add the correct Opus include path and other essential PJSIP include paths.
# Version 7 - Added specific 'pjmedia-codec' include path and ensured all essential PJSIP internal includes.

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
        # They cover general PJSIP modules and the specific 'pjmedia-codec' and 'pj' subdirectories.
        $pathsToAdd = @(
            "../../../pjlib/include/pj",         # For Opus (copied), and pj/config_site.h etc.
            "../../pjlib/include",              # For general pj/*.h headers (e.g., pj/config.h, pj/pool.h)
            "../include",                       # For general pjmedia/*.h headers (e.g., pjmedia/config.h, pjmedia/errno.h)
            "../include/pjmedia-codec"          # For pjmedia-codec/*.h headers (e.g., amr_sdp_match.h, opus.h)
            # Add other necessary PJSIP module includes if they become issues
            # "../../pjlib-util/include",
            # "../../pjnath/include",
            # "../../pjsip/include"
        )

        foreach ($path in $pathsToAdd) {
            # Check if the current path has already been added to avoid duplicates
            if ($currentIncludes -notlike "*$path*") {
                # Add the new value, ensuring a semicolon separator
                if ($currentIncludes -ne "") {
                    $currentIncludes += ";"
                }
                $currentIncludes += $path
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
