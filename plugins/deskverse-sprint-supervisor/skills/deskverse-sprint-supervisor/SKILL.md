---
name: deskverse-sprint-supervisor
description: Use when the user wants to list, select, execute, resume, monitor, or message Deskverse sprints through the local supervisor.
---

# Sprint Supervisor

Este plugin é independente do projeto que será supervisionado. O pacote inclui
o supervisor em `scripts/codex/sprint-supervisor.sh`; o repositório-alvo é
informado por `--repository` (ou é o diretório atual). O arquivo de fila deve
existir no repositório-alvo em `docs/automation/sprint-queue.json`, ou ser
indicado com `--queue`.

Após instalar o plugin, localize a pasta instalada com `codex plugin list` e
use o caminho absoluto do script incluído. Exemplo:

```bash
PLUGIN_ROOT="/c/Users/<usuario>/.codex/plugins/cache/<marketplace>/deskverse-sprint-supervisor/<versao>"
bash "$PLUGIN_ROOT/scripts/codex/sprint-supervisor.sh" --mode status \
  --repository "$PWD"
```

Em um checkout do plugin, o caminho equivalente é
`plugins/deskverse-sprint-supervisor/scripts/codex/sprint-supervisor.sh`.

## Preflight obrigatório

O supervisor é um script Bash, não um script POSIX `sh`. No Windows, sempre
valide e invoque o arquivo com o Bash do Git:

```bash
bash -n "$PLUGIN_ROOT/scripts/codex/sprint-supervisor.sh"
bash "$PLUGIN_ROOT/scripts/codex/sprint-supervisor.sh" --mode status --repository "$PWD"
```

Não use `sh`, `pwsh -File`, `cmd` ou uma chamada direta que faça outro
interpretador analisar o arquivo. Isso pode quebrar construções Bash, como
`[[ ... ]]`, agrupamentos e heredocs, produzindo erros de sintaxe perto de
parênteses que não existem no código executado pelo Bash.

## Seleção conversacional

Antes de iniciar ou retomar qualquer sprint:

1. Leia `AGENTS.md`, `docs/memoria-codex.md` e
   `docs/automation/sprint-queue.json`.
2. Consulte a fila real:

   ```bash
   bash "$PLUGIN_ROOT/scripts/codex/sprint-supervisor.sh" --mode list --repository "$PWD"
   ```

3. Mostre ao usuário os itens retornados, com ID, título, tamanho, status e
   dependências. Não invente IDs nem mantenha uma seleção hardcoded.
4. Pergunte quais IDs devem ser executados. Preserve a ordem informada pelo
   usuário; o supervisor ainda valida dependências e orçamento.
5. Execute apenas a seleção confirmada:

   ```bash
   # Uma sprint
   bash "$PLUGIN_ROOT/scripts/codex/sprint-supervisor.sh" --mode run \
     --sprints 02d --repository "$PWD"

   # Várias sprints, em sequência, mantendo o loop nativo
   bash "$PLUGIN_ROOT/scripts/codex/sprint-supervisor.sh" --mode run \
     --sprints 02d,02e --loop --repository "$PWD"
   ```

IDs também podem ser passados repetindo `--sprint`. Use `--sprints all` apenas
quando o usuário pedir a fila automática completa.

## Acompanhamento e intervenção

- `--mode status` mostra o estado persistido, a sprint atual, pausas, agentes e
  a última mensagem.
- `--mode dry-run --sprints ID[,ID...]` valida a seleção sem iniciar o Codex.
- `--mode message --message "..."` enfileira uma instrução para a próxima
  fronteira segura; não interrompa o turno atual para injetá-la.
- Para acompanhar subagentes, leia o status/log persistido e comunique mudanças
  relevantes, erros resumidos e a ação em andamento em até cinco palavras.

O supervisor continua responsável por dependências, orçamento, compactação de
contexto, rotação de contas, commits, push e validação no navegador. Não
declare uma sprint concluída sem os marcadores, commit e gates exigidos por
`AGENTS.md`.

## Limitação da interface

O manifesto de plugin fornece ativação conversacional, mas não cria checkboxes
arbitrários nativos no Codex. A seleção nesta versão é feita informando os IDs
no chat. Uma checklist clicável exigiria uma extensão MCP ou um painel local
separado; não simule essa interface com IDs fixos.
