Write-Host "==> Executando patch.ps1..."

$patchFile = Join-Path $PSScriptRoot "pjproject.patch"
if (!(Test-Path $patchFile)) {
    Write-Error "Arquivo de patch não encontrado: $patchFile"
    exit 1
}

Write-Host "Aplicando patch em modo seguro..."
git apply $patchFile

if ($LASTEXITCODE -ne 0) {
    Write-Error "Erro ao aplicar o patch com git apply."
    exit $LASTEXITCODE
}

Write-Host "Patch aplicado com sucesso."
