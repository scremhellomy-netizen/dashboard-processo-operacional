param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $root 'erro_atualizacao.log'
$branch = 'master'
$expectedRemote = 'scremhellomy-netizen/dashboard-processo-operacional'
$publishPaths = @('data/recebimento.json.gz','data/embalagem.json.gz','data/armazenagem.json.gz','data/expedicao.json.gz','data/manifest.json')
$backup = $null
$cleanedLocalData = $false
$published = $false

function Invoke-Git {
    param([Parameter(Mandatory=$true)][string[]]$GitArgs)
    $result = @(& git.exe @GitArgs 2>&1)
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "git $($GitArgs -join ' ') falhou ($code): $($result -join ' ')" }
    return $result
}
function Normalize-Name([string]$name) {
    $name = [regex]::Replace($name, '#U([0-9a-fA-F]{4})', { param($m) [char][Convert]::ToInt32($m.Groups[1].Value,16) })
    $name = $name.Normalize([Text.NormalizationForm]::FormD)
    $name = [regex]::Replace($name,'\p{Mn}','')
    return [regex]::Replace($name.ToLowerInvariant(),'[^a-z0-9]','')
}
try {
    Set-Location -LiteralPath $root
    Write-Host '=== Atualizacao automatica do Dashboard de Processo Operacional ===' -ForegroundColor Cyan
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { throw 'Git for Windows nao encontrado no PATH.' }
    if (-not (Test-Path -LiteralPath (Join-Path $root '.git'))) { throw 'Pasta .git nao encontrada. Use a pasta clonada do repositorio.' }
    $inside = [string]((Invoke-Git -GitArgs @('rev-parse','--is-inside-work-tree') | Select-Object -First 1))
    if ($inside.Trim() -ne 'true') { throw 'Repositorio Git invalido.' }
    Invoke-Git -GitArgs @('cat-file','-e','HEAD^{commit}') | Out-Null
    $origin = [string]((Invoke-Git -GitArgs @('remote','get-url','origin') | Select-Object -First 1))
    if ($origin -notmatch '(?i)github\.com[:/]scremhellomy-netizen/dashboard-processo-operacional(?:\.git)?/?$') { throw "Remote origin inesperado: $origin" }
    $currentBranch = [string]((Invoke-Git -GitArgs @('branch','--show-current') | Select-Object -First 1))
    if ($currentBranch.Trim() -ne $branch) { throw "Branch incorreta: $currentBranch (esperado: master)." }
    if (Test-Path (Join-Path $root '.git/rebase-merge')) { throw 'Rebase em andamento. Resolva-o antes de executar o BAT.' }
    if (Test-Path (Join-Path $root '.git/rebase-apply')) { throw 'Rebase em andamento. Resolva-o antes de executar o BAT.' }
    if (Test-Path (Join-Path $root '.git/MERGE_HEAD')) { throw 'Merge em andamento. Resolva-o antes de executar o BAT.' }

    $srcDir = Join-Path $root 'dados_para_publicar'
    if (-not (Test-Path -LiteralPath $srcDir -PathType Container)) { throw "Pasta de origem ausente: $srcDir" }
    $sources = @(Get-ChildItem -LiteralPath $srcDir -File -Filter '*.json.gz')
    $spec = @(
        @{key='recebimento';system='qualitystorm';dest='recebimento.json.gz'},
        @{key='embalagem';system='qualitystorm';dest='embalagem.json.gz'},
        @{key='armazenagem';system='escalasoft';dest='armazenagem.json.gz'},
        @{key='expedicao';system='escalasoft';dest='expedicao.json.gz'}
    )
    $selected = @()
    foreach ($item in $spec) {
        $matches = @($sources | Where-Object {
            $n = Normalize-Name $_.Name
            $n.Contains($item.key) -and $n.Contains($item.system)
        })
        if ($matches.Count -ne 1) { throw "Esperado 1 arquivo $($item.key) / $($item.system), encontrados $($matches.Count)." }
        $f = $matches[0]
        $fs = [IO.File]::OpenRead($f.FullName)
        try {
            $gz = New-Object IO.Compression.GzipStream($fs,[IO.Compression.CompressionMode]::Decompress)
            try {
                $reader = New-Object IO.StreamReader($gz,[Text.Encoding]::UTF8)
                try {
                    $obj = ConvertFrom-Json -InputObject $reader.ReadToEnd() -ErrorAction Stop
                    if ($null -eq $obj.columns -or $null -eq $obj.data) { throw "Estrutura JSON invalida: $($f.Name)" }
                    Write-Host "OK: $($f.Name) - $(@($obj.data).Count) registros"
                } finally { $reader.Dispose() }
            } finally { $gz.Dispose() }
        } finally { $fs.Dispose() }
        $selected += @{src=$f.FullName;dest=$item.dest}
    }

    # Apenas os cinco arquivos publicados podem estar modificados.
    # Logs e arquivos ignorados (inclusive dados_para_publicar) nao bloqueiam.
    $status = @(Invoke-Git -GitArgs @('status','--porcelain','--untracked-files=no'))
    $allowed = @{}
    foreach ($p in $publishPaths) { $allowed[$p] = $true }
    foreach ($line in $status) {
        if ($line.Length -lt 4) { continue }
        $path = $line.Substring(3).Trim('"') -replace '\\','/'
        if ($line.Substring(0,2) -match 'U|AA|DD' -or $path -notin $publishPaths) {
            throw "Alteracao Git fora das bases publicadas: $line. Publique/resolva manualmente antes de continuar."
        }
    }

    # Backup persistente das bases locais antes de sincronizar; nao remove dados originais.
    $dataDir = Join-Path $root 'data'
    $backup = Join-Path $root ('.backup_publicacao_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    foreach ($p in $publishPaths) {
        $local = Join-Path $root ($p -replace '/', [IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $local) { Copy-Item -LiteralPath $local -Destination (Join-Path $backup ([IO.Path]::GetFileName($local))) -Force }
    }
    Write-Host "Backup de seguranca: $backup"

    # Permite atualizar quando os JSON publicados estao alterados localmente.
    # As fontes originais em dados_para_publicar permanecem intocadas.
    if ($status.Count -gt 0) {
        Invoke-Git -GitArgs (@('restore','--staged','--worktree','--') + $publishPaths) | Out-Null
        $cleanedLocalData = $true
    }
    Invoke-Git -GitArgs @('pull','--ff-only','origin',$branch) | Out-Null
    Write-Host 'Repositorio sincronizado com origin/master.'

    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    foreach ($item in $selected) {
        Copy-Item -LiteralPath $item.src -Destination (Join-Path $dataDir $item.dest) -Force
    }
    $manifest = [ordered]@{
        atualizado_em = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        arquivos = @('recebimento.json.gz','embalagem.json.gz','armazenagem.json.gz','expedicao.json.gz')
        origem = 'dados publicados pelo responsavel do dashboard'
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $dataDir 'manifest.json') -Encoding UTF8
    Invoke-Git -GitArgs (@('add','--') + $publishPaths) | Out-Null
    & git.exe diff --cached --quiet -- @publishPaths
    $diffCode = $LASTEXITCODE
    if ($diffCode -eq 1) {
        Invoke-Git -GitArgs @('commit','-m','Atualiza bases operacionais do dashboard') | Out-Null
        Invoke-Git -GitArgs @('push','origin',$branch) | Out-Null
        $published = $true
        Write-Host 'SUCESSO: bases e manifest publicados na branch master.' -ForegroundColor Green
    } elseif ($diffCode -eq 0) {
        $published = $true
        Write-Host 'Sem diferencas para publicar.' -ForegroundColor Yellow
    } else { throw "Erro ao comparar arquivos staged (codigo $diffCode)." }
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    Write-Host "Backup local mantido em: $backup"
    exit 0
} catch {
    $msg = "ERRO: $($_.Exception.Message)`r`nLinha: $($_.InvocationInfo.ScriptLineNumber)`r`nComando: $($_.InvocationInfo.Line)`r`n$($_.ScriptStackTrace)"
    $msg | Set-Content -LiteralPath $log -Encoding UTF8
    Write-Host $msg -ForegroundColor Red
    if ($backup) { Write-Host "Backup de seguranca (nao apagar): $backup" -ForegroundColor Yellow }
    Write-Host 'Nenhum push foi confirmado nesta execucao.' -ForegroundColor Yellow
    exit 1
}
