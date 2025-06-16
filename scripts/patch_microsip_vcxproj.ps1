# =================================================================================================
# PATCH SCRIPT FOR MicroSIP PROJECT FILE (CALLED BY GITHUB ACTIONS WORKFLOW)
#
# This script adds PJSIP and MicroSIP's internal include and library paths to microsip.vcxproj.
#
# Changes:
#   - Now explicitly includes MicroSIP's root directory ($(ProjectDir)) and its 'lib' subdirectory
#     ($(ProjectDir)lib) for internal headers.
#   - Includes ($(ProjectDir)lib\jsoncpp) for the json.h header.
#   - Ensures all PJSIP include paths are correctly prefixed with $(ProjectDir)lib\pjproject\.
#   - The PjsipAppsIncludePath parameter is now used to ensure pjsua.h (and other pjsip/include)
#     headers are found correctly by including the pjsip/include path.
# =================================================================================================
param (
    [Parameter(Mandatory=$true)]
    [string]$ProjFile,
    [Parameter(Mandatory=$true)]
    [string]$PjsipIncludeRoot, # e.g., 'lib/pjproject'
    [Parameter(Mandatory=$true)]
    [string]$PjsipLibRoot, # e.g., 'lib/pjproject'
    [Parameter(Mandatory=$true)] # Este parâmetro agora aponta para 'lib/pjproject/pjsip/include'
    [string]$PjsipAppsIncludePath # e.g., 'lib/pjproject/pjsip/include' (onde pjsua.h pode estar)
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
        # Add ALL necessary include directories:
        # 1. MicroSIP's own directories
        # 2. Third-party libraries specifically for MicroSIP (e.g., jsoncpp)
        # 3. All PJSIP core include directories
        $requiredIncludes = @(
            "$(ProjectDir)" # For root headers like stdafx.h, global.h, mainDlg.h
            "$(ProjectDir)lib" # For headers in MicroSIP's lib folder like MSIP.h, CListCtrl_ToolTip.h, etc.
            "$(ProjectDir)lib\jsoncpp" # For json.h
            Join-Path -Path "$(ProjectDir)$PjsipIncludeRoot" -ChildPath "pjlib/include"    # For pj/types.h, etc.
            Join-Path -Path "$(ProjectDir)$PjsipIncludeRoot" -ChildPath "pjlib-util/include"
            Join-Path -Path "$(ProjectDir)$PjsipIncludeRoot" -ChildPath "pjnath/include"
            Join-Path -Path "$(ProjectDir)$PjsipIncludeRoot" -ChildPath "pjmedia/include"
            Join-Path -Path "$(ProjectDir)$PjsipIncludeRoot" -ChildPath "pjsip/include" # Contains pjsua-lib folder and pjsua.h within it
            # The $PjsipAppsIncludePath is now covered by "$(ProjectDir)$PjsipIncludeRoot\pjsip\include"
            # as PjsipAppsIncludePath is expected to be "lib/pjproject/pjsip/include" which is derived from $PjsipIncludeRoot
        )

        $additionalIncludeDirsNode = $clCompileNode.SelectSingleNode("./msbuild:AdditionalIncludeDirectories", $nsManager)

        # Concatenate and filter out duplicates
        $currentIncludes = if ($additionalIncludeDirsNode) { $additionalIncludeDirsNode.'#text' } else { "" }
        $newIncludesArray = $currentIncludes.Split(';') | Where-Object { $_ -ne "" } | ForEach-Object { $_.Trim() }

        foreach ($includePath in $requiredIncludes) {
            # Add only if not already present
            if ($newIncludesArray -notcontains $includePath) {
                $newIncludesArray += $includePath
            }
        }
        $newIncludesString = ($newIncludesArray | Select-Object -Unique) -join ';' # Ensure unique and rejoin

        if ($additionalIncludeDirsNode) {
            # Check if actual change is needed to avoid unnecessary file writes
            if ($newIncludesString -ne $currentIncludes) {
                $additionalIncludeDirsNode.'#text' = "$newIncludesString;%(AdditionalIncludeDirectories)"
                Write-Host "Updated AdditionalIncludeDirectories in $ProjFile to include all necessary paths."
            } else {
                Write-Host "All necessary include paths already present in AdditionalIncludeDirectories."
            }
        } else {
            $newIncludeNode = $projXml.CreateElement("AdditionalIncludeDirectories", $nsManager.LookupNamespace("msbuild"))
            $newIncludeNode.'#text' = "$newIncludesString;%(AdditionalIncludeDirectories)"
            $clCompileNode.AppendChild($newIncludeNode)
            Write-Host "Added AdditionalIncludeDirectories node with all necessary paths in $ProjFile."
        }
    } else {
        Write-Host "##[warning]Warning: Could not find ClCompile node for Release|x64 in $ProjFile. Skipping include path update."
    }

    if ($linkerNode) {
        # Add PJSIP library directories
        $additionalLibraryDirsNode = $linkerNode.SelectSingleNode("./msbuild:AdditionalLibraryDirectories", $nsManager)
        $pjsipLibPathFull = "$(ProjectDir)$PjsipLibRoot" # Full path to the libs folder

        if ($additionalLibraryDirsNode) {
            $currentLibDirs = $additionalLibraryDirsNode.'#text'
            if ($currentLibDirs -notmatch [regex]::Escape($pjsipLibPathFull)) {
                $additionalLibraryDirsNode.'#text' = "$pjsipLibPathFull;$currentLibDirs"
                Write-Host "Updated AdditionalLibraryDirectories in $ProjFile to include PJSIP lib path."
            } else {
                Write-Host "PJSIP library path already present in AdditionalLibraryDirectories."
            }
        } else {
            $newLibNode = $projXml.CreateElement("AdditionalLibraryDirectories", $nsManager.LookupNamespace("msbuild"))
            $newLibNode.'#text' = "$pjsipLibPathFull;%(AdditionalLibraryDirectories)"
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
