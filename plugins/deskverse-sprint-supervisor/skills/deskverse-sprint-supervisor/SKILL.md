---
name: deskverse-sprint-supervisor
description: Use when the user wants to list, select, plan, execute, reconcile, resume, monitor, or message Deskverse sprints through the local supervisor.
---

# Sprint Supervisor

Este plugin é independente do projeto supervisionado. O chat atual é o
supervisor principal; os subagentes nativos do Codex executam as sprints. O
script Bash é um runner auxiliar de estado, persistência, recuperação e
compatibilidade com execução autônoma.

O repositório-alvo é informado por `--repository` (ou é o diretório atual). A
fila deve existir no repositório-alvo em `docs/automation/sprint-queue.json`, ou
ser indicada com `--queue`.

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

Antes de iniciar ou retomar qualquer sprint, o supervisor do chat deve ler:

1. `AGENTS.md`;
2. `docs/memoria-codex.md`;
3. `docs/automation/sprint-queue.json`;
4. o documento da sprint selecionada e suas dependências.

O supervisor é um script Bash, não um script POSIX `sh`. No Windows, sempre
valide e invoque o arquivo com o Bash do Git:

```bash
bash -n "$PLUGIN_ROOT/scripts/codex/sprint-supervisor.sh"
bash "$PLUGIN_ROOT/scripts/codex/sprint-supervisor.sh" --mode status --repository "$PWD"
```

Não use `sh`, `pwsh -File`, `cmd` ou uma chamada direta que faça outro
interpretador analisar o arquivo.

## Fluxo principal: supervisor do chat

`--controller chat` é o padrão. No modo `run`, o script valida o repositório,
reconcilia sprints concluídas, seleciona a próxima sprint elegível, persiste o
estado e grava um plano/handoff para esta conversa. Ele nunca inicia `codex
exec`.

Use a fila real para apresentar a seleção ao usuário:

```bash
bash "$PLUGIN_ROOT/scripts/codex/sprint-supervisor.sh" --mode list \
  --repository "$PWD"
```

Mostre ID, título, tamanho, status e dependências. Pergunte quais IDs o usuário
quer executar, preserve a ordem informada e execute somente a seleção
confirmada. Use `--sprints all` apenas quando o usuário pedir a fila automática
completa.

Para preparar o próximo handoff sem avançar a execução:

```bash
bash "$PLUGIN_ROOT/scripts/codex/sprint-supervisor.sh" --mode plan \
  --repository "$PWD"
```

Para preparar e iniciar o ciclo conversacional:

```bash
bash "$PLUGIN_ROOT/scripts/codex/sprint-supervisor.sh" --mode run \
  --controller chat --sprints 02d --repository "$PWD"
```

Depois que o script entregar o handoff, o supervisor do chat deve delegar a
sprint a um subagente nativo. O supervisor não implementa a sprint diretamente
quando a delegação nativa estiver disponível.

Para cada sprint delegada, o supervisor do chat deve:

- iniciar o subagente com o modelo e reasoning configurados em
  `codex.subagents` na fila;
- usar descrições/mensagens de progresso com no máximo cinco palavras;
- escalar o reasoning em caso de falha, bloqueio ou resultado insuficiente,
  seguindo a escada configurada até `xhigh`;
- exigir que o subagente leia `AGENTS.md`, `docs/memoria-codex.md` e o documento
  da sprint antes de editar;
- validar testes aplicáveis e o navegador após cada sprint que altere produto
  ou interface;
- permitir commit somente depois de todos os gates e critérios de aceite;
- reconciliar o estado e continuar para as demais sprints confirmadas.

O subagente deve atualizar o status do documento, registrar a memória
operacional exigida e criar o commit atômico da sprint. Nunca declare conclusão
sem esses marcadores e sem validação real.

O modelo e o reasoning do supervisor são os do modelo desta conversa. A
configuração `codex.model`/`codex.reasoning_effort` da fila é usada somente pelo
runner legado, nunca para escolher o modelo do supervisor do chat.

## Runner legado

O fluxo autônomo existente permanece disponível apenas com
`--controller runner`:

```bash
bash "$PLUGIN_ROOT/scripts/codex/sprint-supervisor.sh" --mode run \
  --controller runner --sprints 02d --repository "$PWD"
```

Somente esse controlador pode iniciar `codex exec`, aplicar a rotação de contas,
compactação e demais políticas autônomas. `--model` e `--reasoning-effort` são
substituições do runner legado; em `chat`, o script rejeita essas opções.
`--loop` também exige `--controller runner`.

## Acompanhamento e intervenção

- `--mode status` mostra supervisor do chat ou runner legado, subagentes,
  sprint atual, pausas, handoff persistido e última mensagem.
- `--mode reconcile` reconcilia documentos concluídos com o estado persistido
  sem executar uma sprint.
- `--mode dry-run --sprints ID[,ID...]` valida a seleção sem iniciar Codex.
- `--mode message --message "..."` enfileira uma instrução para a próxima
  fronteira segura; não interrompa um turno ativo para injetá-la.
- `--mode list` apresenta a fila sem iniciar Codex.

O supervisor do chat continua responsável por dependências, orçamento,
compactação, commits, push e validação no navegador. No runner legado, essas
responsabilidades são exercidas pelo próprio processo autônomo conforme a fila.

## Limitação da interface

O manifesto fornece ativação conversacional, mas não cria checkboxes arbitrários
nativos no Codex. A seleção é feita informando IDs no chat. Uma checklist
clicável exigiria uma extensão MCP ou um painel local separado; não simule essa
interface com IDs fixos.
