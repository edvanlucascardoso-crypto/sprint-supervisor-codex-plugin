#!/usr/bin/env bash
set -Eeuo pipefail

# Este arquivo usa recursos específicos do Bash. No Windows, invoque-o pelo
# Git Bash ("bash script.sh"), nunca por sh, cmd ou PowerShell.

# Supervisor serial de sprints para Git Bash no Windows.
# A persistência fica fora do checkout para sobreviver a novas execuções.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# O supervisor é distribuível: o repositório-alvo é o diretório atual por
# padrão, e pode ser sobrescrito explicitamente com --repository.
REPO_ROOT="$(pwd -P)"
QUEUE_PATH="$REPO_ROOT/docs/automation/sprint-queue.json"
STATE_ROOT=""
MODE="run"
MODE_EXPLICIT="false"
SPRINTS_OVERRIDE=""
PAUSE_HOURS=5
PUSH_MODE_OVERRIDE=""
PUSH_EVERY_OVERRIDE=""
MODEL_OVERRIDE=""
REASONING_OVERRIDE=""
SUBAGENT_MODEL_OVERRIDE=""
SUBAGENT_REASONING_OVERRIDE=""
ACCOUNT_OVERRIDE=""
AUTO_COMMIT_OVERRIDE=""
COMPACTION_ENABLED_OVERRIDE=""
COMPACTION_LIMIT_OVERRIDE=""
COMPACTION_SCOPE_OVERRIDE=""
LOOP_ENABLED="false"
LOOP_CHILD="false"
LOOP_INTERVAL="300"
ACCOUNTS_JSON='{"enabled":false,"profiles":[]}'
ACCOUNT_ROTATION_ENABLED="false"
ACTIVE_ACCOUNT_ID=""
ACTIVE_CODEX_HOME=""
MESSAGE_TEXT=""
MESSAGE_FILE=""

ORIGINAL_ARGS=("$@")

usage() {
  cat <<'EOF'
Uso: sprint-supervisor.sh [--mode run|dry-run|reset-pause|status|list|message] [--repository PATH]
                          [--queue PATH] [--state-root PATH] [--pause-hours N]
                          [--sprints ID[,ID...]] [--sprint ID]
                          [--push-on never|sprint|commits|both] [--push-every N]
                          [--model MODEL] [--reasoning-effort LEVEL]
                          [--subagent-model MODEL] [--subagent-reasoning-effort LEVEL]
                          [--account ACCOUNT_ID]
                          [--auto-commit-dirty|--no-auto-commit-dirty]
                          [--auto-compact|--no-auto-compact] [--compact-token-limit N]
                          [--loop] [--loop-interval SECONDS]
                          [--message TEXT|--message-file PATH]

Enviar uma mensagem para a execução ativa (não interrompe o turno atual):
  sprint-supervisor.sh --mode message --message "instrução para o supervisor"
  sprint-supervisor.sh --send-message "instrução para o supervisor"

Listar a fila e as sprints ainda pendentes:
  sprint-supervisor.sh --mode list
EOF
}

while (($#)); do
  case "$1" in
    --mode) [[ $# -ge 2 ]] || { echo 'Falta valor para --mode.' >&2; exit 2; }; MODE="${2,,}"; MODE_EXPLICIT="true"; shift 2 ;;
    --repository) [[ $# -ge 2 ]] || { echo 'Falta valor para --repository.' >&2; exit 2; }; REPO_ROOT="$(cd "$2" && pwd)"; shift 2 ;;
    --sprints) [[ $# -ge 2 ]] || { echo 'Falta valor para --sprints.' >&2; exit 2; }; SPRINTS_OVERRIDE="$2"; shift 2 ;;
    --sprint) [[ $# -ge 2 ]] || { echo 'Falta valor para --sprint.' >&2; exit 2; }; if [[ -n "$SPRINTS_OVERRIDE" ]]; then SPRINTS_OVERRIDE+=",$2"; else SPRINTS_OVERRIDE="$2"; fi; shift 2 ;;
    --queue) [[ $# -ge 2 ]] || { echo 'Falta valor para --queue.' >&2; exit 2; }; QUEUE_PATH="$2"; shift 2 ;;
    --state-root) [[ $# -ge 2 ]] || { echo 'Falta valor para --state-root.' >&2; exit 2; }; STATE_ROOT="$2"; shift 2 ;;
    --pause-hours) [[ $# -ge 2 ]] || { echo 'Falta valor para --pause-hours.' >&2; exit 2; }; PAUSE_HOURS="$2"; shift 2 ;;
    --push-on) [[ $# -ge 2 ]] || { echo 'Falta valor para --push-on.' >&2; exit 2; }; PUSH_MODE_OVERRIDE="${2,,}"; shift 2 ;;
    --push-every) [[ $# -ge 2 ]] || { echo 'Falta valor para --push-every.' >&2; exit 2; }; PUSH_EVERY_OVERRIDE="$2"; shift 2 ;;
    --push) PUSH_MODE_OVERRIDE="sprint"; shift ;;
    --no-push) PUSH_MODE_OVERRIDE="never"; shift ;;
    --model) [[ $# -ge 2 ]] || { echo 'Falta valor para --model.' >&2; exit 2; }; MODEL_OVERRIDE="$2"; shift 2 ;;
    --reasoning-effort|--effort) [[ $# -ge 2 ]] || { echo 'Falta valor para --reasoning-effort.' >&2; exit 2; }; REASONING_OVERRIDE="$2"; shift 2 ;;
    --subagent-model) [[ $# -ge 2 ]] || { echo 'Falta valor para --subagent-model.' >&2; exit 2; }; SUBAGENT_MODEL_OVERRIDE="$2"; shift 2 ;;
    --subagent-reasoning-effort|--subagent-effort) [[ $# -ge 2 ]] || { echo 'Falta valor para --subagent-reasoning-effort.' >&2; exit 2; }; SUBAGENT_REASONING_OVERRIDE="$2"; shift 2 ;;
    --account) [[ $# -ge 2 ]] || { echo 'Falta valor para --account.' >&2; exit 2; }; ACCOUNT_OVERRIDE="$2"; shift 2 ;;
    --auto-commit-dirty) AUTO_COMMIT_OVERRIDE="true"; shift ;;
    --no-auto-commit-dirty) AUTO_COMMIT_OVERRIDE="false"; shift ;;
    --auto-compact) COMPACTION_ENABLED_OVERRIDE="true"; shift ;;
    --no-auto-compact) COMPACTION_ENABLED_OVERRIDE="false"; shift ;;
    --compact-token-limit) [[ $# -ge 2 ]] || { echo 'Falta valor para --compact-token-limit.' >&2; exit 2; }; COMPACTION_LIMIT_OVERRIDE="$2"; shift 2 ;;
    --loop) LOOP_ENABLED="true"; shift ;;
    --loop-interval) [[ $# -ge 2 ]] || { echo 'Falta valor para --loop-interval.' >&2; exit 2; }; LOOP_INTERVAL="$2"; shift 2 ;;
    --loop-child) LOOP_CHILD="true"; shift ;;
    --message) [[ $# -ge 2 ]] || { echo 'Falta valor para --message.' >&2; exit 2; }; MESSAGE_TEXT="$2"; [[ "$MODE_EXPLICIT" == "true" ]] || MODE="message"; shift 2 ;;
    --message-file) [[ $# -ge 2 ]] || { echo 'Falta valor para --message-file.' >&2; exit 2; }; MESSAGE_FILE="$2"; [[ "$MODE_EXPLICIT" == "true" ]] || MODE="message"; shift 2 ;;
    --send-message) [[ $# -ge 2 ]] || { echo 'Falta valor para --send-message.' >&2; exit 2; }; MESSAGE_TEXT="$2"; MODE="message"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Argumento desconhecido: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$MODE" in
  run|dry-run|reset-pause|status|list|message) ;;
  *) echo "Modo inválido: $MODE" >&2; exit 2 ;;
esac

if ! [[ "$PAUSE_HOURS" =~ ^[0-9]+$ ]] || (( PAUSE_HOURS <= 0 )); then
  echo '--pause-hours deve ser um inteiro positivo.' >&2
  exit 2
fi

if [[ "$MODE" == "message" ]]; then
  if [[ -n "$MESSAGE_FILE" ]]; then
    [[ -f "$MESSAGE_FILE" ]] || { echo "Arquivo de mensagem não encontrado: $MESSAGE_FILE" >&2; exit 2; }
    MESSAGE_TEXT="$(<"$MESSAGE_FILE")"
  fi
  if [[ -z "${MESSAGE_TEXT//[[:space:]]/}" ]]; then
    echo 'Informe --message TEXT ou --message-file PATH.' >&2
    exit 2
  fi
fi
if [[ -n "$SPRINTS_OVERRIDE" ]] && ! [[ "$SPRINTS_OVERRIDE" =~ ^[[:space:]]*(all|[0-9]+[a-z]?)([[:space:]]*,[[:space:]]*(all|[0-9]+[a-z]?))*[[:space:]]*$ ]]; then
  echo '--sprints deve conter IDs separados por vírgula (ex.: 01,02a) ou all.' >&2
  exit 2
fi
if ! [[ "$LOOP_INTERVAL" =~ ^[0-9]+$ ]]; then
  echo '--loop-interval deve ser um inteiro não negativo (segundos).' >&2
  exit 2
fi
if [[ "$LOOP_ENABLED" == "true" && "$MODE" != "run" ]]; then
  echo '--loop só pode ser usado com --mode run.' >&2
  exit 2
fi
if [[ -n "$PUSH_MODE_OVERRIDE" ]] && [[ "$PUSH_MODE_OVERRIDE" != "never" && "$PUSH_MODE_OVERRIDE" != "sprint" && "$PUSH_MODE_OVERRIDE" != "commits" && "$PUSH_MODE_OVERRIDE" != "both" ]]; then
  echo '--push-on deve ser never, sprint, commits ou both.' >&2
  exit 2
fi
if [[ -n "$PUSH_EVERY_OVERRIDE" ]] && { ! [[ "$PUSH_EVERY_OVERRIDE" =~ ^[1-9][0-9]*$ ]] || (( PUSH_EVERY_OVERRIDE < 1 )); }; then
  echo '--push-every deve ser um inteiro positivo.' >&2
  exit 2
fi

if [[ -z "$STATE_ROOT" ]]; then
  if [[ -n "${LOCALAPPDATA:-}" ]]; then
    if command -v cygpath >/dev/null 2>&1; then
      STATE_ROOT="$(cygpath -u "$LOCALAPPDATA")/Deskverse/codex-supervisor"
    else
      STATE_ROOT="$LOCALAPPDATA/Deskverse/codex-supervisor"
    fi
  else
    STATE_ROOT="${HOME:-/tmp}/AppData/Local/Deskverse/codex-supervisor"
  fi
fi

STATE_PATH="$STATE_ROOT/state.json"
BUDGET_PATH="$STATE_ROOT/budget.json"
LOG_ROOT="$STATE_ROOT/logs"
LOCK_PATH="$STATE_ROOT/lock"

if [[ "$LOOP_ENABLED" == "true" && "$LOOP_CHILD" != "true" ]]; then
  loop_state_snapshot() {
    LOOP_STATE_ROOT="$STATE_ROOT" node <<'NODE'
const fs = require('fs');
const path = require('path');
const file = path.join(process.env.LOOP_STATE_ROOT, 'state.json');
if (!fs.existsSync(file)) { console.log('unknown\t0\t'); process.exit(0); }
try {
  const state = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
  console.log([
    state.status || 'unknown',
    Array.isArray(state.completed) ? state.completed.length : 0,
    state.pause_until || ''
  ].join('\t'));
} catch {
  console.log('unknown\t0\t');
}
NODE
  }

  loop_wait() {
    local pause_until="${1:-}"
    local seconds
    if [[ -n "$pause_until" ]]; then
      seconds="$(node -e 'const t=Date.parse(process.argv[1]); console.log(Number.isFinite(t) ? Math.max(1, Math.ceil((t-Date.now())/1000)) : 0)' "$pause_until")"
    else
      seconds="$LOOP_INTERVAL"
    fi
    # An explicit zero means "continue immediately" after a normal sprint,
    # but an unknown pause must never turn into a tight retry loop.
    if [[ -z "$pause_until" && "$seconds" -eq 0 ]]; then
      seconds=60
    fi
    (( seconds > 0 )) && sleep "$seconds"
  }

  loop_interrupt() {
    printf '\n[loop] Interrompido; a sprint atual foi preservada pelo supervisor.\n' >&2
    exit 130
  }
  trap loop_interrupt INT TERM

  while true; do
    IFS=$'\t' read -r before_status before_count before_pause < <(loop_state_snapshot)
    printf '[loop] iniciando ciclo (concluídas=%s, status=%s)\n' "$before_count" "$before_status"
    set +e
    bash "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" "${ORIGINAL_ARGS[@]}" --loop-child
    child_exit=$?
    set -e

    IFS=$'\t' read -r after_status after_count pause_until < <(loop_state_snapshot)
    printf '[loop] ciclo finalizado (exit=%s, status=%s, concluídas=%s)\n' \
      "$child_exit" "$after_status" "$after_count"

    case "$after_status" in
      complete)
        printf '[loop] todas as sprints elegíveis foram concluídas.\n'
        exit 0
        ;;
      needs_attention|interrupted)
        printf '[loop] execução parada para intervenção manual.\n' >&2
        exit 10
        ;;
      account_rotated)
        printf '[loop] conta esgotada; retomando com a próxima conta disponível.\n'
        ;;
      paused|paused_budget|paused_rate_limit)
        printf '[loop] aguardando pausa até %s.\n' "${pause_until:-próximo ciclo}"
        loop_wait "$pause_until"
        ;;
      *)
        if [[ "$child_exit" -ne 0 ]]; then
          printf '[loop] processo filho terminou com erro; execução parada.\n' >&2
          exit "$child_exit"
        fi
        if [[ "$after_count" =~ ^[0-9]+$ && "$before_count" =~ ^[0-9]+$ ]] && (( after_count > before_count )); then
          printf '[loop] sprint concluída; avançando imediatamente para a próxima elegível.\n'
          continue
        else
          printf '[loop] nenhum avanço detectado; aguardando próximo ciclo.\n'
          loop_wait
        fi
        ;;
    esac
  done
fi

# O entrypoint mantém a CLI e a orquestração; detalhes ficam nos módulos
# carregados abaixo para que possam evoluir e ser testados isoladamente.
source "$SCRIPT_DIR/supervisor-ui.sh"
source "$SCRIPT_DIR/supervisor-state.sh"

if [[ "$MODE" == "message" ]]; then
  message_recover_processing
  queued_message="$(message_enqueue "$MESSAGE_TEXT")"
  message_id="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.id)' "$queued_message")"
  printf 'Mensagem enfileirada (%s); será entregue na próxima fronteira segura.\n' "$message_id"
  exit 0
fi

if [[ "$MODE" == "status" ]]; then
  if [[ -f "$STATE_ROOT/status.json" ]]; then
    STATE_PATH="$STATE_ROOT/status.json" node -e 'const fs=require("fs"); process.stdout.write(fs.readFileSync(process.env.STATE_PATH,"utf8"));'
  elif [[ -f "$STATE_PATH" ]]; then
    STATE_PATH="$STATE_PATH" node -e 'const fs=require("fs"); process.stdout.write(fs.readFileSync(process.env.STATE_PATH,"utf8"));'
  else
    echo "Ainda não há uma execução registrada em $STATE_ROOT."
  fi
  exit 0
fi

cd "$REPO_ROOT"

if [[ "$MODE" == "list" ]]; then
  QUEUE_PATH="$QUEUE_PATH" STATE_PATH="$STATE_PATH" REPO_ROOT="$REPO_ROOT" node <<'NODE'
const fs = require('fs');
const path = require('path');
const queue = JSON.parse(fs.readFileSync(process.env.QUEUE_PATH, 'utf8').replace(/^\uFEFF/, ''));
let state = {};
if (fs.existsSync(process.env.STATE_PATH)) {
  try { state = JSON.parse(fs.readFileSync(process.env.STATE_PATH, 'utf8').replace(/^\uFEFF/, '')); } catch {}
}
const sprintSort = (a, b) => String(a).localeCompare(String(b), undefined, { numeric: true, sensitivity: 'base' });
const walk = dir => fs.existsSync(dir) ? fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
  const full = path.join(dir, entry.name);
  return entry.isDirectory() ? walk(full) : [full];
}) : [];
const completed = new Set(Array.isArray(state.completed) ? state.completed : []);
const docs = new Map();
for (const documentPath of walk(path.join(process.env.REPO_ROOT, 'docs', 'sprints'))) {
  const id = path.basename(documentPath).match(/^sprint-(\d+[a-z]?)-/i)?.[1];
  if (!id) continue;
  const text = fs.readFileSync(documentPath, 'utf8').slice(0, 2500);
  const title = text.match(/^#\s+(.+)$/m)?.[1]?.trim() || '';
  const status = text.match(/^\s*\*\*Status:\*\*\s*([^\r\n]+)/im)?.[1] || 'sem status';
  const normalized = status.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  docs.set(id, { title, status });
  if (normalized.startsWith('conclu')) completed.add(id);
}
const items = (queue.items || []).map(item => {
  const done = completed.has(item.id);
  const dependencies = item.depends_on || [];
  const dependenciesDone = dependencies.every(dep => completed.has(dep));
  const documentInfo = docs.get(item.id) || {};
  return {
    id: item.id,
    title: item.title || item.name || documentInfo.title || `Sprint ${item.id}`,
    size: item.size || 'medium',
    status: done ? 'concluída' : dependenciesDone ? 'pendente' : 'bloqueada',
    depends_on: dependencies,
    document: item.document || null,
    document_status: documentInfo.status || null
  };
}).sort((a, b) => sprintSort(a.id, b.id));
console.log(JSON.stringify({
  completed: [...completed].sort(sprintSort),
  pending: items.filter(item => item.status !== 'concluída').map(item => item.id),
  items
}, null, 2));
NODE
  exit 0
fi

QUEUE_CONFIG="$(QUEUE_PATH="$QUEUE_PATH" node <<'NODE'
const fs = require('fs');
const queue = JSON.parse(fs.readFileSync(process.env.QUEUE_PATH, 'utf8').replace(/^\uFEFF/, ''));
console.log(JSON.stringify(queue.codex || {}));
NODE
)"
ACCOUNTS_JSON="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(JSON.stringify(x.accounts||{enabled:false,profiles:[]}))' "$QUEUE_CONFIG")"
ACCOUNT_ROTATION_ENABLED="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(String(x.enabled !== false && Array.isArray(x.profiles) && x.profiles.length > 0))' "$ACCOUNTS_JSON")"
ACCOUNT_PAUSE_HOURS="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(String(x.all_exhausted_pause_hours || process.argv[2]))' "$ACCOUNTS_JSON" "$PAUSE_HOURS")"
if ! [[ "$ACCOUNT_PAUSE_HOURS" =~ ^[1-9][0-9]*$ ]]; then ACCOUNT_PAUSE_HOURS="$PAUSE_HOURS"; fi
CODEX_MODEL="${MODEL_OVERRIDE:-$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.model||"gpt-5.6-sol")' "$QUEUE_CONFIG")}"
CODEX_REASONING="${REASONING_OVERRIDE:-$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.reasoning_effort||"high")' "$QUEUE_CONFIG")}"
SUBAGENT_MODEL="${SUBAGENT_MODEL_OVERRIDE:-$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.subagents?.model||"gpt-5.6-terra")' "$QUEUE_CONFIG")}"
SUBAGENT_REASONING="${SUBAGENT_REASONING_OVERRIDE:-$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.subagents?.reasoning_effort||"medium")' "$QUEUE_CONFIG")}"
AUTO_COMMIT_DIRTY="${AUTO_COMMIT_OVERRIDE:-$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(String(x.auto_commit_dirty ?? true))' "$QUEUE_CONFIG")}"
PUSH_MODE="${PUSH_MODE_OVERRIDE:-$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.push?.mode||"never")' "$QUEUE_CONFIG")}"
PUSH_EVERY="${PUSH_EVERY_OVERRIDE:-$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(String(x.push?.every_commits||4))' "$QUEUE_CONFIG")}"
COMPACTION_ENABLED="${COMPACTION_ENABLED_OVERRIDE:-$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(String(x.context_compaction?.enabled ?? true))' "$QUEUE_CONFIG")}"
COMPACTION_LIMIT="${COMPACTION_LIMIT_OVERRIDE:-$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(String(x.context_compaction?.auto_compact_token_limit || 64000))' "$QUEUE_CONFIG")}"
COMPACTION_SCOPE="${COMPACTION_SCOPE_OVERRIDE:-$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.context_compaction?.scope||"total")' "$QUEUE_CONFIG")}"
SUMMARY_MAX_CHARS="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(String(x.context_compaction?.summary_max_chars || 8000))' "$QUEUE_CONFIG")"
if ! [[ "$COMPACTION_LIMIT" =~ ^[0-9]+$ ]] || (( COMPACTION_LIMIT <= 0 )); then COMPACTION_LIMIT=64000; fi
if ! [[ "$SUMMARY_MAX_CHARS" =~ ^[0-9]+$ ]] || (( SUMMARY_MAX_CHARS < 1000 )); then SUMMARY_MAX_CHARS=8000; fi
case "$COMPACTION_SCOPE" in total|body_after_prefix) ;; *) COMPACTION_SCOPE=total ;; esac
case "$PUSH_MODE" in never|sprint|commits|both) ;; *) PUSH_MODE=never ;; esac
if ! [[ "$PUSH_EVERY" =~ ^[1-9][0-9]*$ ]]; then PUSH_EVERY=4; fi
case "$SUBAGENT_REASONING" in
  minimal|low) SUBAGENT_LADDER="$SUBAGENT_REASONING -> medium -> high -> xhigh" ;;
  medium) SUBAGENT_LADDER="medium -> high -> xhigh" ;;
  high) SUBAGENT_LADDER="high -> xhigh" ;;
  xhigh|max|ultra) SUBAGENT_LADDER="$SUBAGENT_REASONING" ;;
  *) SUBAGENT_LADDER="$SUBAGENT_REASONING -> high -> xhigh" ;;
esac
CODEX_CONFIG_ARGS=(
  --config "model_reasoning_effort=\"$CODEX_REASONING\""
  --config "agents.default_subagent_model=\"$SUBAGENT_MODEL\""
  --config "agents.default_subagent_reasoning_effort=\"$SUBAGENT_REASONING\""
)
if [[ "$COMPACTION_ENABLED" == "true" ]]; then
  CODEX_CONFIG_ARGS+=(
    --config "model_auto_compact_token_limit=$COMPACTION_LIMIT"
    --config "model_auto_compact_token_limit_scope=\"$COMPACTION_SCOPE\""
  )
else
  # Zero é o valor documentado pelo exemplo de configuração do Codex para
  # desativar/substituir o limite automático nesta execução.
  CODEX_CONFIG_ARGS+=(--config "model_auto_compact_token_limit=0")
fi

if ! validate_queue; then
  echo 'A fila não cobre todas as sprints pendentes; corrija sprint-queue.json antes de executar.' >&2
  exit 2
fi
if ! validate_accounts "$ACCOUNTS_JSON"; then
  echo 'Configuração de contas inválida; revise codex.accounts na sprint-queue.json.' >&2
  exit 2
fi

mkdir -p "$LOG_ROOT"
if ! mkdir "$LOCK_PATH" 2>/dev/null; then
  existing_pid="$(<"$LOCK_PATH/pid" 2>/dev/null || true)"
  if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
    echo "Supervisor já está em execução (PID $existing_pid); esta invocação não fará nada."
    exit 0
  fi
  rm -f "$LOCK_PATH/pid"
  if ! rmdir "$LOCK_PATH" 2>/dev/null || ! mkdir "$LOCK_PATH" 2>/dev/null; then
    echo "Não foi possível adquirir o lock do supervisor." >&2
    exit 1
  fi
fi
LOCK_PATH="$LOCK_PATH" SUPERVISOR_PID="$$" node -e 'const fs=require("fs"); fs.writeFileSync(`${process.env.LOCK_PATH}/pid`, process.env.SUPERVISOR_PID);'
release_lock() { print_final_status || true; rm -f "$LOCK_PATH/pid"; rmdir "$LOCK_PATH" 2>/dev/null || true; }
trap release_lock EXIT

STATUS_PHASE="starting"
RUN_ID=""
NEXT_ID=""
CODEX_PID=""
BROWSER_PID=""
CODEX_RENDERED_STDOUT_LINES=0
CODEX_RENDERED_STDERR_LINES=0
BROWSER_RENDERED_STDOUT_LINES=0
BROWSER_RENDERED_STDERR_LINES=0
ACTIVITY_SUMMARY=""

render_codex_delta() {
  local total_stdout total_stderr
  total_stdout="$(wc -l < "$STDOUT_PATH" | tr -d ' ')"
  if (( total_stdout > CODEX_RENDERED_STDOUT_LINES )); then
    tail -n +$((CODEX_RENDERED_STDOUT_LINES + 1)) "$STDOUT_PATH" | stream_codex_stdout /dev/null || true
    CODEX_RENDERED_STDOUT_LINES="$total_stdout"
  fi
  total_stderr="$(wc -l < "$STDERR_PATH" | tr -d ' ')"
  if (( total_stderr > CODEX_RENDERED_STDERR_LINES )); then
    tail -n +$((CODEX_RENDERED_STDERR_LINES + 1)) "$STDERR_PATH" | stream_codex_stderr /dev/null || true
    CODEX_RENDERED_STDERR_LINES="$total_stderr"
  fi
}

render_browser_delta() {
  local total_stdout total_stderr
  total_stdout="$(wc -l < "$BROWSER_STDOUT" | tr -d ' ')"
  if (( total_stdout > BROWSER_RENDERED_STDOUT_LINES )); then
    tail -n +$((BROWSER_RENDERED_STDOUT_LINES + 1)) "$BROWSER_STDOUT" | stream_browser_stdout /dev/null || true
    BROWSER_RENDERED_STDOUT_LINES="$total_stdout"
  fi
  total_stderr="$(wc -l < "$BROWSER_STDERR" | tr -d ' ')"
  if (( total_stderr > BROWSER_RENDERED_STDERR_LINES )); then
    tail -n +$((BROWSER_RENDERED_STDERR_LINES + 1)) "$BROWSER_STDERR" | stream_browser_stderr /dev/null || true
    BROWSER_RENDERED_STDERR_LINES="$total_stderr"
  fi
}

run_codex() {
  if [[ -n "${ACTIVE_CODEX_HOME:-}" ]]; then
    CODEX_HOME="$ACTIVE_CODEX_HOME" codex "$@"
  else
    codex "$@"
  fi
}

initialize_push_base() {
  [[ "$PUSH_MODE" != "never" ]] || return 0
  local head base
  head="$(git rev-parse HEAD)"
  base="$(state_field push_base_commit || true)"
  if [[ -z "$base" ]] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then
    state_patch "$(node -e 'console.log(JSON.stringify({push_base_commit:process.argv[1],commits_since_push:0,last_push_error:null}))' "$head")"
  fi
}

maybe_push_after_commit() {
  local sprint_boundary="${1:-false}" head base count should_push=false
  [[ "$MODE" == "run" ]] || return 0
  [[ "$PUSH_MODE" != "never" ]] || return 0
  head="$(git rev-parse HEAD)"
  base="$(state_field push_base_commit || true)"
  if [[ -z "$base" ]] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then
    state_patch "$(node -e 'console.log(JSON.stringify({push_base_commit:process.argv[1],commits_since_push:0,last_push_error:null}))' "$head")"
    return 0
  fi
  count="$(git rev-list --count "$base..HEAD")"
  state_patch "$(node -e 'console.log(JSON.stringify({commits_since_push:Number(process.argv[1])}))' "$count")"
  if [[ "$PUSH_MODE" == "commits" || "$PUSH_MODE" == "both" ]] && (( count >= PUSH_EVERY )); then
    should_push=true
  fi
  if [[ "$sprint_boundary" == "true" && ( "$PUSH_MODE" == "sprint" || "$PUSH_MODE" == "both" ) ]]; then
    should_push=true
  fi
  [[ "$should_push" == "true" ]] || return 0
  log "Executando git push (política $PUSH_MODE; $count commit(s) desde o último push)."
  if ! GIT_TERMINAL_PROMPT=0 git push < /dev/null; then
    state_patch "$(node -e 'console.log(JSON.stringify({last_push_error:process.argv[1]}))' 'git push falhou; o commit local foi preservado.')"
    log 'git push falhou; a execução local foi preservada e o push será reavaliado na próxima execução.'
    return 1
  fi
  state_patch "$(node -e 'console.log(JSON.stringify({push_base_commit:process.argv[1],commits_since_push:0,last_push_at:new Date().toISOString(),last_push_error:null}))' "$head")"
  log "Push concluído em $head."
}

on_interrupt() {
  local reason="Execução interrompida pelo usuário; checkpoint preservado."
  if [[ -n "${CODEX_PID:-}" ]] && kill -0 "$CODEX_PID" 2>/dev/null; then
    kill -TERM "$CODEX_PID" 2>/dev/null || true
    sleep 1
    kill -KILL "$CODEX_PID" 2>/dev/null || true
  fi
  if [[ -n "${BROWSER_PID:-}" ]] && kill -0 "$BROWSER_PID" 2>/dev/null; then
    kill -TERM "$BROWSER_PID" 2>/dev/null || true
  fi
  if [[ -f "$STATE_PATH" ]]; then
    state_patch "$(node -e 'console.log(JSON.stringify({status:"interrupted",last_error:process.argv[1],finished_at:new Date().toISOString()}))' "$reason")" || true
  fi
  STATUS_PHASE="interrupted"
  status_update "$STATUS_PHASE" "$reason" || true
  log "$reason"
  context_summary_write "${NEXT_ID:-—}" "$STATUS_PHASE" "" "" "$reason" || true
  exit 130
}
trap on_interrupt INT TERM

ensure_state
reconcile_completed_sprints

if [[ "$MODE" == "reset-pause" ]]; then
  state_patch "$(node -e 'console.log(JSON.stringify({pause_until:null,status:"idle",last_error:null,account_cooldowns:{}}))')"
  STATUS_PHASE="idle"
  log 'Pausa removida.'
  exit 0
fi

initialize_push_base

selection="$(STATE_PATH="$STATE_PATH" QUEUE_PATH="$QUEUE_PATH" BUDGET_PATH="$BUDGET_PATH" REPO_ROOT="$REPO_ROOT" REQUESTED_SPRINTS="$SPRINTS_OVERRIDE" node <<'NODE'
const fs = require('fs');
const path = require('path');
const sprintSort = (a, b) => String(a).localeCompare(String(b), undefined, { numeric: true, sensitivity: 'base' });
const queue = JSON.parse(fs.readFileSync(process.env.QUEUE_PATH, 'utf8').replace(/^\uFEFF/, ''));
const state = JSON.parse(fs.readFileSync(process.env.STATE_PATH, 'utf8').replace(/^\uFEFF/, ''));
const now = Date.now();
const requested = new Set(String(process.env.REQUESTED_SPRINTS || '')
  .split(',')
  .map(value => value.trim().toLowerCase())
  .filter(value => value && value !== 'all'));
const queueItems = queue.items || [];
const unknown = [...requested].filter(id => !queueItems.some(item => String(item.id).toLowerCase() === id));
if (unknown.length) {
  console.log(JSON.stringify({ action: 'invalid_selection', requested: [...requested], unknown }));
  process.exit(0);
}
if (state.pause_until && Date.parse(state.pause_until) > now) {
  console.log(JSON.stringify({ action: 'paused', pause_until: state.pause_until })); process.exit(0);
}
const walk = dir => fs.existsSync(dir) ? fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
  const full = path.join(dir, entry.name);
  return entry.isDirectory() ? walk(full) : [full];
}) : [];
const completedFromDocuments = [];
const documentIds = new Set();
for (const documentPath of walk(path.join(process.env.REPO_ROOT, 'docs', 'sprints'))) {
  const id = path.basename(documentPath).match(/^sprint-(\d+[a-z]?)-/i)?.[1];
  if (!id) continue;
  documentIds.add(id);
  const text = fs.readFileSync(documentPath, 'utf8').slice(0, 2500);
  const status = text.match(/^\s*\*\*Status:\*\*\s*([^\r\n]+)/im)?.[1] || '';
  const normalized = status.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  if (normalized.startsWith('conclu')) completedFromDocuments.push(id);
}
completedFromDocuments.sort(sprintSort);
const completed = new Set([
  ...completedFromDocuments
]);
// Se um documento foi removido, ainda podemos usar a evidência persistida do
// gate. Quando ele existe, seu Status prevalece para permitir reaberturas.
for (const id of state.completed || []) if (!documentIds.has(id)) completed.add(id);
const eligible = queueItems.map((item, index) => ({ item, index })).filter(({item}) =>
  !completed.has(item.id) && (item.depends_on || []).every(dep => completed.has(dep)));
const pending = queueItems.filter(item => !completed.has(item.id));
const requestedPending = requested.size
  ? queueItems.filter(item => requested.has(String(item.id).toLowerCase()) && !completed.has(item.id))
  : [];
if (requested.size && !requestedPending.length) {
  console.log(JSON.stringify({ action: 'complete', completed: [...completed], requested: [...requested] }));
  process.exit(0);
}
if (requested.size) {
  const blocked = requestedPending.filter(item => !(item.depends_on || []).every(dep => completed.has(dep)));
  if (blocked.length) {
    console.log(JSON.stringify({
      action: 'blocked_selection',
      requested: [...requested],
      blocked: blocked.map(item => ({ id: item.id, depends_on: item.depends_on || [] }))
    }));
    process.exit(0);
  }
}
if (!eligible.length) {
  if (!pending.length) console.log(JSON.stringify({ action: 'complete', completed: [...completed] }));
  else console.log(JSON.stringify({ action: 'blocked', completed: [...completed], pending: pending.map(item => ({ id: item.id, depends_on: item.depends_on || [] })) }));
  process.exit(0);
}
const scopedEligible = requested.size
  ? eligible.filter(({item}) => requested.has(String(item.id).toLowerCase()))
  : eligible;
if (requested.size && !scopedEligible.length) {
  console.log(JSON.stringify({
    action: 'blocked_selection',
    requested: [...requested],
    blocked: requestedPending.map(item => ({ id: item.id, depends_on: item.depends_on || [] }))
  }));
  process.exit(0);
}
const reserve = item => item.size === 'short' ? 10 : item.size === 'long' ? 20 : 15;
let remaining = null;
if (fs.existsSync(process.env.BUDGET_PATH)) {
  const budget = JSON.parse(fs.readFileSync(process.env.BUDGET_PATH, 'utf8').replace(/^\uFEFF/, ''));
  if (budget.remaining_percent !== null && budget.remaining_percent !== undefined) remaining = Number(budget.remaining_percent);
  else if (Number(budget.total_tokens || 0) > 0) remaining = Math.max(0, Math.min(100, 100 * (Number(budget.total_tokens) - Number(budget.consumed_tokens || 0)) / Number(budget.total_tokens)));
}
let chosen = scopedEligible[0];
let decision = null;
if (remaining !== null && remaining < reserve(chosen.item)) {
  const affordable = scopedEligible.filter(({item}) => remaining >= reserve(item)).sort((a,b) => (Number(a.item.cost_rank || reserve(a.item)) - Number(b.item.cost_rank || reserve(b.item))) || (a.index - b.index));
  if (!affordable.length) { console.log(JSON.stringify({ action: 'paused_budget', remaining_percent: remaining, reset_at: fs.existsSync(process.env.BUDGET_PATH) ? JSON.parse(fs.readFileSync(process.env.BUDGET_PATH,'utf8').replace(/^\uFEFF/, '')).reset_at || null : null })); process.exit(0); }
  chosen = affordable[0];
  decision = 'Escolhida ' + chosen.item.id + ' (' + chosen.item.size + ') entre ' + scopedEligible.length + ' selecionadas com ' + remaining + '% restantes.';
}
console.log(JSON.stringify({ action: 'run', id: chosen.item.id, document: chosen.item.document, size: chosen.item.size, remaining_percent: remaining, decision, completed: [...completed].sort(sprintSort) }));
NODE
)"
selection_action="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.action)' "$selection")"

case "$selection_action" in
  invalid_selection)
    invalid_ids="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write((x.unknown||[]).join(", "))' "$selection")"
    state_patch "$(node -e 'console.log(JSON.stringify({status:"needs_attention",current:null,last_error:process.argv[1]}))' "Seleção inválida; IDs ausentes na fila: $invalid_ids")"
    STATUS_PHASE="needs_attention"
    log "Seleção inválida; IDs ausentes na fila: $invalid_ids."
    exit 2 ;;
  blocked_selection)
    blocked_ids="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write((x.blocked||[]).map(item => item.id).join(", "))' "$selection")"
    state_patch "$(node -e 'console.log(JSON.stringify({status:"needs_attention",current:null,last_error:process.argv[1]}))' "Seleção bloqueada; dependências não concluídas para: $blocked_ids")"
    STATUS_PHASE="needs_attention"
    log "Seleção bloqueada; conclua as dependências antes: $blocked_ids."
    exit 10 ;;
  paused)
    STATUS_PHASE="paused"; PAUSE_UNTIL="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.pause_until)' "$selection")"
    log "Supervisor pausado até $PAUSE_UNTIL."; exit 0 ;;
  complete)
    state_patch "$(node -e 'console.log(JSON.stringify({status:"complete",current:null}))')"; STATUS_PHASE="complete"; log 'Nenhuma sprint elegível na fila.'; exit 0 ;;
  blocked)
    blocked_ids="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write((x.pending||[]).map(item => item.id).join(", "))' "$selection")"
    state_patch "$(node -e 'console.log(JSON.stringify({status:"needs_attention",current:null,last_error:process.argv[1]}))' "Nenhuma sprint elegível: dependências não concluídas ou ciclo na fila.")"
    STATUS_PHASE="needs_attention"; log "Fila bloqueada; sprints pendentes sem dependências satisfeitas: $blocked_ids."; exit 10 ;;
  paused_budget)
    remaining="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(String(x.remaining_percent))' "$selection")"
    reset_at="$(node -e 'const x=JSON.parse(process.argv[1]); if(x.reset_at) process.stdout.write(x.reset_at)' "$selection")"
    patch="$(node -e 'const x=JSON.parse(process.argv[1]); console.log(JSON.stringify({status:"paused_budget",current:null,budget_remaining_percent:x.remaining_percent,pause_until:x.reset_at||null}))' "$selection")"
    PAUSE_UNTIL="$reset_at"; state_patch "$patch"; STATUS_PHASE="paused_budget"; log "Franquia em ${remaining}%; nenhuma sprint elegível cabe na margem."; exit 0 ;;
esac

NEXT_ID="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.id)' "$selection")"
STATUS_PHASE="selecting"
DOCUMENT="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.document)' "$selection")"
DECISION="$(node -e 'const x=JSON.parse(process.argv[1]); if(x.decision) process.stdout.write(x.decision)' "$selection")"
DETECTED_COMPLETED="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write((x.completed||[]).join(", "))' "$selection")"
status_update "$STATUS_PHASE" "Sprint $NEXT_ID selecionada; verificando o checkout e o documento."
[[ -z "$DETECTED_COMPLETED" ]] || log "Conclusões detectadas automaticamente: $DETECTED_COMPLETED."
[[ -z "$DECISION" ]] || log "$DECISION"
DOCUMENT_PATH="$REPO_ROOT/$DOCUMENT"
[[ -f "$DOCUMENT_PATH" ]] || { state_patch "$(node -e 'console.log(JSON.stringify({status:"needs_attention",last_error:process.argv[1]}))' "Documento da sprint não encontrado: $DOCUMENT_PATH")"; exit 10; }

cd "$REPO_ROOT"
if [[ "$ACCOUNT_ROTATION_ENABLED" == "true" ]]; then
  PREFERRED_ACCOUNT="${ACCOUNT_OVERRIDE:-$(state_field active_account || true)}"
  ACCOUNT_PICK="$(account_selection "$ACCOUNTS_JSON" "$PREFERRED_ACCOUNT")"
  ACCOUNT_ACTION="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.action)' "$ACCOUNT_PICK")"
  case "$ACCOUNT_ACTION" in
    selected)
      ACTIVE_ACCOUNT_ID="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.id)' "$ACCOUNT_PICK")"
      ACTIVE_CODEX_HOME="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.home)' "$ACCOUNT_PICK")"
      state_patch "$(node -e 'console.log(JSON.stringify({active_account:process.argv[1],status:"selecting",last_error:null}))' "$ACTIVE_ACCOUNT_ID")"
      log "Conta Codex ativa: $ACTIVE_ACCOUNT_ID."
      ;;
    all_exhausted)
      PAUSE_UNTIL="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.pause_until||"")' "$ACCOUNT_PICK")"
      state_patch "$(node -e 'console.log(JSON.stringify({status:"paused_rate_limit",pause_until:process.argv[1]}))' "$PAUSE_UNTIL")"
      STATUS_PHASE="paused_rate_limit"
      log "Todas as contas Codex estão temporariamente indisponíveis; pausa até $PAUSE_UNTIL."
      exit 0
      ;;
    needs_setup)
      missing_accounts="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write((x.missing||[]).join(", "))' "$ACCOUNT_PICK")"
      state_patch "$(node -e 'console.log(JSON.stringify({status:"needs_attention",last_error:process.argv[1]}))' "Contas Codex sem login: $missing_accounts")"
      STATUS_PHASE="needs_attention"
      log "Contas Codex sem login: $missing_accounts."
      exit 10
      ;;
  esac
fi
if [[ "$MODE" != "dry-run" ]]; then
  dirty_paths="$(git status --porcelain)"
  if [[ -n "$dirty_paths" ]]; then
    if ! commit_dirty_checkpoint "$dirty_paths"; then
      state_patch "$(node -e 'console.log(JSON.stringify({status:"needs_attention",current:process.argv[1],last_error:"Checkout sujo e checkpoint automático não autorizado ou não concluído."}))' "$NEXT_ID")"
      log 'Checkout sujo; execução bloqueada para preservar alterações manuais.'
      exit 10
    fi
  fi
fi
BEFORE_COMMIT="$(git rev-parse HEAD)"

if [[ "$MODE" == "dry-run" ]]; then
  STATUS_PHASE="dry-run"
  log "Dry-run: próxima sprint $NEXT_ID; documento: $DOCUMENT."
  log 'Dry-run: nenhuma chamada ao Codex foi feita.'
  exit 0
fi

PREVIOUS_CURRENT="$(state_field current || true)"
SESSION_ID="$(state_field session_id || true)"
SESSION_ACCOUNT="$(state_field session_account || true)"
LAST_ERROR="$(state_field last_error || true)"
CONTEXT_SUMMARY=""
if [[ "$PREVIOUS_CURRENT" == "$NEXT_ID" ]]; then
  CONTEXT_SUMMARY="$(context_summary_read || true)"
fi
PROMPT="$(cat <<__SUPERVISOR_PROMPT__
Você é o executor serial do Deskverse. Trabalhe SOMENTE na Sprint $NEXT_ID.

Antes de editar:
- leia AGENTS.md;
- leia docs/memoria-codex.md;
- leia integralmente $DOCUMENT;
- confira as dependências e o estado atual do repositório.
- use inspeções somente de leitura; não use Remove-Item, del, rm, git clean,
  git reset --hard ou outros comandos destrutivos;
- nunca redirecione saída para nomes reservados do Windows (nul, con, prn,
  aux). Se um arquivo específico não puder ser editado, removido ou lido,
  registre-o como ignorado, não insista na operação e continue com os demais
  arquivos e tarefas da sprint. Não trate esse arquivo isolado como bloqueio.

Implemente o escopo da sprint, respeitando o styleguide e as decisões registradas.
Não antecipe a próxima sprint. Execute os testes, typecheck, lint, build e inspeções
exigidos pelo documento. Só considere concluída depois de atualizar o campo Status
do documento para "Concluída em AAAA-MM-DD", registrar na memória operacional uma
entrada verificável e criar um commit atômico que inclua essas atualizações.

Se a sprint alterar comportamento ou interface no navegador, crie ou atualize os
testes E2E necessários. Depois do seu commit, um gate externo abrirá o app em
Chromium e executará npm run test:e2e.

Se houver requisito ambíguo ou falha que impeça os critérios de aceite, pare no
checkpoint seguro, não faça commit falso e informe o bloqueio. Erros restritos
a um arquivo que não pode ser editado/removido devem ser ignorados conforme a
regra acima, sem interromper a execução do restante.

Se coordenar subagentes, publique atualizações periódicas no texto usando uma
linha por atualização neste formato exato:
AGENT_PROGRESS: {"id":"identificador","name":"nome ou papel","task":"tarefa","status":"running|completed|failed|blocked|retrying","reasoning_effort":"medium|high|xhigh","message":"descrição com no máximo cinco palavras"}
Isso permite ao supervisor compartilhar o andamento de cada agente sem expor
todo o transcript interno.
O campo message de cada AGENT_PROGRESS deve ser uma descrição objetiva do que
está acontecendo, com no máximo cinco palavras.

Política obrigatória de recuperação de subagentes:
- comece cada subagente em $SUBAGENT_MODEL com esforço $SUBAGENT_REASONING;
- se ele falhar, ficar bloqueado ou produzir resultado insuficiente, repita a
  mesma tarefa elevando o esforço nesta sequência: $SUBAGENT_LADDER
  (sem reduzir o nível configurado);
- publique um AGENT_PROGRESS com status retrying antes de cada nova tentativa;
- nunca ultrapasse xhigh nem crie tentativas duplicadas em paralelo para o mesmo
  bloqueio; se xhigh também falhar, preserve o bloqueio e informe-o.

Na última mensagem, escreva exatamente uma destas linhas:
STATUS: COMPLETED
STATUS: PAUSED
STATUS: BLOCKED
e inclua o hash do commit quando STATUS for COMPLETED.
Antes dessa linha, inclua uma seção curta CONTEXT_HANDOFF com decisões,
arquivos alterados, validações, bloqueios e o próximo passo para uma retomada.
__SUPERVISOR_PROMPT__
)"
if [[ -n "$LAST_ERROR" ]]; then PROMPT+=$'\n\nO último gate falhou. Corrija antes de concluir:\n'"$LAST_ERROR"; fi
if [[ -n "$CONTEXT_SUMMARY" ]]; then
  PROMPT+=$'\n\nCONTEXTO COMPACTADO DA RETOMADA (fonte auxiliar; confirme no código e nos documentos):\n'"$CONTEXT_SUMMARY"
fi

RUN_ID="${NEXT_ID}-$(date '+%Y%m%d-%H%M%S')"
STDOUT_PATH="$LOG_ROOT/$RUN_ID.jsonl"
STDERR_PATH="$LOG_ROOT/$RUN_ID.stderr.log"
: > "$STDOUT_PATH"
: > "$STDERR_PATH"
STATUS_PHASE="running_codex"
state_patch "$(node -e 'console.log(JSON.stringify({current:process.argv[1],status:"running",started_at:new Date().toISOString(),last_error:null,budget_decision:process.argv[2]||null}))' "$NEXT_ID" "$DECISION")"
log "Iniciando Sprint $NEXT_ID com modelo $CODEX_MODEL/$CODEX_REASONING; subagentes $SUBAGENT_MODEL/$SUBAGENT_REASONING."

set +e
if [[ "$PREVIOUS_CURRENT" == "$NEXT_ID" && -n "$SESSION_ID" && "$SESSION_ACCOUNT" == "$ACTIVE_ACCOUNT_ID" ]]; then
  log "Retomando sessão $SESSION_ID."
  run_codex exec resume --model "$CODEX_MODEL" \
    --dangerously-bypass-approvals-and-sandbox "${CODEX_CONFIG_ARGS[@]}" \
    --json "$SESSION_ID" "$PROMPT" \
    < /dev/null > "$STDOUT_PATH" 2> "$STDERR_PATH" &
else
  run_codex exec --model "$CODEX_MODEL" \
    --dangerously-bypass-approvals-and-sandbox "${CODEX_CONFIG_ARGS[@]}" \
    --json "$PROMPT" \
    < /dev/null > "$STDOUT_PATH" 2> "$STDERR_PATH" &
fi
CODEX_PID=$!
while kill -0 "$CODEX_PID" 2>/dev/null; do
  render_codex_delta
  EVENT_COUNT="$(wc -l < "$STDOUT_PATH" | tr -d ' ')"
  COMPACTION_COUNT="$(grep -Eic 'context[_-]?compaction|contextCompaction' "$STDOUT_PATH" 2>/dev/null || true)"
  AGENTS_JSON="$(agents_snapshot "$STDOUT_PATH")"
  live_session="$(STDOUT_PATH="$STDOUT_PATH" node <<'NODE'
const fs = require('fs');
const path = process.env.STDOUT_PATH;
if (!fs.existsSync(path)) process.exit(0);
for (const line of fs.readFileSync(path, 'utf8').split(/\r?\n/)) {
  try { const event = JSON.parse(line); if (event.type === 'thread.started' && event.thread_id) { process.stdout.write(event.thread_id); break; } } catch {}
}
NODE
  )"
  if [[ -n "$live_session" ]]; then
    SESSION_ID="$live_session"
    SESSION_ACCOUNT="$ACTIVE_ACCOUNT_ID"
    state_patch "$(node -e 'console.log(JSON.stringify({session_id:process.argv[1],session_account:process.argv[2]||null}))' "$live_session" "$SESSION_ACCOUNT")"
  fi
  ACTIVITY_SUMMARY="$(activity_snapshot "$STDOUT_PATH")"
  status_update "running_codex" "Codex · ${ACTIVITY_SUMMARY:-processando sprint}."
  sleep 10
done
wait "$CODEX_PID"
CODEX_EXIT=$?
CODEX_PID=""
render_codex_delta
# O formatador JSONL lê o arquivo incrementalmente; aguarde-o parar de crescer
# para não avaliar a sprint antes de receber o último evento.
previous_event_count=-1
for _ in {1..10}; do
  current_event_count="$(wc -l < "$STDOUT_PATH" | tr -d ' ')"
  [[ "$current_event_count" == "$previous_event_count" ]] && break
  previous_event_count="$current_event_count"
  sleep 0.2
done
set -e

SUMMARY="$(STDOUT_PATH="$STDOUT_PATH" node <<'NODE'
const fs = require('fs');
const lines = fs.readFileSync(process.env.STDOUT_PATH, 'utf8').split(/\r?\n/);
let thread_id = null, final_text = '', input_tokens = 0, cached_input_tokens = 0, output_tokens = 0, turns = 0;
for (const line of lines) { if (!line.trim()) continue; let e; try { e = JSON.parse(line); } catch { continue; }
  if (e.type === 'thread.started') thread_id = e.thread_id || thread_id;
  if (e.type === 'turn.completed') { const u=e.usage||{}; input_tokens += Number(u.input_tokens||0); cached_input_tokens += Number(u.cached_input_tokens||0); output_tokens += Number(u.output_tokens||0); turns++; }
  if (e.type === 'item.completed' && e.item?.type === 'agent_message') final_text = e.item.text || final_text;
}
console.log(JSON.stringify({thread_id, final_text, input_tokens, cached_input_tokens, output_tokens, turns}));
NODE
)"
AGENTS_JSON="$(agents_snapshot "$STDOUT_PATH")"
EVENT_COUNT="$(wc -l < "$STDOUT_PATH" | tr -d ' ')"
COMPACTION_COUNT="$(grep -Eic 'context[_-]?compaction|contextCompaction' "$STDOUT_PATH" 2>/dev/null || true)"
TURN_COUNT="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(String(x.turns||0))' "$SUMMARY" 2>/dev/null || echo 0)"
LAST_AGENT_MESSAGE="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write((x.final_text||"").slice(-1000))' "$SUMMARY")"
STATUS_PHASE="evaluating"
status_update "$STATUS_PHASE" "Codex terminou; avaliando marcador, commit e checkout."
THREAD_ID="$(node -e 'const x=JSON.parse(process.argv[1]); if(x.thread_id) process.stdout.write(x.thread_id)' "$SUMMARY")"
[[ -z "$THREAD_ID" ]] || state_patch "$(node -e 'console.log(JSON.stringify({session_id:process.argv[1],session_account:process.argv[2]||null}))' "$THREAD_ID" "$ACTIVE_ACCOUNT_ID")"
USAGE_JSON="$(node -e 'const x=JSON.parse(process.argv[1]); console.log(JSON.stringify({input_tokens:x.input_tokens,cached_input_tokens:x.cached_input_tokens,output_tokens:x.output_tokens,turns:x.turns}))' "$SUMMARY")"
add_usage "$USAGE_JSON"
TOKEN_COUNT="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(String(x.input_tokens+x.output_tokens))' "$SUMMARY")"
update_budget "$TOKEN_COUNT"

FINAL_TEXT="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.final_text||"")' "$SUMMARY")"
COMPLETED_MARKER=0
if printf '%s\n' "$FINAL_TEXT" | grep -Eiq '^STATUS:[[:space:]]*COMPLETED[[:space:]]*$'; then COMPLETED_MARKER=1; fi
RATE_LIMIT=0
# O stdout contém a resposta do agente e pode mencionar "créditos" em contexto
# normal. Só classifique como limite quando o stderr ou um evento de erro
# estruturado trouxer um sinal inequívoco.
if grep -Eiq 'rate limit|usage limit|too many requests|quota exceeded|insufficient[_ -]?quota|out of credits|credit limit|HTTP[[:space:]]*429' "$STDERR_PATH"; then
  RATE_LIMIT=1
elif STDOUT_PATH="$STDOUT_PATH" node <<'NODE'
const fs = require('fs');
const path = process.env.STDOUT_PATH;
const pattern = /rate limit|usage limit|too many requests|quota exceeded|insufficient[_ -]?quota|out of credits|credit limit|HTTP\s*429/i;
let hit = false;
if (fs.existsSync(path)) for (const line of fs.readFileSync(path, 'utf8').split(/\r?\n/)) {
  try {
    const event = JSON.parse(line);
    if (String(event.type || '').toLowerCase().includes('error') && pattern.test(JSON.stringify(event))) { hit = true; break; }
  } catch {}
}
process.exit(hit ? 0 : 1);
NODE
then
  RATE_LIMIT=1
fi
AFTER_COMMIT="$(git rev-parse HEAD)"
AFTER_DIRTY="$(checkout_dirty_without_ignored)"

if (( RATE_LIMIT )); then
  PAUSE_UNTIL="$(now_plus_hours "$ACCOUNT_PAUSE_HOURS")"
  if [[ "$ACCOUNT_ROTATION_ENABLED" == "true" && -n "$ACTIVE_ACCOUNT_ID" ]]; then
    state_patch "$(STATE_PATH="$STATE_PATH" ACCOUNT_ID="$ACTIVE_ACCOUNT_ID" ACCOUNT_UNTIL="$PAUSE_UNTIL" node <<'NODE'
const fs = require('fs');
const state = JSON.parse(fs.readFileSync(process.env.STATE_PATH, 'utf8').replace(/^\uFEFF/, ''));
state.account_cooldowns = {...(state.account_cooldowns || {}), [process.env.ACCOUNT_ID]: process.env.ACCOUNT_UNTIL};
state.session_id = null;
state.session_account = null;
console.log(JSON.stringify(state));
NODE
)"
    NEXT_ACCOUNT_PICK="$(account_selection "$ACCOUNTS_JSON" "")"
    NEXT_ACCOUNT_ACTION="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.action)' "$NEXT_ACCOUNT_PICK")"
    if [[ "$NEXT_ACCOUNT_ACTION" == "selected" ]]; then
      NEXT_ACCOUNT_ID="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.id)' "$NEXT_ACCOUNT_PICK")"
      NEXT_ACCOUNT_HOME="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.home)' "$NEXT_ACCOUNT_PICK")"
      ACTIVE_ACCOUNT_ID="$NEXT_ACCOUNT_ID"
      ACTIVE_CODEX_HOME="$NEXT_ACCOUNT_HOME"
      STATUS_PHASE="account_rotated"
      state_patch "$(node -e 'console.log(JSON.stringify({status:"account_rotated",active_account:process.argv[1],pause_until:null,last_error:null}))' "$NEXT_ACCOUNT_ID")"
      log "Limite da conta anterior; alternando para $NEXT_ACCOUNT_ID e retomando o contexto."
    elif [[ "$NEXT_ACCOUNT_ACTION" == "all_exhausted" ]]; then
      STATUS_PHASE="paused_rate_limit"
      NEXT_PAUSE="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.pause_until||process.argv[2])' "$NEXT_ACCOUNT_PICK" "$PAUSE_UNTIL")"
      state_patch "$(node -e 'console.log(JSON.stringify({status:"paused_rate_limit",pause_until:process.argv[1]}))' "$NEXT_PAUSE")"
      log "Limite de uso em todas as contas; pausa até $NEXT_PAUSE."
    else
      missing_accounts="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write((x.missing||[]).join(", "))' "$NEXT_ACCOUNT_PICK")"
      STATUS_PHASE="needs_attention"
      state_patch "$(node -e 'console.log(JSON.stringify({status:"needs_attention",last_error:process.argv[1]}))' "Contas Codex sem login: $missing_accounts")"
      log "Não foi possível alternar: contas sem login ($missing_accounts)."
    fi
  else
    STATUS_PHASE="paused_rate_limit"
    state_patch "$(node -e 'console.log(JSON.stringify({status:"paused_rate_limit",pause_until:process.argv[1]}))' "$PAUSE_UNTIL")"
    log "Limite de uso detectado; pausa até $PAUSE_UNTIL."
  fi
elif (( CODEX_EXIT != 0 )); then
  ERROR_TEXT="$(tail -n 80 "$STDERR_PATH" 2>/dev/null || true)"
  STATUS_PHASE="needs_attention"
  state_patch "$(node -e 'console.log(JSON.stringify({status:"needs_attention",last_error:process.argv[1]}))' "$ERROR_TEXT")"
  log "Codex terminou com código $CODEX_EXIT; revisão necessária."
elif (( COMPLETED_MARKER )) && [[ "$AFTER_COMMIT" != "$BEFORE_COMMIT" ]] && [[ -z "$AFTER_DIRTY" ]]; then
  BROWSER_COMMAND="$(QUEUE_PATH="$QUEUE_PATH" node <<'NODE'
const fs = require('fs');
const q = JSON.parse(fs.readFileSync(process.env.QUEUE_PATH, 'utf8').replace(/^\uFEFF/, ''));
process.stdout.write(q.browser_check || 'npm run test:e2e -- --reporter=json');
NODE
)"
  BROWSER_STDOUT="$LOG_ROOT/$RUN_ID.browser.json"
  BROWSER_STDERR="$LOG_ROOT/$RUN_ID.browser.stderr.log"
  SCREENSHOT_PATH="$LOG_ROOT/$RUN_ID.browser.png"
  STATUS_PHASE="validating_browser"
  log "Executando gate de navegador: $BROWSER_COMMAND"
  set +e
  (cd "$REPO_ROOT" && export SUPERVISOR_SCREENSHOT_PATH="$SCREENSHOT_PATH" && bash -lc "$BROWSER_COMMAND" < /dev/null) \
    > "$BROWSER_STDOUT" 2> "$BROWSER_STDERR" &
  BROWSER_PID=$!
  while kill -0 "$BROWSER_PID" 2>/dev/null; do
    render_browser_delta
    status_update "validating_browser" "Gate de navegador em execução para a sprint $NEXT_ID."
    sleep 10
  done
  wait "$BROWSER_PID"
  BROWSER_EXIT=$?
  BROWSER_PID=""
  render_browser_delta
  set -e
  if (( BROWSER_EXIT == 0 )); then
    add_completed "$NEXT_ID" "$AFTER_COMMIT"
    if maybe_push_after_commit true; then
      STATUS_PHASE="completed"
      log "Sprint $NEXT_ID concluída no commit $AFTER_COMMIT e aprovada pelo navegador."
    else
      ERROR_TEXT="git push falhou; sprint concluída localmente no commit $AFTER_COMMIT, mas o remoto precisa ser atualizado."
      STATUS_PHASE="needs_attention"
      state_patch "$(node -e 'console.log(JSON.stringify({status:"needs_attention",last_error:process.argv[1]}))' "$ERROR_TEXT")"
      log "$ERROR_TEXT"
    fi
  else
    ERROR_TEXT="$(tail -n 80 "$BROWSER_STDERR" 2>/dev/null || true)"
    STATUS_PHASE="needs_attention"
    state_patch "$(node -e 'console.log(JSON.stringify({status:"needs_attention",last_error:process.argv[1]}))' "$ERROR_TEXT")"
    log "Gate de navegador falhou com código $BROWSER_EXIT; sprint não avançada."
  fi
else
  STATUS_PHASE="needs_attention"
  state_patch "$(node -e 'console.log(JSON.stringify({status:"needs_attention",last_error:"Execução terminou sem marcador COMPLETED, commit novo e checkout limpo."}))')"
  log 'Execução terminou sem marcador COMPLETED, commit novo e checkout limpo.'
fi

state_patch "$(node -e 'console.log(JSON.stringify({finished_at:new Date().toISOString()}))')"
context_summary_write "$NEXT_ID" "$STATUS_PHASE" "${AFTER_COMMIT:-}" "${FINAL_TEXT:-}" "${ERROR_TEXT:-}" || true
