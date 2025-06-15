# scripts/build_pjsip.ps1
#
# Este script compila a solução PJSIP, adicionando de forma robusta
# o caminho de inclusão para a biblioteca Opus.

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$OpusIncludePath,

    [Parameter(Mandatory=$true)]
    [string]$SlnFile
)

Write-Host "Compilando a solução: $SlnFile"
Write-Host "Adicionando o caminho de inclusão do Opus: $OpusIncludePath"

# --- Início da Depuração ---
# Verifica se o diretório de inclusão do Opus existe
if (-not (Test-Path $OpusIncludePath)) {
    Write-Host "##[error]Erro: O caminho de inclusão do Opus não existe: $OpusIncludePath"
    exit 1
} else {
    Write-Host "Caminho de inclusão do Opus verificado: $OpusIncludePath (Existe)"
}

# Verifica se o arquivo opus/opus.h existe dentro do caminho de inclusão
$opusHeaderPath = Join-Path -Path $OpusIncludePath -ChildPath "opus/opus.h"
if (-not (Test-Path $opusHeaderPath)) {
    Write-Host "##[error]Erro: O arquivo 'opus/opus.h' não foi encontrado em: $opusHeaderPath"
    Write-Host "Certifique-se de que a estrutura de pastas do Opus esteja correta (opus-source/include/opus/opus.h)."
    exit 1
} else {
    Write-Host "Arquivo 'opus/opus.h' verificado: $opusHeaderPath (Existe)"
}
# --- Fim da Depuração ---

# Correção: Escapa o '$' para que o PowerShell não tente expandir $(AdditionalIncludeDirectories)
# MSBuild irá interpretar a variável $(AdditionalIncludeDirectories) corretamente.
$includeArgument = "`"`$(AdditionalIncludeDirectories);$OpusIncludePath`""

msbuild.exe $SlnFile /p:Configuration=Release /p:Platform=Win32 /p:AdditionalIncludeDirectories=$includeArgument

# Verifica o código de saída do MSBuild. Se não for 0 (sucesso), encerra o script com erro.
if ($LASTEXITCODE -ne 0) {
    Write-Host "##[error]O build do MSBuild falhou com o código de saída: $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host "Build do PJSIP concluído com sucesso."
