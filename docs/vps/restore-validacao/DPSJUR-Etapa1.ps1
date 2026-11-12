# ==============================================================================
# DPSjur - VALIDACAO DE RESTAURACAO - ETAPA 1 (DIAGNOSTICO DO BACKUP)
# Arquivo: docs/vps/restore-validacao/DPSJUR-Etapa1.ps1
# Versao: v1.1.0 (Windows PowerShell 5.1)
#
# v1.1.0: corrige a falha "Nao e possivel localizar uma sobrecarga para
# 'FromBase64String' e a contagem de argumentos: '2'" reportada na etapa [2/5]
# em Windows PowerShell 5.1. Causa: a API do GitHub devolve o campo "content"
# em base64 COM quebras de linha, e o desserializador JSON do PowerShell 5.1
# pode entrega-lo como ARRAY de strings; o "-replace" sobre array devolve
# array, e FromBase64String recebe 2 "argumentos". O campo agora e sempre
# normalizado para UMA string antes do Base64. Nenhuma verificacao de
# integridade foi removida ou afrouxada.
#
# FINALIDADE: executar a ETAPA 1 do README desta pasta (diagnostico somente
# leitura do backup .sql.gz) num unico comando, sem copiar blocos de comandos.
#
# ORIGEM FIXADA: commit b19a532bffe6ae0e069ad9f19e0fae4a9d09db07 do repositorio
# dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl, arquivo
# docs/vps/restore-validacao/01-diagnostico-backup.sh (ja auditado).
#
# ANCORA DE INTEGRIDADE: o script Bash e lido pela API do GitHub nesse commit.
# O identificador de blob Git (SHA-1 de "blob <tamanho>\0" + conteudo) precisa
# ser 884cf88d8bcf1299c5cd81accbde9d92efaacadd, com 8966 bytes. So entao o
# arquivo e baixado de novo pelo raw.githubusercontent.com e comparado byte a
# byte com o conteudo versionado. Qualquer divergencia aborta sem executar.
#
# GARANTIAS (somente leitura):
#   - o diagnostico le apenas o .sql.gz (zcat/grep/md5sum); nada e restaurado;
#   - nao acessa VPS, bancos, EasyPanel nem conteineres Docker (WSL so e usado
#     para bash/gzip/md5sum e para executar o diagnostico);
#   - o backup original nao e modificado nem excluido (o tamanho e conferido
#     antes e depois);
#   - nenhum relatorio ou log anterior e apagado;
#   - nenhuma senha, token ou credencial existe neste arquivo;
#   - nao pede elevacao de administrador, nao instala nada e nao altera a
#     politica de execucao do PowerShell.
#
# COMO EXECUTAR (bypass de politica so para esta invocacao, nao permanente):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\DPSJUR-Etapa1.ps1
#
# TEXTO SEM ACENTOS DE PROPOSITO: o Windows PowerShell 5.1 le .ps1 sem BOM como
# ANSI; mantendo o arquivo em ASCII, as mensagens nao viram caracteres errados.
# ==============================================================================

$ErrorActionPreference = 'Stop'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# ------------------------------------------------------------------------------
# 1. Configuracao
# ------------------------------------------------------------------------------
$dir      = 'C:\Users\dowsp\DPSJUR-Backup-Teste'
$bk       = $dir + '\sbjur_backup_2026-11-11_030001.sql.gz'
$sh       = $dir + '\01-diagnostico-backup.sh'
$wslDir   = '/mnt/c/Users/dowsp/DPSJUR-Backup-Teste'
$wslBk    = $wslDir + '/sbjur_backup_2026-11-11_030001.sql.gz'
$wslSh    = $wslDir + '/01-diagnostico-backup.sh'
$commit   = 'b19a532bffe6ae0e069ad9f19e0fae4a9d09db07'
$blobId   = '884cf88d8bcf1299c5cd81accbde9d92efaacadd'
$blobSize = 8966
$repo     = 'dowspaulo-wq/migra--o-sistema-legal-desk-fg93i2kgl'
$repoPath = 'docs/vps/restore-validacao/01-diagnostico-backup.sh'
$apiUrl   = 'https://api.github.com/repos/' + $repo + '/contents/' + $repoPath + '?ref=' + $commit
$rawUrl   = 'https://raw.githubusercontent.com/' + $repo + '/' + $commit + '/' + $repoPath
$startTime = Get-Date

# ------------------------------------------------------------------------------
# Funcoes auxiliares
# ------------------------------------------------------------------------------
function Fail([string]$msg) {
    Write-Host ''
    Write-Host ('ERRO: ' + $msg) -ForegroundColor Red
    Write-Host 'O backup original nao foi alterado. Se precisar de ajuda, cole esta saida no chat.' -ForegroundColor Yellow
    exit 1
}

function Get-Sha256Hex([byte[]]$data) {
    $alg = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($alg.ComputeHash($data)) -replace '-', '').ToLower() }
    finally { $alg.Dispose() }
}

function Get-Sha1Hex([byte[]]$data) {
    $alg = [System.Security.Cryptography.SHA1]::Create()
    try { return ([System.BitConverter]::ToString($alg.ComputeHash($data)) -replace '-', '').ToLower() }
    finally { $alg.Dispose() }
}

function Test-SameBytes([byte[]]$a, [byte[]]$b) {
    if ($a.Length -ne $b.Length) { return $false }
    for ($i = 0; $i -lt $a.Length; $i++) {
        if ($a[$i] -ne $b[$i]) { return $false }
    }
    return $true
}

# Normaliza um campo de resposta JSON para UMA string unica.
# No Windows PowerShell 5.1, ConvertFrom-Json/Invoke-RestMethod podem entregar
# strings longas com quebras de linha (ex.: o campo "content" em base64 da API
# do GitHub) como ARRAY de strings. Aplicar -replace sobre array devolve array
# e quebra metodos .NET que esperam 1 argumento. Isto junta tudo em uma string,
# tolerando array, colecao de 1 elemento, $null e string simples.
function Get-SingleString($value) {
    if ($null -eq $value) { return '' }
    if ($value -is [System.Array]) { return (@($value) -join '') }
    return [string]$value
}

# Garante caminho ABSOLUTO para metodos .NET ([IO.File]::*): no PowerShell 5.1
# o diretorio corrente do .NET pode diferir do do PowerShell quando o script e
# invocado com caminho relativo.
function Get-AbsolutePath([string]$p) {
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($p)
}

# Roda um comando bash dentro do WSL e devolve o codigo de saida.
# Os comandos passados usam apenas aspas simples (sem aspas duplas), para o
# Windows PowerShell 5.1 repassar os argumentos sem corromper.
function Invoke-Wsl([string]$cmd) {
    & wsl -e bash -c $cmd | Out-Host
    return $LASTEXITCODE
}

try {
    # --------------------------------------------------------------------------
    # 2. Pre-requisitos (aborta sem instalar nem alterar nada)
    # --------------------------------------------------------------------------
    Write-Host '[1/5] Verificando pre-requisitos...' -ForegroundColor Cyan

    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        Fail ('Pasta nao encontrada: ' + $dir + '. Crie a pasta e copie o backup para ela.')
    }
    if (-not (Test-Path -LiteralPath $bk -PathType Leaf)) {
        Fail ('Backup nao encontrado: ' + $bk)
    }
    $bkSizeBefore = (Get-Item -LiteralPath $bk).Length
    Write-Host ('  Pasta OK   : ' + $dir)
    Write-Host ('  Backup OK  : ' + $bk)
    Write-Host ('  Tamanho    : ' + $bkSizeBefore + ' bytes')

    $wslCheck = $null
    try {
        $wslCheck = Invoke-Wsl 'command -v bash >/dev/null && command -v gzip >/dev/null && command -v md5sum >/dev/null && echo WSL_OK'
    } catch {
        Fail 'WSL nao disponivel neste computador (wsl.exe nao respondeu). Instale o WSL2 com uma distribuicao Linux e tente de novo.'
    }
    if ($wslCheck -ne 0) {
        Fail 'WSL disponivel, mas faltam bash, gzip ou md5sum na distribuicao padrao. Nada foi instalado.'
    }
    Write-Host '  WSL OK     : bash, gzip e md5sum encontrados'

    # --------------------------------------------------------------------------
    # 3. Integridade do script Bash, ancorada ao conteudo versionado
    # --------------------------------------------------------------------------
    Write-Host ''
    Write-Host '[2/5] Verificando integridade do script Bash no commit fixado...' -ForegroundColor Cyan
    Write-Host ('  Commit: ' + $commit)

    $headers = @{ 'User-Agent' = 'DPSJUR-Etapa1'; 'Accept' = 'application/vnd.github+json' }
    try {
        $meta = Invoke-RestMethod -Uri $apiUrl -Headers $headers
    } catch {
        Fail ('Nao foi possivel consultar a API do GitHub no commit fixado. Verifique a conexao. Detalhe: ' + $_.Exception.Message)
    }
    if ((Get-SingleString $meta.encoding) -ne 'base64') {
        Fail ('Resposta inesperada da API do GitHub (encoding: ' + (Get-SingleString $meta.encoding) + ').')
    }
    if ([int](Get-SingleString $meta.size) -ne $blobSize) {
        Fail ('Tamanho informado pela API (' + (Get-SingleString $meta.size) + ') difere do fixado (' + $blobSize + ' bytes).')
    }
    if ((Get-SingleString $meta.sha) -ne $blobId) {
        Fail ('Identificador de blob informado pela API (' + (Get-SingleString $meta.sha) + ') difere do fixado (' + $blobId + ').')
    }

    # CORRECAO v1.1.0: o campo "content" (base64 com quebras de linha) pode
    # chegar como ARRAY de strings no PowerShell 5.1; normaliza para UMA
    # string ANTES de limpar espacos e converter para bytes.
    $contentRaw  = Get-SingleString $meta.content
    $contentB64  = ($contentRaw -replace '\s', '')
    if ([string]::IsNullOrEmpty($contentB64)) {
        Fail 'A API do GitHub nao devolveu o conteudo base64 esperado (campo content vazio).'
    }
    $versioned = [System.Convert]::FromBase64String($contentB64)
    if ($versioned.Length -ne $blobSize) {
        Fail ('Conteudo decodificado com ' + $versioned.Length + ' bytes; o esperado e ' + $blobSize + '.')
    }

    # Blob Git: SHA-1 de "blob <tamanho>" + byte 0 + conteudo
    $ms = New-Object System.IO.MemoryStream
    $hdr = [System.Text.Encoding]::ASCII.GetBytes('blob ' + $versioned.Length)
    $ms.Write($hdr, 0, $hdr.Length)
    $ms.WriteByte(0)
    $ms.Write($versioned, 0, $versioned.Length)
    $gitBlob = Get-Sha1Hex ($ms.ToArray())
    $ms.Dispose()
    if ($gitBlob -ne $blobId) {
        Fail ('Blob Git recalculado (' + $gitBlob + ') difere do fixado (' + $blobId + '). Conteudo versionado nao confere; nada foi executado.')
    }

    $expectedSha256 = Get-Sha256Hex $versioned
    Write-Host '  Conteudo versionado conferido:'
    Write-Host ('    tamanho         : ' + $versioned.Length + ' bytes')
    Write-Host ('    blob Git        : ' + $gitBlob)
    Write-Host ('    SHA-256 esperado: ' + $expectedSha256) -ForegroundColor Green

    # Segundo canal: download bruto, conferido contra o conteudo versionado
    $downloaded = $null
    $wc = New-Object System.Net.WebClient
    try {
        $wc.Headers['User-Agent'] = 'DPSJUR-Etapa1'
        $downloaded = $wc.DownloadData($rawUrl)
    } catch {
        Fail ('Nao foi possivel baixar o arquivo bruto do GitHub. Detalhe: ' + $_.Exception.Message)
    } finally {
        $wc.Dispose()
    }

    $downloadedSha256 = Get-Sha256Hex $downloaded
    if (($downloadedSha256 -ne $expectedSha256) -or (-not (Test-SameBytes $downloaded $versioned))) {
        $downloaded = $null
        Fail ('O arquivo baixado difere do conteudo versionado (SHA-256 baixado: ' + $downloadedSha256 + '). Arquivo descartado; nada foi executado.')
    }
    $downloaded = $null
    Write-Host '  Download bruto  : confere byte a byte com o conteudo versionado' -ForegroundColor Green

    $shAbs = Get-AbsolutePath $sh
    [System.IO.File]::WriteAllBytes($shAbs, $versioned)
    Write-Host ('  Script validado gravado em: ' + $sh)

    # --------------------------------------------------------------------------
    # 4. Normalizacao e verificacao de sintaxe (antes de qualquer execucao)
    # --------------------------------------------------------------------------
    Write-Host ''
    Write-Host '[3/5] Normalizando fim de linha e verificando sintaxe (bash -n)...' -ForegroundColor Cyan

    $rc = Invoke-Wsl ("sed -i 's/\r$//' '" + $wslSh + "'")
    if ($rc -ne 0) {
        Fail ('Falha ao normalizar o fim de linha do script no WSL (codigo ' + $rc + '). Cole a saida acima no chat.')
    }

    $rc = Invoke-Wsl ('bash -n ' + $wslSh + ' && echo SINTAXE_OK')
    if ($rc -ne 0) {
        Fail ('bash -n reprovou o script (codigo ' + $rc + '). Nada foi executado. Cole a saida acima no chat.')
    }
    Write-Host '  bash -n: sintaxe OK' -ForegroundColor Green

    # --------------------------------------------------------------------------
    # 5. Execucao do diagnostico (somente leitura sobre o .sql.gz)
    # --------------------------------------------------------------------------
    Write-Host ''
    Write-Host '[4/5] Executando o diagnostico (somente leitura sobre o .sql.gz)...' -ForegroundColor Cyan

    $rc = Invoke-Wsl ('bash ' + $wslSh + ' ' + $wslBk)
    if ($rc -ne 0) {
        Fail ('O diagnostico terminou com codigo ' + $rc + '. Cole a saida acima no chat.')
    }

    # --------------------------------------------------------------------------
    # 6. Relatorio: exibir, manter e abrir; conferir que o backup nao mudou
    # --------------------------------------------------------------------------
    Write-Host ''
    Write-Host '[5/5] Relatorio...' -ForegroundColor Cyan

    $rep = Get-ChildItem -LiteralPath $dir -Filter 'diagnostico-backup-*.txt' |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $rep -or $rep.LastWriteTime -lt $startTime.AddSeconds(-5)) {
        Fail 'Nenhum relatorio diagnostico-backup-*.txt novo foi encontrado na pasta do backup.'
    }

    $bkSizeAfter = (Get-Item -LiteralPath $bk).Length
    if ($bkSizeAfter -ne $bkSizeBefore) {
        Fail 'O tamanho do backup mudou durante a execucao. Pare e cole esta saida no chat.'
    }

    Write-Host ('Relatorio gravado em: ' + $rep.FullName) -ForegroundColor Green
    Write-Host '----- CONTEUDO DO RELATORIO -----'
    Get-Content -LiteralPath $rep.FullName -Encoding UTF8 | Out-Host
    Write-Host '----- FIM DO RELATORIO -----'

    Start-Process -FilePath 'notepad.exe' -ArgumentList $rep.FullName
    Write-Host ''
    Write-Host 'Concluido. O relatorio foi aberto no Bloco de Notas.' -ForegroundColor Green
    Write-Host 'Copie o conteudo do relatorio e cole de volta no chat. Nenhum arquivo anterior foi apagado.'
    exit 0
} catch {
    Fail ('Falha inesperada: ' + $_.Exception.Message)
}
