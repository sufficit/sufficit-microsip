# =================================================================================================
# PATCH SCRIPT FOR MicroSIP PROJECT FILE (CALLED BY GITHUB ACTIONS WORKFLOW)
#
# This script adds PJSIP and MicroSIP's internal include and library paths to microsip.vcxproj.
#
# Changes:
#   - FIXED: Ajustada a lógica de construção de caminhos. Agora, os parâmetros de entrada
#     ($PjsipIncludeRoot, $PjsipLibRoot, $PjsipAppsIncludePath) são tratados como caminhos
#     ABSOLUTOS já construídos pela etapa chamadora. Isso elimina a necessidade de lógica
#     de GetRelativePath ou Join-Path dentro deste script para os caminhos PJSIP.
#   - Adicionado o bloco `param` para aceitar `PjsipIncludeRoot`, `PjsipLibRoot`,
#     e `PjsipAppsIncludePath` como parâmetros, resolvendo o erro "A parameter cannot be found".
#   - Adicionadas verificações para garantir que os nós `ClCompile` e `Link` são encontrados,
#     e se não forem, o script tenta criá-los antes de adicionar os includes/libs.
#     Isto deve resolver o aviso "Could not find Linker node".
#   - Ajustados os caminhos de include para serem consistentes e garantir que os cabeçalhos PJSIP
#     são sempre encontrados corretamente pelo compilador do MicroSIP.
#   - FIXED: Corrigido `ParserError` na definição do atributo "Condition" para ItemDefinitionGroup.
#     A string agora é tratada como literal usando aspas duplas com escaping de aspas simples internas.
# =================================================================================================
param (
    [Parameter(Mandatory=$true)]
    [string]$ProjFile, # Caminho completo para microsip.vcxproj (ex: C:\a\sufficit-microsip\sufficit-microsip\microsip.vcxproj)
    [Parameter(Mandatory=$true)]
    [string]$PjsipIncludeRoot, # ex: 'C:\path\to\external\pjproject' (caminho absoluto para a raiz do PJSIP)
    [Parameter(Mandatory=$true)]
    [string]$PjsipLibRoot, # ex: 'C:\path\to\external\pjproject\lib' (caminho absoluto para as libs PJSIP)
    [Parameter(Mandatory=$true)]
    [string]$PjsipAppsIncludePath # ex: 'C:\path\to\external\pjproject\pjsip\include' (caminho absoluto para pjsua.h)
)

Write-Host "Executing patch script for MicroSIP: $ProjFile"
Write-Host "PjsipIncludeRoot received: $PjsipIncludeRoot"
Write-Host "PjsipLibRoot received: $PjsipLibRoot"
Write-Host "PjsipAppsIncludePath received: $PjsipAppsIncludePath"

try {
    [xml]$projXml = Get-Content $ProjFile

    $nsManager = New-Object System.Xml.XmlNamespaceManager($projXml.NameTable)
    $nsManager.AddNamespace("msbuild", "http://schemas.microsoft.com/developer/msbuild/2003")

    # O diretório do ficheiro de projeto MicroSIP (que é a raiz do repositório MicroSIP neste caso)
    $microsipProjectDir = Split-Path -Path $ProjFile -Parent
    
    # Os caminhos PJSIP são agora recebidos como absolutos, então precisamos de torná-los
    # relativos ao diretório do .vcxproj para a propriedade AdditionalIncludeDirectories.
    # Como microsip.vcxproj está na raiz do repositório, estes são os mesmos que os caminhos PJSIP_..._RELATIVE
    $pjsipIncludePathForVcxproj = [System.IO.Path]::GetRelativePath($microsipProjectDir, $PjsipIncludeRoot)
    $pjsipLibPathForVcxproj = [System.IO.Path]::GetRelativePath($microsipProjectDir, $PjsipLibRoot)
    $pjsipAppsIncludePathForVcxproj = [System.IO.Path]::GetRelativePath($microsipProjectDir, $PjsipAppsIncludePath)

    # Encontrar ou criar o ItemDefinitionGroup para Release|x64
    $itemDefinitionGroupNode = $projXml.SelectSingleNode("//msbuild:ItemDefinitionGroup[contains(@Condition, 'Release') and contains(@Condition, 'x64')]", $nsManager)
    if (-not $itemDefinitionGroupNode) {
        Write-Host "Creating missing ItemDefinitionGroup for Release|x64."
        $projectNode = $projXml.SelectSingleNode("/msbuild:Project", $nsManager)
        $itemDefinitionGroupNode = $projXml.CreateElement("ItemDefinitionGroup", $nsManager.LookupNamespace("msbuild"))
        # Corrigido: Usar aspas duplas e escapar as aspas simples internas
        $itemDefinitionGroupNode.SetAttribute("Condition", "'$(Configuration)|$(Platform)'=='Release|x64'")
        $projectNode.AppendChild($itemDefinitionGroupNode)
    }

    # Encontrar ou criar o nó ClCompile
    $clCompileNode = $itemDefinitionGroupNode.SelectSingleNode("./msbuild:ClCompile", $nsManager)
    if (-not $clCompileNode) {
        Write-Host "Creating missing ClCompile node for Release|x64."
        $clCompileNode = $projXml.CreateElement("ClCompile", $nsManager.LookupNamespace("msbuild"))
        $itemDefinitionGroupNode.AppendChild($clCompileNode)
    }

    # Encontrar ou criar o nó Link
    $linkerNode = $itemDefinitionGroupNode.SelectSingleNode("./msbuild:Link", $nsManager)
    if (-not $linkerNode) {
        Write-Host "Creating missing Link node for Release|x64."
        $linkerNode = $projXml.CreateElement("Link", $nsManager.LookupNamespace("msbuild"))
        $itemDefinitionGroupNode.AppendChild($linkerNode)
    }


    # Processar Includes
    # Add ALL necessary include directories:
    # 1. MicroSIP's own directories (relativos ao ProjectDir)
    # 2. Third-party libraries specifically for MicroSIP (e.g., jsoncpp)
    # 3. All PJSIP core include directories (relativos ao ProjectDir, usando os parâmetros)
    $requiredIncludes = @(
        ".\" # Para cabeçalhos na raiz do projeto MicroSIP (onde microsip.vcxproj está)
        ".\lib" # Para cabeçalhos em MicroSIP's lib folder
        ".\lib\jsoncpp" # Para json.h
        "$pjsipIncludePathForVcxproj\pjlib\include" # Usar barra invertida para consistência no Windows
        "$pjsipIncludePathForVcxproj\pjlib-util\include"
        "$pjsipIncludePathForVcxproj\pjnath\include"
        "$pjsipIncludePathForVcxproj\pjmedia\include"
        "$pjsipAppsIncludePathForVcxproj" # Já aponta para external/pjproject/pjsip/include
        # Adicionar include para Opus, que é copiado para pjlib/include/pj/opus
        "$pjsipIncludePathForVcxproj\pjlib\include\pj\opus"
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

    # Processar Library Directories e Dependencies
    # Add PJSIP library directories
    $additionalLibraryDirsNode = $linkerNode.SelectSingleNode("./msbuild:AdditionalLibraryDirectories", $nsManager)
    $libDirToAdd = $pjsipLibPathForVcxproj # Já é o caminho relativo ao microsip.vcxproj

    if ($additionalLibraryDirsNode) {
        $currentLibDirs = $additionalLibraryDirsNode.'#text'
        if ($currentLibDirs -notmatch [regex]::Escape($libDirToAdd)) {
            $additionalLibraryDirsNode.'#text' = "$libDirToAdd;$currentLibDirs"
            Write-Host "Updated AdditionalLibraryDirectories in $ProjFile to include PJSIP lib path."
        } else {
            Write-Host "PJSIP library path already present in AdditionalLibraryDirectories."
        }
    } else {
        $newLibNode = $projXml.CreateElement("AdditionalLibraryDirectories", $nsManager.LookupNamespace("msbuild"))
        $newLibNode.'#text' = "$libDirToAdd;%(AdditionalLibraryDirectories)"
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

    $projXml.Save($ProjFile)
    Write-Host "Successfully patched $ProjFile."
} catch {
    Write-Host "##[error]Error patching $($ProjFile): $($_.Exception.Message)"
    exit 1
}
