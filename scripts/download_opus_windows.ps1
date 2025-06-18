# =================================================================================================
# DOWNLOAD OPUS SCRIPT FOR WINDOWS (CALLED BY GITHUB ACTIONS WORKFLOW)
#
# Author: Hugo Castro de Deco, Sufficit
# Collaboration: Gemini AI for Google
# Date: June 18, 2025 - 00:35:00 AM -03
# Version: 1.0.72
#
# This script downloads the latest pre-compiled Opus library for Windows from a GitHub Release,
# extracts it, and copies the necessary .lib and .h files to the PJSIP build environment.
#
# Changes in Version 8:
#   - Improved error handling for fetching the latest release tag, ensuring $LATEST_RELEASE_DATA
#     and $LATEST_RELEASE_TAG are valid before proceeding.
#   - Renamed 'opus.lib' to 'libopus.lib' during copy operation to match linker's expectation,
#     resolving LNK1181 error.
#   - Minor refactor of variable names for clarity.
# Changes in Version 9:
#   - Updated version and timestamp in script header.
# Changes in Version 1.0.70:
#   - FIXED: Corrected ARTIFACT_PREFIX and modified logic to correctly construct the expected
#     artifact name from the release tag, removing the redundant "-build" string which caused
#     the artifact not to be found during download.
# Changes in Version 1.0.72:
#   - FIXED: Further refined the logic for constructing the expected artifact name to reliably
#     extract the date-time part from the release tag, accommodating variations like "build-".
#     This ensures that the script correctly matches the artifact name on GitHub releases.
# =================================================================================================

# Enforce stricter parsing and error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$REPO_OWNER="sufficit"
$REPO_NAME="opus"
# This base name should match the fixed part of your Windows Opus artifact name before the date/time.
$ARTIFACT_BASE_NAME="opus-windows-x64" 
$ARTIFACT_EXT=".zip"

# Use the GH_PAT environment variable directly
$authToken = $env:GH_PAT

Write-Host "Fetching latest release tag from https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"

try {
    $headers = @{}
    if ($authToken) {
        $headers.Add("Authorization", "token $authToken")
    }

    $LATEST_RELEASE_DATA = Invoke-RestMethod -Uri "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest" -Headers $headers -ErrorAction Stop
    
    if (-not $LATEST_RELEASE_DATA -or -not $LATEST_RELEASE_DATA.tag_name) {
        throw "Could not retrieve the latest release tag from GitHub API or API response was invalid."
    }
    $LATEST_RELEASE_TAG = $LATEST_RELEASE_DATA.tag_name

    Write-Host "Found latest Opus release tag: ${LATEST_RELEASE_TAG}"

    # Extract just the date-time part from the tag_name, regardless of prefix.
    # This regex looks for YYYYMMDD-HHMMSS at the end of the tag.
    if ($LATEST_RELEASE_TAG -match '(\d{8}-\d{6})$') {
        $dateTimePart = $matches[1]
    } else {
        # Fallback if the date-time part is not exactly as expected, try to use the whole tag
        Write-Warning "Could not parse specific date-time part from tag '${LATEST_RELEASE_TAG}'. Using full tag as part of artifact name."
        $dateTimePart = $LATEST_RELEASE_TAG -replace "build-", "" # Still remove "build-" if it exists
    }

    $expectedArtifactName = "${ARTIFACT_BASE_NAME}-${dateTimePart}${ARTIFACT_EXT}"
    Write-Host "Constructed expected artifact name: ${expectedArtifactName}"

    # Filter assets to find the specific zip file
    $downloadUrl = $null
    foreach ($asset in $LATEST_RELEASE_DATA.assets) {
        if ($asset.name -eq $expectedArtifactName) {
            $downloadUrl = $asset.browser_download_url
            break
        }
    }

    if (-not $downloadUrl) {
        throw "Could not find the expected artifact '${expectedArtifactName}' in the latest release. Available assets: $($LATEST_RELEASE_DATA.assets.name -join ', ')"
    }

    $tempDownloadDir = "external_libs/opus_temp"
    New-Item -ItemType Directory -Path $tempDownloadDir -Force | Out-Null

    $tempZipFile = Join-Path -Path $tempDownloadDir -ChildPath $expectedArtifactName

    Write-Host "Downloading Opus artifact from: ${downloadUrl}"
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZipFile -Headers $headers

    Write-Host "Extracting ${tempZipFile} to ${tempDownloadDir}"
    Expand-Archive -Path $tempZipFile -DestinationPath $tempDownloadDir -Force

    Write-Host "--- Contents of ${tempDownloadDir} after extraction (for debugging) ---"
    Get-ChildItem -Path $tempDownloadDir -Recurse | Format-List FullName, Name, Length, CreationTimeUtc, LastWriteTimeUtc
    Write-Host "-----------------------------------------------------------------"

    $pjLibDir = Join-Path -Path (Get-Location) -ChildPath "lib" # Relative to external/pjproject
    New-Item -ItemType Directory -Path $pjLibDir -Force | Out-Null

    $pjIncludeOpusDir = Join-Path -Path (Get-Location) -ChildPath "pjlib/include/pj/opus"
    New-Item -ItemType Directory -Path $pjIncludeOpusDir -Force | Out-Null

    # Find opus.lib (it might be in a subdirectory like 'dist_windows/bin')
    Write-Host "Searching for opus.lib in extracted contents..."
    $foundOpusLib = Get-ChildItem -Path $tempDownloadDir -Filter "opus.lib" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($null -ne $foundOpusLib) {
        $destinationFileName = "libopus.lib" # Rename to libopus.lib as MicroSIP expects
        $destinationPath = Join-Path -Path $pjLibDir -ChildPath $destinationFileName
        Copy-Item -Path $foundOpusLib.FullName -Destination $destinationPath -Force
        Write-Host "Copied $($foundOpusLib.Name) from $($foundOpusLib.FullName) to ${destinationPath} (renamed to ${destinationFileName})"
    } else {
        throw "opus.lib não encontrado dentro do conteúdo extraído do lançamento Opus (${tempDownloadDir}). Por favor, verifique a estrutura do artefato."
    }

    # Copy Opus headers to PJSIP's pjlib/include/pj/opus directory
    New-Item -ItemType Directory -Path $pjIncludeOpusDir -Force | Out-Null

    Write-Host "Attempting broad recursive search for Opus headers (*.h) in '${tempDownloadDir}' and its subdirectories..."
    $foundOpusHeaders = Get-ChildItem -Path $tempDownloadDir -Filter "*.h" -Recurse

    if ($null -ne $foundOpusHeaders -and $foundOpusHeaders.Count -gt 0) {
        foreach ($headerFile in $foundOpusHeaders) {
            Copy-Item -Path $headerFile.FullName -Destination $pjIncludeOpusDir -Force
            Write-Host "Copied header: $($headerFile.FullName) to ${pjIncludeOpusDir}"
        }
        Write-Host "Successfully copied $($foundOpusHeaders.Count) Opus header files."
    } else {
        Write-Warning "Nenhum arquivo de cabeçalho Opus (*.h) encontrado dentro do conteúdo extraído de ${tempDownloadDir}. Verifique se o pacote Opus contém os cabeçalhos."
    }

    # Clean up temporary directory
    Write-Host "Cleaning up temporary directory: ${tempDownloadDir}"
    Remove-Item -Path $tempDownloadDir -Recurse -Force

    Write-Host "Opus library and header processing completed."

} catch {
    Write-Host "##[error]Error downloading/preparing Opus: $($_.Exception.Message)"
    exit 1
}