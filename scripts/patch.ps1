# This script patches the PJSIP project file to set comprehensive and correct include paths.
# Version 10 - Updated to use absolute paths for Opus and Speex includes after tracing the build issue.

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

        # Clear existing include paths before adding new ones, to prevent conflicts or incorrect ordering.
        $currentIncludes = "" 
        
        # Get the absolute path to the workspace root
        $workspaceRoot = $env:GITHUB_WORKSPACE

        # Define all necessary include paths using absolute paths.
        # This resolves the ambiguity of relative paths and ensures correctness.
        $pathsToAdd = @(
            (Join-Path -Path $workspaceRoot -ChildPath "pjproject/pjlib/include/pj"),         # For Opus (copied), and pj/config_site.h etc.
            (Join-Path -Path $workspaceRoot -ChildPath "pjproject/pjlib/include"),              # For general pj/*.h headers (e.g., pj/config.h, pj/pool.h)
            (Join-Path -Path $workspaceRoot -ChildPath "pjproject/pjmedia/include"),            # For general pjmedia/*.h headers (e.g., pjmedia/config.h, pjmedia/errno.h)
            (Join-Path -Path $workspaceRoot -ChildPath "pjproject/pjmedia/include/pjmedia-codec"), # For pjmedia-codec/*.h headers (e.g., amr_sdp_match.h, opus.h internal PJSIP)
            
            # Explicit path for Speex library using its absolute location:
            (Join-Path -Path $workspaceRoot -ChildPath "pjproject/third_party/speex/include")  # For speex/speex.h
            # The Opus headers are now found via the pjproject/pjlib/include/pj path
        )

        foreach ($path in $pathsToAdd) {
            # Add the new value, ensuring a semicolon separator if not the first path
            if ($currentIncludes -ne "") {
                $currentIncludes += ";"
            }
            $currentIncludes += $path
            Write-Host "Adding include path: $path"
        }
        
        # Preserve any existing AdditionalIncludeDirectories to avoid breaking other necessary includes.
        # This is typically represented by the $(AdditionalIncludeDirectories) macro in MSBuild.
        $includeDirsNode.InnerText = $currentIncludes + ";`$(AdditionalIncludeDirectories)"
        Write-Host "Final AdditionalIncludeDirectories set to: $($includeDirsNode.InnerText)"
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