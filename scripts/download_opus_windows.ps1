# =================================================================================================
# DOWNLOAD OPUS SCRIPT FOR WINDOWS (CALLED BY GITHUB ACTIONS WORKFLOW)
#
# Author: Hugo Castro de Deco, Sufficit
# Collaboration: Gemini AI for Google
# Date: June 16, 2025
# Version: 4 (Fixed variable interpolation in throw statement)
#
# This script downloads the latest pre-compiled Opus library for Windows from a GitHub Release,
# extracts it, and copies the necessary .lib and .h files to the PJSIP build environment.
#
# Changes:
#   - Improved robustness for finding and copying Opus header files, searching recursively.
#   - Added Set-StrictMode and ErrorActionPreference for better error handling.
#   - Added cleanup of the temporary download directory (external_libs/opus_temp).
#   - **FIXED: Variable interpolation in error message by using ${} for clarity.**
# =================================================================================================

# Enforce stricter parsing and error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$REPO_OWNER="sufficit"
$REPO_NAME="opus"
$ARTIFACT_PREFIX="opus-windows-x64"
$ARTIFACT_EXT=".zip"

Write-Host "Fetching latest release tag from https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
try {
    $LATEST_RELEASE_DATA = Invoke-RestMethod -Uri "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest" -Headers @{Authorization = "token $env:GITHUB_TOKEN"} -ErrorAction Stop
    $LATEST_RELEASE_TAG = $LATEST_RELEASE_DATA.tag_name
    Write-Host "Found latest Opus release tag: $LATEST_RELEASE_TAG"
}
catch {
    throw "Erro ao obter o último lançamento do Opus: $($_.Exception.Message)"
}

# Construct expected artifact name based on convention (e.g., opus-windows-x64-20250616-164541.zip)
# We assume the release asset name directly corresponds to the release tag's date-time part
# or can be derived predictably. For this example, let's derive it from the tag.
# For example, if tag is "build-20250616-164541", then artifact is "opus-windows-x64-20250616-164541.zip"
$RELEASE_DATE_PART = $LATEST_RELEASE_TAG -replace "build-", ""
$EXPECTED_ARTIFACT_NAME = "${ARTIFACT_PREFIX}-${RELEASE_DATE_PART}${ARTIFACT_EXT}"
Write-Host "Expected artifact name: $EXPECTED_ARTIFACT_NAME"

# Find the download URL for the specific artifact
$DOWNLOAD_URL = $null
foreach ($asset in $LATEST_RELEASE_DATA.assets) {
    if ($asset.name -eq $EXPECTED_ARTIFACT_NAME) {
        $DOWNLOAD_URL = $asset.browser_download_url
        break
    }
}

if (-not $DOWNLOAD_URL) {
    # Changed variable interpolation to use ${}
    throw "Não foi possível encontrar o artefato '$EXPECTED_ARTIFACT_NAME' no último lançamento do ${REPO_OWNER}/${REPO_NAME}. Artefatos disponíveis: $($LATEST_RELEASE_DATA.assets.name -join ', ')"
}

Write-Host "Downloading Opus artifact from: $DOWNLOAD_URL"

$tempDownloadDir = "external_libs/opus_temp"
$zipFilePath = Join-Path -Path $tempDownloadDir -ChildPath $EXPECTED_ARTIFACT_NAME

# Create temporary directory for download and extraction
New-Item -ItemType Directory -Path $tempDownloadDir -Force | Out-Null

try {
    Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile $zipFilePath -Headers @{Authorization = "token $env:GITHUB_TOKEN"} -ErrorAction Stop
}
catch {
    # Changed variable interpolation to use ${}
    throw "Erro ao baixar o artefato Opus de ${DOWNLOAD_URL}: $($_.Exception.Message)"
}

Write-Host "Extracting $zipFilePath to $tempDownloadDir"
try {
    Expand-Archive -Path $zipFilePath -DestinationPath $tempDownloadDir -Force
}
catch {
    throw "Erro ao extrair o artefato Opus de ${zipFilePath}: $($_.Exception.Message)"
}

Write-Host "--- Contents of $tempDownloadDir after extraction (for debugging) ---"
Get-ChildItem -Path $tempDownloadDir -Recurse | Select-Object FullName
Write-Host "-----------------------------------------------------------------"

# Define target directories relative to the current PJSIP directory
$pjsipLibDir = "lib" # PJSIP's default lib directory for build outputs
$pjIncludeOpusDir = "pjlib/include/pj/opus" # PJSIP's include path for Opus headers

# Create the PJSIP lib directory if it doesn't exist
New-Item -ItemType Directory -Path $pjsipLibDir -Force | Out-Null

# Find opus.lib and copy it to PJSIP's lib directory
Write-Host "Searching for opus.lib in extracted contents..."
# Search recursively for opus.lib within the extracted contents
$foundOpusLib = Get-ChildItem -Path $tempDownloadDir -Filter "opus.lib" -Recurse | Select-Object -First 1

if ($null -ne $foundOpusLib) {
    Copy-Item -Path $foundOpusLib.FullName -Destination $pjsipLibDir -Force
    Write-Host "Copied opus.lib from $($foundOpusLib.FullName) to $pjsipLibDir"
} else {
    throw "opus.lib não encontrado dentro do conteúdo extraído do lançamento Opus ($tempDownloadDir). Por favor, verifique a estrutura do artefato."
}

# Copy Opus headers to PJSIP's pjlib/include/pj/opus directory
New-Item -ItemType Directory -Path $pjIncludeOpusDir -Force | Out-Null

Write-Host "Attempting broad recursive search for Opus headers (*.h) in '$tempDownloadDir' and its subdirectories..."
$foundOpusHeaders = Get-ChildItem -Path $tempDownloadDir -Filter "*.h" -Recurse

if ($null -ne $foundOpusHeaders -and $foundOpusHeaders.Count -gt 0) {
    foreach ($headerFile in $foundOpusHeaders) {
        Copy-Item -Path $headerFile.FullName -Destination $pjIncludeOpusDir -Force
        Write-Host "Copied header: $($headerFile.FullName) to $pjIncludeOpusDir"
    }
    Write-Host "Successfully copied $($foundOpusHeaders.Count) Opus header files."
} else {
    Write-Warning "Nenhum arquivo de cabeçalho Opus (*.h) encontrado dentro do conteúdo extraído de $tempDownloadDir. Verifique se o pacote Opus contém os cabeçalhos."
}

# Clean up temporary directory
Write-Host "Cleaning up temporary directory: $tempDownloadDir"
Remove-Item -Path $tempDownloadDir -Recurse -Force | Out-Null

Write-Host "Opus library and header processing completed."
