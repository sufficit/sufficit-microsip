# scripts/build-pjsip.ps1
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

# Aqui, não precisamos escapar o '$', pois estamos em um script .ps1 dedicado.
# MSBuild irá interpretar a variável $(AdditionalIncludeDirectories) corretamente.
$includeArgument = "`"$(AdditionalIncludeDirectories);$OpusIncludePath`""

msbuild.exe $SlnFile /p:Configuration=Release /p:Platform=Win32 /p:AdditionalIncludeDirectories=$includeArgument

# Verifica o código de saída do MSBuild. Se não for 0 (sucesso), encerra o script com erro.
if ($LASTEXITCODE -ne 0) {
    Write-Host "##[error]O build do MSBuild falhou com o código de saída: $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host "Build do PJSIP concluído com sucesso."
