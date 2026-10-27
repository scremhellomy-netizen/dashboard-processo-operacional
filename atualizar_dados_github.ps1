param([string]$Repositorio = 'https://github.com/scremhellomy-netizen/dashboard-processo-operacional.git')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $root 'erro_atualizacao.log'
$branch = 'master'
function Invoke-GitCommand([string[]]$Arguments) {
    & git.exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Git falhou (codigo $LASTEXITCODE): git $($Arguments -join ' ')" }
}
try {
    Set-Location -LiteralPath $root
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git for Windows nao encontrado.' }
    if (-not (Test-Path -LiteralPath (Join-Path $root '.git'))) {
        throw 'Pasta sem repositorio Git. Clone a branch master do repositorio e coloque os arquivos de origem em dados_para_publicar.'
    }
    $inside = @(& git rev-parse --is-inside-work-tree 2>$null)
    if ($LASTEXITCODE -ne 0 -or @($inside).Count -eq 0 -or "$($inside[0])".Trim() -ne 'true') {
        throw 'Repositorio Git local invalido. Faca um clone limpo da branch master.'
    }
    Invoke-GitCommand @('cat-file','-e','HEAD^{commit}')
    $origin = @(& git remote get-url origin 2>$null)
    if ($LASTEXITCODE -ne 0 -or @($origin).Count -eq 0) { throw 'Remote origin nao configurado.' }
    $originUrl = [string]$origin[0]
    if ($originUrl -notmatch '(?i)(github\.com[:/])scremhellomy-netizen/dashboard-processo-operacional(\.git)?$') {
        throw "Repositorio incorreto: $originUrl"
    }
    $currentBranch = @(& git branch --show-current)
    if ($LASTEXITCODE -ne 0 -or @($currentBranch).Count -eq 0 -or ([string]$currentBranch[0]).Trim() -ne $branch) {
        throw 'Execute a partir da branch master. Nao sera alterada automaticamente.'
    }
    $status = @(& git status --porcelain)
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao consultar git status.' }
    if (@($status).Count -gt 0) {
        throw 'Ha alteracoes locais nao publicadas. Salve ou publique essas alteracoes antes de atualizar, para evitar sobrescrita.'
    }
    Invoke-GitCommand @('pull','--ff-only','origin',$branch)
    $srcDir = Join-Path $root 'dados_para_publicar'
    if (-not (Test-Path -LiteralPath $srcDir)) { throw "Pasta nao encontrada: $srcDir" }
    $files = @(Get-ChildItem -LiteralPath $srcDir -File -Filter '*.json.gz')
    $spec = @(
        @{name='recebimento';system='qualitystorm';dest='recebimento.json.gz'},
        @{name='embalagem';system='qualitystorm';dest='embalagem.json.gz'},
        @{name='armazenagem';system='escalasoft';dest='armazenagem.json.gz'},
        @{name='expedicao';system='escalasoft';dest='expedicao.json.gz'}
    )
    $selected = @()
    foreach ($item in $spec) {
        $matches = @($files | Where-Object {
            $n = $_.BaseName -replace '#U[0-9a-fA-F]{4}',''
            $n = $n.Normalize([Text.NormalizationForm]::FormD)
            $n = [regex]::Replace($n,'\p{Mn}','').ToLowerInvariant()
            $n = [regex]::Replace($n,'[^a-z0-9]','')
            $key = $item.name
            if ($key -eq 'expedicao') { $key = 'expedi' }
            $n.Contains($key) -and $n.Contains($item.system)
        })
        if ($matches.Count -ne 1) { throw "Esperado exatamente um arquivo para $($item.name) / $($item.system). Encontrados: $($matches.Count)." }
        $file = $matches[0]
        $stream = [IO.File]::OpenRead($file.FullName)
        try {
            $gzip = New-Object IO.Compression.GzipStream($stream,[IO.Compression.CompressionMode]::Decompress)
            try {
                $reader = New-Object IO.StreamReader($gzip,[Text.Encoding]::UTF8)
                try {
                    $content = $reader.ReadToEnd()
                    $obj = ConvertFrom-Json -InputObject $content -ErrorAction Stop
                    if ($null -eq $obj.data -or $null -eq $obj.columns) { throw "JSON sem data/columns: $($file.Name)" }
                    Write-Host "Validado: $($file.Name) - $(@($obj.data).Count) registros"
                } finally { $reader.Dispose() }
            } finally { $gzip.Dispose() }
        } finally { $stream.Dispose() }
        $selected += @{src=$file.FullName;dest=$item.dest}
    }
    $dataDir = Join-Path $root 'data'
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
    foreach ($item in $selected) {
        Copy-Item -LiteralPath $item.src -Destination (Join-Path $dataDir $item.dest) -Force
    }
    $manifest = [ordered]@{
        atualizado_em = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        arquivos = @('recebimento.json.gz','embalagem.json.gz','armazenagem.json.gz','expedicao.json.gz')
        origem = 'dados publicados pelo responsavel do dashboard'
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $dataDir 'manifest.json') -Encoding UTF8
    Invoke-GitCommand @('add','data/recebimento.json.gz','data/embalagem.json.gz','data/armazenagem.json.gz','data/expedicao.json.gz','data/manifest.json')
    & git diff --cached --quiet
    if ($LASTEXITCODE -eq 1) {
        Invoke-GitCommand @('commit','-m','Atualiza bases e data de publicacao do dashboard')
        Invoke-GitCommand @('push','origin',$branch)
        Write-Host 'PUBLICACAO CONCLUIDA. Aguarde o GitHub Pages atualizar.' -ForegroundColor Green
    } elseif ($LASTEXITCODE -eq 0) {
        Write-Host 'Nenhuma alteracao detectada.' -ForegroundColor Yellow
    } else { throw 'Falha em git diff --cached.' }
    if (Test-Path $log) { Remove-Item $log -Force }
} catch {
    $msg = "ERRO: $($_.Exception.Message)`r`nLinha: $($_.InvocationInfo.ScriptLineNumber)`r`nComando: $($_.InvocationInfo.Line)`r`n$($_.ScriptStackTrace)"
    $msg | Set-Content -LiteralPath $log -Encoding UTF8
    Write-Host $msg -ForegroundColor Red
    exit 1
}
