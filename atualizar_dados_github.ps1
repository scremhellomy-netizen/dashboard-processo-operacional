param([string]$Repositorio = "")
$ErrorActionPreference="Stop"
if(-not (Get-Command git -ErrorAction SilentlyContinue)){throw "Git não foi encontrado."}
if(-not (Get-Command gh -ErrorAction SilentlyContinue)){throw "GitHub CLI (gh) não foi encontrado."}
gh auth status
if($LASTEXITCODE -ne 0){throw "Faça login com: gh auth login"}
$required=@(
"Recebimento - QualityStorm.json.gz",
"Embalagem - QualityStorm.json(1).gz",
"Armazenagem - EscalaSoft.json(2).gz",
"Expedição - EscalaSoft.json.gz")
$map=@{
"Recebimento - QualityStorm.json.gz"="recebimento.json.gz"
"Embalagem - QualityStorm.json(1).gz"="embalagem.json.gz"
"Armazenagem - EscalaSoft.json(2).gz"="armazenagem.json.gz"
"Expedição - EscalaSoft.json.gz"="expedicao.json.gz"}
New-Item -ItemType Directory -Force -Path "data" | Out-Null
foreach($name in $required){$src=Join-Path "dados_para_publicar" $name;if(-not(Test-Path $src)){throw "Arquivo obrigatório não encontrado: $src"};Copy-Item $src (Join-Path "data" $map[$name]) -Force}
$manifest = [ordered]@{atualizado_em=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ");arquivos=@("recebimento.json.gz","embalagem.json.gz","armazenagem.json.gz","expedicao.json.gz");origem="dados publicados pelo responsável do dashboard"} 
$manifest | ConvertTo-Json -Depth 5 | Set-Content "data/manifest.json" -Encoding UTF8
if(-not(Test-Path ".git")){git init;git branch -M main}
if($Repositorio -eq ""){$Repositorio=git remote get-url origin 2>$null}
if([string]::IsNullOrWhiteSpace($Repositorio)){throw "Informe o repositório com -Repositorio ou configure o remote origin."}
if(-not (git remote get-url origin 2>$null)){git remote add origin $Repositorio}
git add index.html data .github README.md ORIENTACOES_CARREGAMENTO.md .gitignore
git commit -m "Atualiza dados publicados do dashboard"
if($LASTEXITCODE -eq 0){git push origin main;Write-Host "Dados publicados. O GitHub Actions fará o deploy." -ForegroundColor Green}else{Write-Host "Nenhuma alteração para publicar." -ForegroundColor Yellow}
