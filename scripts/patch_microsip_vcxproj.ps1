# =================================================================================================
# PATCH SCRIPT FOR MicroSIP PROJECT FILE (CALLED BY GITHUB ACTIONS WORKFLOW)
#
# This script adds PJSIP and MicroSIP's internal include and library paths to microsip.vcxproj.
#
# Changes:
#   - FIXED: Removidas as referências diretas a `$(ProjectDir)` e `$(SolutionDir)`
#     dentro do script. Agora, todos os caminhos são construídos a partir dos parâmetros de entrada
#     ($ProjFile, $PjsipIncludeRoot, $PjsipLibRoot, $PjsipAppsIncludePath) que devem ser
#     caminhos absolutos ou relativos à raiz do repositório MicroSIP, não macros do MSBuild.
#   - Adicionado o bloco `param` para aceitar `PjsipIncludeRoot`, `PjsipLibRoot`,
#     e `PjsipAppsIncludePath` como parâmetros, resolvendo o erro "A parameter cannot be found".
# =================================================================================================
param (
    [Parameter(Mandatory=$true)]
    [string]$ProjFile, # Caminho completo para microsip.vcxproj
    [Parameter(Mandatory=$true)]
    [string]$PjsipIncludeRoot, # ex: 'external/pjproject' (relativo à raiz do MicroSIP)
    [Parameter(Mandatory=$true)]
    [string]$PjsipLibRoot, # ex: 'external/pjproject/lib' (relativo à raiz do MicroSIP)
    [Parameter(Mandatory=$true)]
    [string]$PjsipAppsIncludePath # ex: 'external/pjproject/pjsip/include' (onde pjsua.h pode estar)
)

Write-Host "Executing patch script for MicroSIP: $ProjFile"
Write-Host "PjsipIncludeRoot received: $PjsipIncludeRoot"
Write-Host "PjsipLibRoot received: $PjsipLibRoot"
Write-Host "PjsipAppsIncludePath received: $PjsipAppsIncludePath"

try {
    [xml]$projXml = Get-Content $ProjFile

    $nsManager = New-Object System.Xml.XmlNamespaceManager($projXml.NameTable)
    $nsManager.AddNamespace("msbuild", "http://schemas.microsoft.com/developer/msbuild/2003")

    # Obter o diretório do ficheiro de projeto MicroSIP (Microsip root)
    $microsipProjectDir = Split-Path -Path $ProjFile -Parent
    
    # Target the main project's ClCompile and Linker configurations
    # We target Release|x64 specifically for includes and libraries
    $clCompileNode = $projXml.SelectSingleNode("//msbuild:ItemDefinitionGroup[contains(@Condition, 'Release') and contains(@Condition, 'x64')]/msbuild:ClCompile", $nsManager)
    $linkerNode = $projXml.SelectSingleNode("//msbuild:ItemDefinitionGroup[contains(@Condition, 'Release') and contains(@Condition, 'x64')]/msbuild:Link", $nsManager)

    if ($clCompileNode) {
        # Construir caminhos relativos ao ficheiro .vcxproj que está a ser patchado.
        # Os parâmetros $PjsipIncludeRoot, $PjsipLibRoot, $PjsipAppsIncludePath
        # são passados como caminhos relativos à raiz do repositório MicroSIP.
        # Precisamos de os converter para serem relativos ao ficheiro .vcxproj (`microsip.vcxproj`).

        # Caminho relativo da raiz do repositório até ao diretório do .vcxproj
        $relativeRootToProj = [System.IO.Path]::GetRelativePath($microsipProjectDir, (Get-Location).Path) # Assume que estamos na raiz do repositório quando o script é chamado
        if (-not $relativeRootToProj) { $relativeRootToProj = "." } # Se for o próprio diretório, use "."

        # Ajustar os caminhos PJSIP para serem relativos ao diretório do `microsip.vcxproj`
        $pjsipIncludePathRelative = [System.IO.Path]::GetRelativePath($microsipProjectDir, (Join-Path -Path $env:GITHUB_WORKSPACE -ChildPath $PjsipIncludeRoot))
        $pjsipAppsIncludePathRelative = [System.IO.Path]::GetRelativePath($microsipProjectDir, (Join-Path -Path $env:GITHUB_WORKSPACE -ChildPath $PjsipAppsIncludePath))
        $pjsipLibRootRelative = [System.IO.Path]::GetRelativePath($microsipProjectDir, (Join-Path -Path $env:GITHUB_WORKSPACE -ChildPath $PjsipLibRoot))

        # Adicionar ALL necessary include directories:
        # 1. MicroSIP's own directories (agora relativos ao ProjectDir)
        # 2. Third-party libraries specifically for MicroSIP (e.g., jsoncpp)
        # 3. All PJSIP core include directories (agora relativos ao ProjectDir, usando os parâmetros)
        $requiredIncludes = @(
            ".\" # Para cabeçalhos na raiz do projeto MicroSIP (onde microsip.vcxproj está)
            ".\lib" # Para cabeçalhos em MicroSIP's lib folder
            ".\lib\jsoncpp" # Para json.h
            "$pjsipIncludePathRelative/pjlib/include"
            "$pjsipIncludePathRelative/pjlib-util/include"
            "$pjsipIncludePathRelative/pjnath/include"
            "$pjsipIncludePathRelative/pjmedia/include"
            "$pjsipAppsIncludePathRelative" # Já aponta para external/pjproject/pjsip/include
        )

        $additionalIncludeDirsNode = $clCompileNode.SelectSingleNode("./msbuild:AdditionalIncludeDirectories", $nsManager)

        # Concatenate and filter out duplicates
        $currentIncludes = if ($additionalIncludeDirsNode) { $additionalIncludeDirsNode.'#text' } else { "" }
        $newIncludesArray = $currentIncludes.Split(';') | Where-Object { $_ -ne "" } | ForEach-Object { $_.Trim() }

        foreach ($includePath in $requiredIncludes) {
            # Add only if not already present
            if ($newIncludesArray -notcontains $includePath) {
                $newIncludesArray += $includePath
            }
        }
        $newIncludesString = ($newIncludesArray | Select-Object -Unique) -join ';' # Ensure unique and rejoin

        if ($additionalIncludeDirsNode) {
            # Check if actual change is needed to avoid unnecessary file writes
            if ($newIncludesString -ne $currentIncludes) {
                $additionalIncludeDirsNode.'#text' = "$newIncludesString;%(AdditionalIncludeDirectories)"
                Write-Host "Updated AdditionalIncludeDirectories in $ProjFile to include all necessary paths."
            } else {
                Write-Host "All necessary include paths already present in AdditionalIncludeDirectories."
            }
        } else {
            $newIncludeNode = $projXml.CreateElement("AdditionalIncludeDirectories", $nsManager.LookupNamespace("msbuild"))
            $newIncludeNode.'#text' = "$newIncludesString;%(AdditionalIncludeDirectories)"
            $clCompileNode.AppendChild($newIncludeNode)
            Write-Host "Added AdditionalIncludeDirectories node with all necessary paths in $ProjFile."
        }
    } else {
        Write-Host "##[warning]Warning: Could not find ClCompile node for Release|x64 in $ProjFile. Skipping include path update."
    }

    if ($linkerNode) {
        # Add PJSIP library directories
        $additionalLibraryDirsNode = $linkerNode.SelectSingleNode("./msbuild:AdditionalLibraryDirectories", $nsManager)
        # O caminho da biblioteca PJSIP já é passado como relativo à raiz do MicroSIP.
        # Ele precisa ser relativo ao diretório do .vcxproj (que é a raiz do MicroSIP)
        $pjsipLibPathLinker = $pjsipLibRootRelative

        if ($additionalLibraryDirsNode) {
            $currentLibDirs = $additionalLibraryDirsNode.'#text'
            if ($currentLibDirs -notmatch [regex]::Escape($pjsipLibPathLinker)) {
                $additionalLibraryDirsNode.'#text' = "$pjsipLibPathLinker;$currentLibDirs"
                Write-Host "Updated AdditionalLibraryDirectories in $ProjFile to include PJSIP lib path."
            } else {
                Write-Host "PJSIP library path already present in AdditionalLibraryDirectories."
            }
        } else {
            $newLibNode = $projXml.CreateElement("AdditionalLibraryDirectories", $nsManager.LookupNamespace("msbuild"))
            $newLibNode.'#text' = "$pjsipLibPathLinker;%(AdditionalLibraryDirectories)"
            $linkerNode.AppendChild($newLibNode)
            Write-Host "Added AdditionalLibraryDirectories node with PJSIP lib path in $ProjFile."
        }

        # Add PJSIP additional dependencies (libraries)
        # NOTE: Assumimos que estes são os nomes dos ficheiros .lib gerados
        # pela compilação anterior dos projetos individuais.
        $pjsipLibs = @(
            "pjlib.lib",
            "pjlib-util.lib",
            "pjnath.lib",
            "pjmedia.lib",
            "pjmedia-audiodev.lib",
            "pjmedia-codec.lib",
            "pjmedia-videodev.lib",
            "pjsip-core.lib",
            "pjsip-simple.lib",
            "pjsip-ua.lib",
            "pjsua-lib.lib", # Crucial for pjsua.h
            "pjsua2-lib.lib",
            "libbaseclasses.lib",
            "libg7221codec.lib",
            "libgsmcodec.lib",
            "libilbccodec.lib",
            "libmilenage.lib",
            "libresample.lib",
            "libspeex.lib",
            "libsrtp.lib",
            "libwebrtc.lib",
            "libyuv.lib",
            "libopus.lib", # From our opus download
            # Common Windows libs that PJSIP might need for linking
            "ws2_32.lib",
            "advapi32.lib",
            "iphlpapi.lib",
            "mswsock.lib",
            "ole32.lib",
            "winmm.lib",
            "user32.lib",
            "gdi32.lib",
            "crypt32.lib",
            "dnsapi.lib"
            # Adicione quaisquer outras bibliotecas específicas que o seu MicroSIP precise para ligar
        )
        # Juntar os nomes das libs com ponto e vírgula
        $pjsipLibsString = $pjsipLibs -join ';'

        $additionalDependenciesNode = $linkerNode.SelectSingleNode("./msbuild:AdditionalDependencies", $nsManager)

        if ($additionalDependenciesNode) {
            $currentDependencies = $additionalDependenciesNode.'#text'
            $newDependencies = $currentDependencies
            # Adicionar apenas as libs que ainda não estão presentes
            foreach ($lib in $pjsipLibs) {
                if ($currentDependencies -notmatch [regex]::Escape($lib)) {
                    $newDependencies = "$lib;$newDependencies"
                }
            }
            if ($newDependencies -ne $currentDependencies) {
                $additionalDependenciesNode.'#text' = "$newDependencies;%(AdditionalDependencies)"
                Write-Host "Updated AdditionalDependencies in $ProjFile to include PJSIP libraries."
            } else {
                Write-Host "PJSIP libraries already present in AdditionalDependencies."
            }
        } else {
            $newDepNode = $projXml.CreateElement("AdditionalDependencies", $nsManager.LookupNamespace("msbuild"))
            $newDepNode.'#text' = "$pjsipLibsString;%(AdditionalDependencies)"
            $linkerNode.AppendChild($newDepNode)
            Write-Host "Added AdditionalDependencies node with PJSIP libraries in $ProjFile."
        }
    } else {
        Write-Host "##[warning]Warning: Could not find Linker node for Release|x64 in $ProjFile. Skipping library path and dependencies update."
    }

    $projXml.Save($ProjFile)
    Write-Host "Successfully patched $ProjFile."
} catch {
    Write-Host "##[error]Error patching $($ProjFile): $($_.Exception.Message)"
    exit 1
}
