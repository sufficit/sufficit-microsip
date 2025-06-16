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
    [xml]$projXml = Get-Content $ProjFile

    $nsManager = New-Object System.Xml.XmlNamespaceManager($projXml.NameTable)
    $nsManager.AddNamespace("msbuild", "http://schemas.microsoft.com/developer/msbuild/2003")

    $clCompileNode = $projXml.SelectSingleNode("//msbuild:ItemDefinitionGroup[contains(@Condition, 'Release') and contains(@Condition, 'x64')]/msbuild:ClCompile", $nsManager)

    if ($clCompileNode) {
        $preprocessorDefinitionsNode = $clCompileNode.SelectSingleNode("./msbuild:PreprocessorDefinitions", $nsManager)

        if ($preprocessorDefinitionsNode) {
            $existingDefinitions = $preprocessorDefinitionsNode.'#text'
            # Adicionar apenas se não existirem para evitar duplicatas e manter a ordem
            $definitionsToAdd = @("_M_X64", "_WIN64")
            $currentDefsArray = $existingDefinitions.Split(';') | Where-Object { $_ -ne "" }
            $newDefinitionsString = $existingDefinitions
            foreach ($def in $definitionsToAdd) {
                if ($currentDefsArray -notcontains $def) {
                    $newDefinitionsString = "$def;$newDefinitionsString" # Adiciona no início
                }
            }
            if ($newDefinitionsString -ne $existingDefinitions) {
                $preprocessorDefinitionsNode.'#text' = $newDefinitionsString
                Write-Host "Updated PreprocessorDefinitions for Release|x64 in $ProjFile."
                Write-Host "New definitions: $($preprocessorDefinitionsNode.'#text')"
            } else {
                Write-Host "PreprocessorDefinitions already contain necessary x64 definitions."
            }
        } else {
            $newDefNode = $projXml.CreateElement("PreprocessorDefinitions", $nsManager.LookupNamespace("msbuild"))
            $newDefNode.'#text' = "_M_X64;_WIN64"
            $clCompileNode.AppendChild($newDefNode)
            Write-Host "Added PreprocessorDefinitions for Release|x64 in $ProjFile."
        }

        # Patch AdditionalIncludeDirectories para Opus
        $additionalIncludeDirsNode = $clCompileNode.SelectSingleNode("./msbuild:AdditionalIncludeDirectories", $nsManager)
        $opusIncludePath = "../../pjlib/include/pj/opus" # Relativo ao pjmedia_codec.vcxproj

        if ($additionalIncludeDirsNode -and $additionalIncludeDirsNode.'#text' -notmatch [regex]::Escape($opusIncludePath)) {
            $additionalIncludeDirsNode.'#text' = "$($additionalIncludeDirsNode.'#text');$opusIncludePath"
            Write-Host "Updated AdditionalIncludeDirectories for Release|x64 in $ProjFile to include Opus: $($additionalIncludeDirsNode.'#text')"
        } elseif (-not $additionalIncludeDirsNode) {
            $newIncludeNode = $projXml.CreateElement("AdditionalIncludeDirectories", $nsManager.LookupNamespace("msbuild"))
            $newIncludeNode.'#text' = "$opusIncludePath;%(AdditionalIncludeDirectories)"
            $clCompileNode.AppendChild($newIncludeNode)
            Write-Host "Added AdditionalIncludeDirectories node with Opus path for Release|x64 in $ProjFile."
        } else {
            Write-Host "Opus include path '$opusIncludePath' already present in AdditionalIncludeDirectories or node not found as expected."
        }

        $projXml.Save($ProjFile)
        Write-Host "Successfully patched $ProjFile."
    } else {
        Write-Host "##[warning]Warning: Could not find Release|x64 configuration in $ProjFile. No patch applied."
    }

} catch {
    Write-Host "##[error]Error patching $($ProjFile): $($_.Exception.Message)"
    exit 1
}
