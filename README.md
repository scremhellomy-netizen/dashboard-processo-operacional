# Dashboard de processo operacional

Esta versão publica o dashboard já acompanhado do último snapshot dos quatro processos.

## Como funciona

Ao acessar o GitHub Pages, o `index.html` carrega automaticamente:

- `data/recebimento.json.gz`
- `data/embalagem.json.gz`
- `data/armazenagem.json.gz`
- `data/expedicao.json.gz`

O visitante não precisa selecionar arquivos.

O botão **Atualizar dados** recarrega o snapshot publicado. A seleção manual continua disponível para testes locais.

## Como atualizar os dados

1. Gere os quatro JSON.GZ pelo conversor.
2. Substitua os quatro arquivos em `dados_para_publicar`.
3. Execute `atualizar_dados_github.bat`.
4. O script copia os dados para `data/`, atualiza a data no `manifest.json` e faz `git push`.
5. O GitHub Actions publica a nova versão.

## Filtro mensal

- Recebimento → `Início`
- Embalagem → `inicio`
- Armazenagem → `ENTRADA`
- Expedição → `DATA_ALT`

## Atenção sobre confidencialidade

Os JSON.GZ em `data/` são parte da publicação. Portanto, quem conseguir acessar o site poderá receber os dados publicados. Se os arquivos contiverem informações internas, números de série, clientes ou outros dados confidenciais, não use um GitHub Pages público. O GitHub informa que repositórios públicos são acessíveis a todos e que a disponibilidade/privacidade do GitHub Pages depende do plano e da organização.
