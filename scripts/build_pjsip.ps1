Write-Host "==> Iniciando build_pjsip.ps1..."

$pjDir = Join-Path $PSScriptRoot "pjproject"
if (!(Test-Path $pjDir)) {
    Write-Error "Diretório pjproject não encontrado."
    exit 1
}

# Assumindo que vc clonou o pjproject corretamente
Set-Location $pjDir

Write-Host "Executando bootstrap..."
cmd /c "python configure.py"  # ou configure.bat se for o script correto

Write-Host "Compilando com nmake..."
cmd /c "nmake /f Makefile.msvc"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Falha na compilação do PJSIP com nmake."
    exit $LASTEXITCODE
}

Write-Host "Compilação do PJSIP concluída com sucesso."
