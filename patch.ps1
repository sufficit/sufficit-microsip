# Este script corrige o arquivo de projeto da PJSIP que possui um caminho de inclusão quebrado para o Opus.

$projFile = "./pjmedia/build/pjmedia-codec.vcxproj"
Write-Host "Loading project file to patch: $projFile"

# Carrega o conteúdo do arquivo XML
$xml = [xml](Get-Content $projFile)

# Define a string exata da condição que queremos encontrar.
# O acento grave (`) antes de cada $ é o FIX CRÍTICO para tratar o texto literalmente.
$targetCondition = "'`$(Configuration)`|`$(Platform)'=='Release|Win32'"

$patched = $false

# Itera por todos os grupos de definição de item no projeto
foreach ($group in $xml.Project.ItemDefinitionGroup) {
    # Se a condição do grupo for exatamente a que procuramos
    if ($group.Condition -eq $targetCondition) {
        Write-Host "Found 'Release|Win32' configuration. Patching..."
        
        # Navega até o nó dos diretórios de inclusão
        $includeDirsNode = $group.ClCompile.AdditionalIncludeDirectories
        
        # Pega o valor atual
        $currentIncludes = $includeDirsNode.'#text'
        
        # Adiciona o caminho que falta para os headers do Opus
        $newIncludePath = ";../../opus-source/include"
        
        # Verifica se o patch já não foi aplicado para evitar duplicatas
        if ($currentIncludes -notlike "*$newIncludePath*") {
            $includeDirsNode.'#text' = $currentIncludes + $newIncludePath
            Write-Host "Successfully patched include path."
        } else {
            Write-Host "Include path already exists. No patch needed."
        }
        
        $patched = $true
        break # Sai do loop pois já encontramos e corrigimos o que precisávamos
    }
}

# Se, após o loop, não tivermos encontrado a seção, o script falha.
if (-not $patched) {
    Write-Host "FATAL: Could not find 'Release|Win32' configuration in $projFile to patch."
    exit 1
}

# Salva o arquivo .vcxproj modificado
$xml.Save($projFile)
Write-Host "Saved updated project file: $projFile"

# Sai com sucesso
exit 0