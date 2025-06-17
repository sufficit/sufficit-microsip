# Build Automation Scripts for Sufficit MicroSIP - Gemini AI Collaboration

## Overview

This directory contains PowerShell scripts developed and refined in collaboration with Google's Gemini AI to automate the build process for the Sufficit MicroSIP project on GitHub Actions. The primary goal is to ensure a reliable and reproducible build for Windows (x64), with future expansion to Linux and Linux ARM.

## Important Note on File Versions

Please ensure that the `Version` and `Timestamp` (or `Last Updated` / `Last Modified`) comments at the top of relevant script files (e.g., `.ps1` files) and configuration header files (e.g., `.h` files like `config_site_content.h` and `pjsip_extra_defines_content.h`) are **manually updated with each and every change** made to these files. This practice is crucial for traceability and to accurately reflect the state of the build automation.

## Core Components

The automation relies on two main PowerShell scripts:

1.  `download_opus_windows.ps1`: Responsible for fetching pre-compiled Opus libraries.
2.  `patch_microsip_vcxproj.ps1`: Modifies the MicroSIP Visual Studio project file (`.vcxproj`) to correctly link against the compiled PJSIP libraries and their dependencies.

## Key Challenges and Solutions (Gemini AI Collaboration History)

The development of these scripts has involved addressing several persistent and sutis issues, primarily related to path resolution, dependency management, and PowerShell's strict parsing rules within the GitHub Actions environment.

### 1. `download_opus_windows.ps1`
* **Initial Problem:** Difficulty authenticating to GitHub Releases to download the Opus artifact, often resulting in "Unauthorized" errors or PowerShell parameter binding failures (e.g., "A parameter cannot be found that matches parameter name 'GitHubToken'." or "'param' is not recognized").
* **Solution:**
    * The `param` block was **removed** from the script.
    * The GitHub Token (`GH_PAT`) is now directly accessed as an environment variable (`$env:GH_PAT`) within the script. This bypasses PowerShell's strict parameter parsing in the CI context.
    * The Opus artifact is fetched from a specific GitHub Release (`sufficit/opus`).
    * Downloaded Opus `.zip` files are extracted to a temporary directory (`external_libs/opus_temp`).
    * The `opus.lib` file is explicitly located, **renamed to `libopus.lib`**, and moved to a centralized PJSIP library directory (`external/pjproject/lib`).
    * All necessary Opus header files (`*.h`) are recursively searched for in the extracted content and copied to `pjlib/include/pj/opus` within the PJSIP structure.
    * Temporary directories are cleaned up after successful processing.

### 2. `config_site_content.h` and `pjsip_extra_defines_content.h`
* **Problem:** Missing header files (`config_site.h`, `pjsip_extra_defines.h`) leading to "Cannot find path" errors during PJSIP compilation, as they were not checked out with the main `pjproject` submodule.
* **Solution:**
    * These files are now stored directly in the main repository under the `scripts/` directory (`scripts/config_site_content.h`, `scripts/pjsip_extra_defines_content.h`).
    * The `Prepare and Build PJSIP` step explicitly copies these files into the expected PJSIP include paths (`pjlib/include/pj/`).
    * `config_site_content.h` includes `#ifndef` guards for common Windows macros (`_WIN32_WINNT`, `_WIN32`, `_M_X64`) to prevent "macro redefinition" warnings (C4005) with Visual Studio 2022.

### 3. `patch_microsip_vcxproj.ps1`
This script has been the source of the most challenging debugging due to interactions between PowerShell, XML manipulation, and MSBuild variables.

* **Problem 1:** Initial `LNK1181: cannot open input file` errors (e.g., `pjlib.lib`, `pjlib-util.lib`).
* **Solution 1:**
    * The build workflow now explicitly compiles all individual PJSIP `.vcxproj` files and then **renames** their output `.lib` files to simpler names (e.g., `pjlib-util-x86_64-x64-vc14-Release.lib` becomes `pjlib-util.lib`).
    * All these renamed `.lib` files are **moved** to a single, centralized directory: `external/pjproject/lib`. This simplifies linker path management.
    * The `patch_microsip_vcxproj.ps1` script is updated to explicitly set the `AdditionalLibraryDirectories` in `microsip.vcxproj` to this centralized `external/pjproject/lib` folder.
    * The script also explicitly lists *all* required PJSIP and common Windows libraries in `AdditionalDependencies`, replacing any existing entries to gain full control.

* **Problem 2:** PowerShell `ParserError` related to here-strings and MSBuild variables in XML attributes (e.g., "The term 'LibraryPath' is not recognized," "Missing ')' in method call," "No characters are allowed after a here-string header").
* **Solution 2:**
    * The problematic `Condition` attribute for `ItemDefinitionGroup` is now set using an **intermediate PowerShell variable** that holds the literal here-string value. This separates the here-string's strict parsing rules from the `SetAttribute` method call.
    * All MSBuild variables (e.g., `$(LibraryPath)`, `%(AdditionalIncludeDirectories)`) when intended to be **literal strings** within the XML are now enclosed in **single quotes** within the PowerShell array definitions (e.g., `'$(LibraryPath)'`). This ensures PowerShell passes them as-is to the XML, where MSBuild then correctly evaluates them.

* **Problem 3:** `Cannot open include file: 'json.h'` error during MicroSIP compilation, even after correctly patching library paths.
* **Solution 3:**
    * The include path for `json.h` was incorrect. It was `.\lib\jsoncpp` but should have been `.\lib\jsoncpp\json`. This was corrected in the `AdditionalIncludeDirectories` section of `patch_microsip_vcxproj.ps1`.

* **Problem 4:** Potential issues from inherited or default MSBuild paths/dependencies still being used (e.g., `%(AdditionalIncludeDirectories)`, `%(AdditionalLibraryDirectories)`, `%(AdditionalDependencies)`).
* **Solution 4:**
    * These placeholders were **removed** from the final `AdditionalIncludeDirectories`, `AdditionalLibraryDirectories`, and `AdditionalDependencies` strings written to `microsip.vcxproj`. This ensures that only the explicitly defined paths and libraries are used, preventing unexpected conflicts or missing paths that might arise from MSBuild's default resolution.

## Usage with GitHub Actions

1.  **Repository Structure:**
    * Ensure your main repository (`sufficit/sufficit-microsip`) contains the MicroSIP source code and this `scripts/` directory.
    * The `pjproject` repository (or a fork) should be included as a submodule at `external/pjproject`.
    * The `opus` repository (or a fork, specifically providing pre-compiled binaries via GitHub Releases) is expected to be maintained separately.
    * Ensure `config_site_content.h` and `pjsip_extra_defines_content.h` are present in this `scripts/` directory.

2.  **GitHub Secret:**
    * A GitHub Personal Access Token (PAT) with `repo` scope is required. Store it as a repository secret named `GH_PAT`. This token is used by `download_opus_windows.ps1` to fetch the Opus release artifact.

3.  **Workflow (`cpp-build.yml`):**
    * The workflow orchestrates the steps: checking out code, preparing build dates, setting up MSBuild, preparing/compiling PJSIP, patching MicroSIP's `.vcxproj`, compiling MicroSIP, and uploading artifacts.
    * **Debug Step (`List PJSIP Lib Directory Contents`):** A diagnostic step has been added before the final MicroSIP compilation to list the contents of the `external/pjproject/lib` directory. This is crucial for verifying that the compiled and renamed PJSIP `.lib` files are indeed present and correctly named if linker errors persist.
    * **Example Versioning Information:**
        * **Version**: `X.Y.Z`
        * **Last Updated**: `YYYY-MM-DD HH:MM:SS TZ`
        * **Description**: A brief, single-line summary of the changes in this workflow version.

4.  **Future Expansion:**
    * Placeholder jobs for `build-linux` and `build-linux-arm` are included but commented out. These can be enabled and configured once the Windows build is fully stable and requirements for other platforms are defined.

This comprehensive approach ensures that the build environment is tightly controlled and all necessary dependencies are correctly managed and linked, leading to a reliable automated build process.