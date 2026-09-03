# Sprint Supervisor

Plugin do Codex para executar e acompanhar sprints em sequência, com seleção,
loop, compactação de contexto, rotação de contas, commits, push e validação no
navegador.

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
bash /c/caminho/para/plugin/scripts/codex/sprint-supervisor.sh \
  --mode list --repository "$PWD"
```

Use `codex plugin list` para localizar a versão instalada e obter o caminho
absoluto de `scripts/codex/sprint-supervisor.sh`.

Cada pessoa deve autenticar sua própria conta Codex e configurar suas próprias
contas OpenAI. Não inclua tokens, sessões ou arquivos de credenciais no Git.
