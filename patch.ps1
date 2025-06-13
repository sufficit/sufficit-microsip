# Este script corrige o arquivo de projeto da PJSIP que possui um caminho de inclusão quebrado para o Opus.

$projFile = "./pjmedia/build/pjmedia-codec.vcxproj"
Write-Host "Loading project file to patch: $projFile"

# Carrega o conteúdo do arquivo XML
$xml = [xml](Get-Content $projFile)

# Define a string exata da condição que queremos encontrar.
$targetCondition = "'$(Configuration)|$(Platform)'=='Release|Win32'"
$patched = $false

# Itera por todos os grupos de definição de item no projeto
foreach ($group in $xml.Project.ItemDefinitionGroup) {
    # Se a condição do grupo for exatamente a que procuramos
    if ($group.Condition -eq $targetCondition) {
        Write-Host "Found 'Release|Win32' configuration. Patching..."

        $includeDirsNode = $group.ClCompile.AdditionalIncludeDirectories
        $currentIncludes = $includeDirsNode.'#text'
        $newIncludePath = ";../../third_party/opus/include"

        if ($currentIncludes -notlike "*$newIncludePath*") {
            $includeDirsNode.'#text' = $currentIncludes + $newIncludePath
            Write-Host "Successfully patched include path."
        } else {
            Write-Host "Include path already exists. No patch needed."
        }

        $patched = $true
        break
    }
}

if (-not $patched) {
    Write-Host "FATAL: Could not find 'Release|Win32' configuration in $projFile to patch."
    exit 1
}

$xml.Save($projFile)
Write-Host "Saved updated project file: $projFile"
exit 0