# =================================================================================================
# PATCH SCRIPT FOR MicroSIP PROJECT FILE (CALLED BY GITHUB ACTIONS WORKFLOW)
#
# This script adds PJSIP include and library paths to microsip.vcxproj.
# =================================================================================================
param (
    [Parameter(Mandatory=$true)]
    [string]$ProjFile,
    [Parameter(Mandatory=$true)]
    [string]$PjsipIncludeRoot, # e.g., 'lib/pjproject'
    [Parameter(Mandatory=$true)]
    [string]$PjsipLibRoot # e.g., 'lib/pjproject'
)

Write-Host "Executing patch script for MicroSIP: $ProjFile"

try {
    [xml]$projXml = Get-Content $ProjFile

    $nsManager = New-Object System.Xml.XmlNamespaceManager($projXml.NameTable)
    $nsManager.AddNamespace("msbuild", "http://schemas.microsoft.com/developer/msbuild/2003")

    # Target the main project's ClCompile and Linker configurations
    # We target Release|x64 specifically for includes and libraries
    $clCompileNode = $projXml.SelectSingleNode("//msbuild:ItemDefinitionGroup[contains(@Condition, 'Release') and contains(@Condition, 'x64')]/msbuild:ClCompile", $nsManager)
    $linkerNode = $projXml.SelectSingleNode("//msbuild:ItemDefinitionGroup[contains(@Condition, 'Release') and contains(@Condition, 'x64')]/msbuild:Link", $nsManager)

    if ($clCompileNode) {
        # Add PJSIP include directories
        $additionalIncludeDirsNode = $clCompileNode.SelectSingleNode("./msbuild:AdditionalIncludeDirectories", $nsManager)
        $pjsipIncludes = @(
            Join-Path -Path $PjsipIncludeRoot -ChildPath "pjlib/include"
            Join-Path -Path $PjsipIncludeRoot -ChildPath "pjlib-util/include"
            Join-Path -Path $PjsipIncludeRoot -ChildPath "pjnath/include"
            Join-Path -Path $PjsipIncludeRoot -ChildPath "pjmedia/include"
            Join-Path -Path $PjsipIncludeRoot -ChildPath "pjsip/include"
            Join-Path -Path $PjsipIncludeRoot -ChildPath "pjsip-apps/include" # This contains pjsua-lib
        )
        $pjsipIncludeString = $pjsipIncludes | ForEach-Object { "$_;" }
        $pjsipIncludeString = $pjsipIncludeString -join ''

        if ($additionalIncludeDirsNode) {
            $currentIncludes = $additionalIncludeDirsNode.'#text'
            # Only add if not already present
            $newIncludes = $currentIncludes
            foreach ($includePath in $pjsipIncludes) {
                if ($currentIncludes -notmatch [regex]::Escape($includePath)) {
                    $newIncludes = "$includePath;$newIncludes"
                }
            }
            if ($newIncludes -ne $currentIncludes) {
                $additionalIncludeDirsNode.'#text' = "$newIncludes;%(AdditionalIncludeDirectories)"
                Write-Host "Updated AdditionalIncludeDirectories in $ProjFile to include PJSIP."
            } else {
                Write-Host "PJSIP include paths already present in AdditionalIncludeDirectories."
            }
        } else {
            $newIncludeNode = $projXml.CreateElement("AdditionalIncludeDirectories", $nsManager.LookupNamespace("msbuild"))
            $newIncludeNode.'#text' = "$pjsipIncludeString;%(AdditionalIncludeDirectories)"
            $clCompileNode.AppendChild($newIncludeNode)
            Write-Host "Added AdditionalIncludeDirectories node with PJSIP paths in $ProjFile."
        }
    } else {
        Write-Host "##[warning]Warning: Could not find ClCompile node for Release|x64 in $ProjFile. Skipping include path update."
    }

    if ($linkerNode) {
        # Add PJSIP library directories
        $additionalLibraryDirsNode = $linkerNode.SelectSingleNode("./msbuild:AdditionalLibraryDirectories", $nsManager)
        $pjsipLibPath = $PjsipLibRoot # This should be the 'lib' folder where .lib files are

        if ($additionalLibraryDirsNode) {
            $currentLibDirs = $additionalLibraryDirsNode.'#text'
            if ($currentLibDirs -notmatch [regex]::Escape($pjsipLibPath)) {
                $additionalLibraryDirsNode.'#text' = "$pjsipLibPath;$currentLibDirs"
                Write-Host "Updated AdditionalLibraryDirectories in $ProjFile to include PJSIP lib path."
            } else {
                Write-Host "PJSIP library path already present in AdditionalLibraryDirectories."
            }
        } else {
            $newLibNode = $projXml.CreateElement("AdditionalLibraryDirectories", $nsManager.LookupNamespace("msbuild"))
            $newLibNode.'#text' = "$pjsipLibPath;%(AdditionalLibraryDirectories)"
            $linkerNode.AppendChild($newLibNode)
            Write-Host "Added AdditionalLibraryDirectories node with PJSIP lib path in $ProjFile."
        }

        # Add PJSIP additional dependencies (libraries)
        $additionalDependenciesNode = $linkerNode.SelectSingleNode("./msbuild:AdditionalDependencies", $nsManager)
        $pjsipLibs = @(
            "pjlib-test.lib"
            "pjlib-util-test.lib"
            "pjnath-test.lib"
            "pjmedia-test.lib"
            "pjsip-test.lib"
            "pjsip-ua-test.lib"
            "pjsip-simple-test.lib"
            "pjsua-lib.lib" # Crucial for pjsua.h
            "libopus.lib" # From our opus download
            # Common Windows libs that PJSIP might need for linking
            "ws2_32.lib"
            "advapi32.lib"
            "iphlpapi.lib"
            "mswsock.lib"
            "ole32.lib"
            "winmm.lib"
            "user32.lib"
            "gdi32.lib"
            "crypt32.lib"
            "dnsapi.lib"
            # Add any other specific PJSIP libraries your MicroSIP build needs
        )
        $pjsipLibsString = $pjsipLibs | ForEach-Object { "$_;" }
        $pjsipLibsString = $pjsipLibsString -join ''

        if ($additionalDependenciesNode) {
            $currentDependencies = $additionalDependenciesNode.'#text'
            $newDependencies = $currentDependencies
            foreach ($lib in $pjsipLibs) {
                if ($currentDependencies -notmatch [regex]::Escape($lib)) {
                    $newDependencies = "$lib;$newDependencies"
                }
            }
            if ($newDependencies -ne $currentDependencies) {
                $additionalDependenciesNode.'#text' = "$newDependencies;%(AdditionalDependencies)"
                Write-Host "Updated AdditionalDependencies in $ProjFile to include PJSIP libraries."
            } else {
                Write-Host "PJSIP libraries already present in AdditionalDependencies."
            }
        } else {
            $newDepNode = $projXml.CreateElement("AdditionalDependencies", $nsManager.LookupNamespace("msbuild"))
            $newDepNode.'#text' = "$pjsipLibsString;%(AdditionalDependencies)"
            $linkerNode.AppendChild($newDepNode)
            Write-Host "Added AdditionalDependencies node with PJSIP libraries in $ProjFile."
        }
    } else {
        Write-Host "##[warning]Warning: Could not find Linker node for Release|x64 in $ProjFile. Skipping library path and dependencies update."
    }

    $projXml.Save($ProjFile)
    Write-Host "Successfully patched $ProjFile."
} catch {
    Write-Host "##[error]Error patching $($ProjFile): $($_.Exception.Message)"
    exit 1
}
