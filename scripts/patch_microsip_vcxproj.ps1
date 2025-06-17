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
#   - Adicionadas verificações para garantir que os nódulos `ClCompile` e `Link` são encontrados,
#     e se não forem, o script tenta criá-los antes de adicionar os includes/libs.
#     Isto deve resolver o aviso "Could not find Linker node".
#   - Ajustados os caminhos de include para serem consistentes e garantir que os cabeçalhos PJSIP
#     são sempre encontrados corretamente pelo compilador do MicroSIP.
#   - FIXED: Corrigido `ParserError` na definição do atributo "Condition" para ItemDefinitionGroup.
#     A string agora é tratada como literal usando um here-string literal de aspas simples (`@' '@`).
#   - FIXED: Added `external/pjproject/third_party/lib` to `AdditionalLibraryDirectories`
#     to resolve `LNK1181: cannot open input file 'libyuv.lib'` error (this logic is now part of the appending below).
#   - FIXED: Removed trailing comma in `$requiredLibDirs` and other arrays to resolve "Missing expression after ','" ParserError.
#   - NEW: Explicitly APPENDEs required library directories and dependencies to existing ones,
#     instead of replacing the entire node content. This preserves existing necessary paths/libs.
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
        # Set the Condition attribute to the literal string '$(Configuration)|$(Platform)'=='Release|x64'.
        # In PowerShell, this is represented by enclosing it in single quotes and doubling any internal single quotes.
        $itemDefinitionGroupNode.SetAttribute("Condition", '''$(Configuration)|$(Platform)''==''Release|x64''')
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

    # Use a more robust appending method for Includes
    if (-not $additionalIncludeDirsNode) {
        $additionalIncludeDirsNode = $projXml.CreateElement("AdditionalIncludeDirectories", $nsManager.LookupNamespace("msbuild"))
        $clCompileNode.AppendChild($additionalIncludeDirsNode)
        $additionalIncludeDirsNode.'#text' = ($requiredIncludes -join ';') + ";%(AdditionalIncludeDirectories)"
        Write-Host "Added AdditionalIncludeDirectories node with all necessary paths in $ProjFile."
    } else {
        $currentIncludes = $additionalIncludeDirsNode.'#text'.Split(';') | Where-Object { $_ -ne "" } | ForEach-Object { $_.Trim() }
        $finalIncludes = ($requiredIncludes + $currentIncludes) | Select-Object -Unique
        $additionalIncludeDirsNode.'#text' = ($finalIncludes -join ';') + ";%(AdditionalIncludeDirectories)"
        Write-Host "Updated AdditionalIncludeDirectories in $ProjFile to include all necessary paths."
    }

    # Processar Library Directories e Dependencies
    $additionalLibraryDirsNode = $linkerNode.SelectSingleNode("./msbuild:AdditionalLibraryDirectories", $nsManager)
    
    # Define all required library directories relative to microsip.vcxproj
    $requiredLibDirs = @(
        $pjsipLibPathForVcxproj, # This is the absolute path to external/pjproject/lib, converted to relative
        (Join-Path -Path $PjsipIncludeRoot -ChildPath "third_party/lib") | ForEach-Object { [System.IO.Path]::GetRelativePath($microsipProjectDir, $_) } # Path to built third-party libs like libyuv.lib, converted to relative
    )

    # Use a more robust appending method for Library Directories
    if (-not $additionalLibraryDirsNode) {
        $additionalLibraryDirsNode = $projXml.CreateElement("AdditionalLibraryDirectories", $nsManager.LookupNamespace("msbuild"))
        $linkerNode.AppendChild($additionalLibraryDirsNode)
        $additionalLibraryDirsNode.'#text' = ($requiredLibDirs -join ';') + ";%(AdditionalLibraryDirectories)"
        Write-Host "Added AdditionalLibraryDirectories node with all necessary library paths in $ProjFile."
    } else {
        $currentLibDirs = $additionalLibraryDirsNode.'#text'.Split(';') | Where-Object { $_ -ne "" } | ForEach-Object { $_.Trim() }
        $finalLibDirs = ($requiredLibDirs + $currentLibDirs) | Select-Object -Unique
        $additionalLibraryDirsNode.'#text' = ($finalLibDirs -join ';') + ";%(AdditionalLibraryDirectories)"
        Write-Host "Updated AdditionalLibraryDirectories in $ProjFile to include all necessary library paths."
    }

    # Add PJSIP additional dependencies (libraries)
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

    # Use a more robust appending method for Dependencies
    if (-not $additionalDependenciesNode) {
        $additionalDependenciesNode = $projXml.CreateElement("AdditionalDependencies", $nsManager.LookupNamespace("msbuild"))
        $linkerNode.AppendChild($additionalDependenciesNode)
        $additionalDependenciesNode.'#text' = ($pjsipLibs -join ';') + ";%(AdditionalDependencies)"
        Write-Host "Added AdditionalDependencies node with all necessary PJSIP libraries."
    } else {
        $currentDependencies = $additionalDependenciesNode.'#text'.Split(';') | Where-Object { $_ -ne "" } | ForEach-Object { $_.Trim() }
        $finalDependencies = ($pjsipLibs + $currentDependencies) | Select-Object -Unique
        $additionalDependenciesNode.'#text' = ($finalDependencies -join ';') + ";%(AdditionalDependencies)"
        Write-Host "Updated AdditionalDependencies in $ProjFile to include all necessary PJSIP libraries."
    }

    $projXml.Save($ProjFile)
    Write-Host "Successfully patched $ProjFile."
} catch {
    Write-Host "##[error]Error patching $($ProjFile): $($_.Exception.Message)"
    exit 1
}