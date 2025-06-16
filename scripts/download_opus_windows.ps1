# =================================================================================================
# DOWNLOAD OPUS SCRIPT FOR WINDOWS (CALLED BY GITHUB ACTIONS WORKFLOW)
#
# Author: Hugo Castro de Deco, Sufficit
# Collaboration: Gemini AI for Google
# Date: June 16, 2025
# Version: 7
#
# This script downloads the latest pre-compiled Opus library for Windows from a GitHub Release,
# extracts it, and copies the necessary .lib and .h files to the PJSIP build environment.
#
# Changes:
#   - Improved robustness for finding and copying Opus header files by ensuring recursive search
#     and checking common 'include' subdirectories.
#   - Updated the warning message regarding missing headers to clarify the likely cause:
#     the Opus release artifact itself might not contain the necessary header files.
#   - **Replaced 'exit 1' with 'throw' for critical errors to ensure proper error propagation**
#     **in PowerShell and GitHub Actions, preventing empty exit codes.**
#   - Added Set-StrictMode and ErrorActionPreference for better error handling.
#   - Added cleanup of the temporary download directory (external_libs/opus_temp).
# =================================================================================================

# Enforce stricter parsing and error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop" # Stop on any terminating error

$REPO_OWNER="sufficit"
$REPO_NAME="opus"
$ARTIFACT_PREFIX="opus-windows-x64"
$ARTIFACT_EXT=".zip"

Write-Host "Fetching latest release tag from https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
try {
  $LATEST_RELEASE_DATA = Invoke-RestMethod -Uri "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest" -Headers @{Authorization = "token $env:GITHUB_TOKEN"} -ErrorAction Stop
} catch {
  throw "Erro ao buscar o último release do Opus: $($_.Exception.Message)"
}

$LATEST_RELEASE_TAG = $LATEST_RELEASE_DATA.tag_name
if (-not $LATEST_RELEASE_TAG) {
  throw "Erro: Não foi possível encontrar a tag do último release para ${REPO_OWNER}/${REPO_NAME}"
}
Write-Host "Found latest Opus release tag: $LATEST_RELEASE_TAG"

$OPUS_BUILD_VERSION = ($LATEST_RELEASE_TAG -replace "build-", "") # Assumes tag is 'build-YYYYMMDD-HHMMSS'
$EXPECTED_ARTIFACT_NAME = "${ARTIFACT_PREFIX}-${OPUS_BUILD_VERSION}${ARTIFACT_EXT}"
Write-Host "Expected artifact name: $EXPECTED_ARTIFACT_NAME"

$DOWNLOAD_URL = $LATEST_RELEASE_DATA.assets | Where-Object { $_.name -eq $EXPECTED_ARTIFACT_NAME } | Select-Object -ExpandProperty browser_download_url
if (-not $DOWNLOAD_URL) {
  throw "Erro: Não foi possível encontrar o URL de download para o artefato $EXPECTED_ARTIFACT_NAME no release $LATEST_RELEASE_TAG"
}
Write-Host "Downloading Opus artifact from: $DOWNLOAD_URL"

$tempDownloadDir = "external_libs/opus_temp"
New-Item -ItemType Directory -Path $tempDownloadDir -Force
$zipPath = Join-Path -Path $tempDownloadDir -ChildPath $EXPECTED_ARTIFACT_NAME

try {
  Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile $zipPath
} catch {
  throw "Erro ao baixar o artefato Opus de $DOWNLOAD_URL: $($_.Exception.Message)"
}


Write-Host "Extracting $zipPath to $tempDownloadDir/"
try {
  Expand-Archive -Path $zipPath -DestinationPath "$tempDownloadDir/" -Force # Ensure trailing slash for destination
} catch {
  throw "Erro ao extrair o artefato Opus de $zipPath: $($_.Exception.Message)"
}


# Debugging: List contents after extraction to help understand the structure
Write-Host "--- Contents of $tempDownloadDir after extraction (for debugging) ---"
Get-ChildItem -Path $tempDownloadDir -Recurse | Select-Object FullName
Write-Host "-----------------------------------------------------------------"

# Copy opus.lib to PJSIP's lib directory
$pjsipLibDir = "lib"
New-Item -ItemType Directory -Path $pjsipLibDir -Force

$foundOpusLib = Get-ChildItem -Path "$tempDownloadDir" -Filter "opus.lib" -Recurse | Select-Object -First 1

if ($null -ne $foundOpusLib) {
    Copy-Item -Path $foundOpusLib.FullName -Destination $pjsipLibDir -ErrorAction Stop
    Write-Host "Copied opus.lib from $($foundOpusLib.FullName) to $pjsipLibDir"
} else {
    throw "Erro: opus.lib não encontrado dentro do conteúdo extraído do release Opus ($tempDownloadDir). Por favor, verifique a estrutura do artefato."
}

# Copy Opus headers to PJSIP's pjlib/include/pj/opus directory
$pjIncludeOpusDir = "pjlib/include/pj/opus"
New-Item -ItemType Directory -Path $pjIncludeOpusDir -Force

$foundOpusHeaders = @()

# First, try a broad recursive search for Opus headers, which should catch them
# if they are directly in any subfolder of $tempDownloadDir
Write-Host "Attempting broad recursive search for Opus headers (*.h) in '$tempDownloadDir' and its subdirectories..."
$foundOpusHeaders = Get-ChildItem -Path "$tempDownloadDir" -Filter "*.h" -Recurse -ErrorAction SilentlyContinue

# If no headers found, it's highly likely they are not included in the artifact
if ($null -eq $foundOpusHeaders -or $foundOpusHeaders.Count -eq 0) {
    # Using a here-string for the warning message to avoid concatenation issues
    Write-Warning @"
No Opus header files (*.h) foram encontrados dentro do conteúdo extraído do artefato de release do Opus ('$tempDownloadDir').
Isso indica que o arquivo ZIP de release do Opus baixado pode não conter os arquivos de cabeçalho necessários.
Por favor, certifique-se de que o artefato de release 'sufficit/opus' inclui os arquivos de cabeçalho (por exemplo, em um diretório 'include' ou 'dist_windows/include').
"@
} else {
    foreach ($headerFile in $foundOpusHeaders) {
        Copy-Item -Path $headerFile.FullName -Destination $pjIncludeOpusDir -ErrorAction Stop
        Write-Host "Copied header: $($headerFile.FullName) to $pjIncludeOpusDir"
    }
    Write-Host "Successfully copied $($foundOpusHeaders.Count) Opus header files."
}

# Clean up the temporary download directory
if (Test-Path $tempDownloadDir) {
    Write-Host "Cleaning up temporary directory: $tempDownloadDir"
    Remove-Item -Path $tempDownloadDir -Recurse -Force -ErrorAction SilentlyContinue # Continue even if cleanup fails
}

Write-Host "Opus library and header processing completed."
