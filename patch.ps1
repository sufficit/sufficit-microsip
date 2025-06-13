# Este script corrige o arquivo de projeto da PJSIP que possui um caminho de inclusão quebrado para o Opus.
# Versão 3 - Versão mais robusta usando SelectSingleNode para garantir a existência dos elementos XML.

$projFile = "./pjmedia/build/pjmedia_codec.vcxproj"
Write-Host "Loading project file to patch: $projFile"

# Carrega o conteúdo do arquivo XML
$xml = [xml](Get-Content $projFile)

# Define a string exata da condição que queremos encontrar.
$targetCondition = "'`$(Configuration)`|`$(Platform)'=='Release|Win32'"

$patched = $false

# Itera por todos os grupos de definição de item no projeto
foreach ($group in $xml.Project.ItemDefinitionGroup) {
    # Se a condição do grupo for exatamente a que procuramos
    if ($group.Condition -eq $targetCondition) {
        Write-Host "Found 'Release|Win32' configuration. Patching..."
        
        # --- INÍCIO DA CORREÇÃO ROBUSTA ---
        # Garante que o nó <ClCompile> exista.
        $clCompileNode = $group.SelectSingleNode("ClCompile")
        if ($null -eq $clCompileNode) {
            Write-Host "ClCompile node not found. Creating it."
            # Usa o namespace do elemento pai para criar o novo nó
            $clCompileNode = $xml.CreateElement("ClCompile", $group.NamespaceURI)
            $group.AppendChild($clCompileNode) | Out-Null
        }
        
        # Garante que o nó <AdditionalIncludeDirectories> exista dentro de <ClCompile>.
        $includeDirsNode = $clCompileNode.SelectSingleNode("AdditionalIncludeDirectories")
        if ($null -eq $includeDirsNode) {
            Write-Host "Creating missing 'AdditionalIncludeDirectories' node."
            $includeDirsNode = $xml.CreateElement("AdditionalIncludeDirectories", $clCompileNode.NamespaceURI)
            $clCompileNode.AppendChild($includeDirsNode) | Out-Null
        }
        # --- FIM DA CORREÇÃO ROBUSTA ---

        # Agora que temos certeza de que o nó existe, podemos modificá-lo com segurança.
        $currentIncludes = $includeDirsNode.InnerText
        $newIncludePath = ";../../opus-source/include"
        
        # Verifica se o patch já não foi aplicado para evitar duplicatas
        if ($currentIncludes -notlike "*$newIncludePath*") {
            # Adiciona o novo valor
            $includeDirsNode.InnerText = ($currentIncludes + $newIncludePath)
            Write-Host "Successfully patched include path."
        } else {
            Write-Host "Include path already exists. No patch needed."
        }
        
        $patched = $true
        break # Sai do loop
    }
}

if (-not $patched) {
    Write-Host "FATAL: Could not find 'Release|Win32' configuration in $projFile to patch."
    exit 1
}

# Salva o arquivo .vcxproj modificado
$xml.Save($projFile)
Write-Host "Saved updated project file: $projFile"

exit 0
