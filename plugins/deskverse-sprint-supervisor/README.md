# Sprint Supervisor

Plugin independente do Codex para listar, selecionar, planejar e acompanhar
sprints do Deskverse. O chat atual é o supervisor principal e delega a execução
das sprints a subagentes nativos. O script incluído mantém estado, persistência,
recuperação e um runner autônomo legado.

## Instalação por marketplace

```bash
codex plugin marketplace add <URL-OU-CAMINHO-DO-MARKETPLACE>
codex plugin add deskverse-sprint-supervisor@personal
```

Para instalar a partir deste repositório:

```bash
git clone <URL-DO-REPOSITORIO>
cd <DIRETORIO-DO-REPOSITORIO>
codex plugin marketplace add "$PWD"
codex plugin add deskverse-sprint-supervisor@personal
```

## Uso

O supervisor deve ser executado pelo Bash do Git no Windows. O repositório
supervisionado é independente do plugin e deve conter a fila em
`docs/automation/sprint-queue.json` (ou ser informado com `--queue`).

```bash
PLUGIN_ROOT="/c/caminho/para/plugin"
bash "$PLUGIN_ROOT/scripts/codex/sprint-supervisor.sh" \
  --mode list --repository "$PWD"
```

O controlador padrão é `chat`. Ele valida o repositório, reconcilia sprints
concluídas, seleciona a próxima sprint e grava um plano/handoff persistido para
o supervisor da conversa. Mesmo com `--mode run`, o controlador `chat` nunca
executa `codex exec`.

```bash
# Preparar o próximo handoff
bash "$PLUGIN_ROOT/scripts/codex/sprint-supervisor.sh" \
  --mode plan --controller chat --repository "$PWD"

# Preparar handoff e iniciar o fluxo conversacional
bash "$PLUGIN_ROOT/scripts/codex/sprint-supervisor.sh" \
  --mode run --controller chat --sprints 02d --repository "$PWD"

# Reconciliar conclusões sem executar sprint
bash "$PLUGIN_ROOT/scripts/codex/sprint-supervisor.sh" \
  --mode reconcile --controller chat --repository "$PWD"
```

Após receber o handoff, o chat delega a sprint a um subagente nativo, exige
descrições com no máximo cinco palavras, escala reasoning até `xhigh` quando
necessário, valida testes e navegador, permite commit somente após a validação
e continua para as demais sprints selecionadas.

O modelo do supervisor é sempre o modelo desta conversa. A fila mantém a
configuração `codex.subagents.model` e `codex.subagents.reasoning_effort` para
os subagentes nativos. `codex.model` e `codex.reasoning_effort` são lidos
somente pelo runner legado.

## Runner autônomo legado

Para preservar a execução autônoma existente, opte explicitamente por
`--controller runner`:

```bash
bash "$PLUGIN_ROOT/scripts/codex/sprint-supervisor.sh" \
  --mode run --controller runner --sprints 02d --repository "$PWD"
```

Somente esse modo inicia `codex exec`. `--loop`, `--model` e
`--reasoning-effort` pertencem ao runner legado. Use `codex plugin list` para
localizar a versão instalada e obter o caminho absoluto do script.

Cada pessoa deve autenticar sua própria conta Codex e configurar suas próprias
contas OpenAI. Não inclua tokens, sessões ou arquivos de credenciais no Git.
