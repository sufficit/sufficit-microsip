# scripts/build_pjsip.ps1
#
# This script compiles the PJSIP solution, robustly adding
# the include path for the Opus library.
# =================================================================================================
#
# Author: Hugo Castro de Deco, Sufficit
# Collaboration: Gemini AI for Google
# Date: June 15, 2025
# Version: 02 (Added _WIN32_WINNT and WINVER definitions to MSBuild command line)
#
# This header should be updated keeping the same format on every interaction.
# Static things and recomendations for AI:
#
#  1º Comments in this file are always in english
#  2º Version has to be updated by each IA interatiction
#  3º Bellow this section the AI should explain every success step on build proccess
#  4º Do not change this header structure

[CmdletBinding()]
param (
    # OpusIncludePath parameter is no longer strictly necessary for build logic,
    # as headers are copied directly in the workflow, but kept for compatibility.
    [Parameter(Mandatory=$false)] # Made optional as direct copying is now handled in workflow
    [string]$OpusIncludePath,

    [Parameter(Mandatory=$true)]
    [string]$SlnFile
)

Write-Host "Compiling solution: $SlnFile"
# Write-Host "Adding Opus include path: $OpusIncludePath" # No longer directly used for MSBuild includes

# Correct: Escapes the '$' so PowerShell doesn't try to expand $(AdditionalIncludeDirectories)
# MSBuild will correctly interpret the $(AdditionalIncludeDirectories) variable.
$includeArgument = "`"`$(AdditionalIncludeDirectories)`"" # Removed $OpusIncludePath as headers are copied

# Define _WIN32_WINNT and WINVER explicitly in the MSBuild command line
# This helps resolve conflicts with Windows SDK headers by ensuring these are defined early and consistently.
$winverDefines = "/p:_WIN32_WINNT=0x0601 /p:WINVER=0x0601"

msbuild.exe $SlnFile /p:Configuration=Release /p:Platform=Win32 /p:AdditionalIncludeDirectories=$includeArgument $winverDefines

# Checks the MSBuild exit code. If it's not 0 (success), exits the script with an error.
if ($LASTEXITCODE -ne 0) {
    Write-Host "##[error]MSBuild build failed with exit code: $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host "PJSIP build completed successfully."