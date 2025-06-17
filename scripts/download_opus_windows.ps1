# =================================================================================================
# DOWNLOAD OPUS SCRIPT FOR WINDOWS (CALLED BY GITHUB ACTIONS WORKFLOW)
#
# Author: Hugo Castro de Deco, Sufficit
# Collaboration: Gemini AI for Google
# Date: June 16, 2025
# Version: 7 (Removed 'param' block to bypass parsing issues in CI)
#
# This script downloads the latest pre-compiled Opus library for Windows from a GitHub Release,
# extracts it, and copies the necessary .lib and .h files to the PJSIP build environment.
#
# Changes in Version 7:
#   - Removed the 'param' block. The GitHubToken is now directly read from the environment
#     variable GH_PAT. This is a workaround to bypass a persistent "param is not recognized" error
#     in the GitHub Actions runner environment, which seems to be related to PowerShell's parsing
#     of the 'param' keyword in specific CI contexts.
#   - Explicitly using $env:GH_PAT for the authentication token.
# =================================================================================================

# Enforce stricter parsing and error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Parameter removed - GitHubToken is now read directly from environment variable
# param(
#     [string]$GitHubToken = ""
# )

$REPO_OWNER="sufficit"
$REPO_NAME="opus"
$ARTIFACT_PREFIX="opus-windows-x64"
$ARTIFACT_EXT=".zip"

# Use the GH_PAT environment variable for authentication
$GitHubToken = $env:GH_PAT

if ([string]::IsNullOrEmpty($GitHubToken)) {
    Write-Warning "##[warning]GitHubToken (GH_PAT environment variable) is not set. Downloads from private repositories or with high rate limits may fail."
    # No exit 1 here, as public repo downloads might still work.
}

# Construct paths relative to GITHUB_WORKSPACE
$pjsipRoot = $env:GITHUB_WORKSPACE
$pjsipLibDir = Join-Path -Path $pjsipRoot -ChildPath "external/pjproject/lib"
$pjIncludeOpusDir = Join-Path -Path $pjsipRoot -ChildPath "external/pjproject/pjlib/include/pj/opus"
$tempDownloadDir = Join-Path -Path $pjsipRoot -ChildPath "external_libs/opus_temp"

# Ensure temp directory exists
New-Item -ItemType Directory -Path $tempDownloadDir -Force | Out-Null

Write-Host "Fetching latest release tag from https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
$releaseApiUrl = "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"

try {
    $headers = @{ "Accept" = "application/vnd.github.v3+json" }
    if (-not [string]::IsNullOrEmpty($GitHubToken)) {
        $headers.Add("Authorization", "token $GitHubToken")
    }

    $latestRelease = Invoke-RestMethod -Uri $releaseApiUrl -Headers $headers
    $latestTag = $latestRelease.tag_name
    Write-Host "Found latest Opus release tag: ${latestTag}"

    $expectedArtifactName = "${ARTIFACT_PREFIX}-${latestTag.Replace('build-', '')}${ARTIFACT_EXT}"
    Write-Host "Expected artifact name: ${expectedArtifactName}"

    $assetUrl = $null
    foreach ($asset in $latestRelease.assets) {
        if ($asset.name -eq $expectedArtifactName) {
            $assetUrl = $asset.browser_download_url
            break
        }
    }

    if ($null -eq $assetUrl) {
        throw "Artifact '${expectedArtifactName}' not found in the latest release. Available assets: $($latestRelease.assets.name -join ', ')"
    }

    $downloadPath = Join-Path -Path $tempDownloadDir -ChildPath "${ARTIFACT_PREFIX}${ARTIFACT_EXT}"
    Write-Host "Downloading Opus artifact from: ${assetUrl}"
    Invoke-WebRequest -Uri $assetUrl -OutFile $downloadPath -Headers $headers

    Write-Host "Extracting ${downloadPath} to ${tempDownloadDir}"
    Expand-Archive -Path $downloadPath -DestinationPath $tempDownloadDir -Force

    Write-Host "--- Contents of ${tempDownloadDir} after extraction (for debugging) ---"
    Get-ChildItem -Path $tempDownloadDir -Recurse | Format-List FullName
    Write-Host "-----------------------------------------------------------------"

    # Copy Opus library to PJSIP's lib directory
    New-Item -ItemType Directory -Path $pjsipLibDir -Force | Out-Null

    Write-Host "Searching for opus.lib in extracted contents..."
    $foundOpusLib = Get-ChildItem -Path $tempDownloadDir -Filter "opus.lib" -Recurse | Select-Object -First 1

    if ($null -ne $foundOpusLib) {
        # Define the new name for the copied Opus library to match linker's expectation
        $destinationFileName = "libopus.lib"
        $destinationPath = Join-Path -Path $pjsipLibDir -ChildPath $destinationFileName

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
        Write-Warning "Nenhum arquivo de cabeçalho Opus (*.h) encontrado dentro do conteúdo extraído de ${tempDownloadDir}. Verifique se o pacote Opus contém os cabeçalhos esperados."
    }

} catch {
    Write-Host "##[error]Erro durante o download e preparação do Opus: $($_.Exception.Message)"
    exit 1 # Indicate failure
} finally {
    # Clean up temporary directory
    Write-Host "Cleaning up temporary directory: ${tempDownloadDir}"
    Remove-Item -Path $tempDownloadDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Opus library and header processing completed."
}