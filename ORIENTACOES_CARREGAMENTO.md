# Orientações

## Usuários do dashboard

Não precisam carregar arquivos. O site carrega automaticamente os quatro snapshots publicados.

## Responsável pela atualização

Coloque em `dados_para_publicar`:

- `Recebimento - QualityStorm.json.gz`
- `Embalagem - QualityStorm.json(1).gz`
- `Armazenagem - EscalaSoft.json(2).gz`
- `Expedição - EscalaSoft.json.gz`

Depois execute `atualizar_dados_github.bat`.

O script atualizará `data/` e fará o push para `main`.

## Teste local

Ao abrir o HTML via `file://`, o navegador pode bloquear o carregamento automático dos arquivos `data/`. Nesse caso, use um servidor local ou selecione manualmente os quatro arquivos.
