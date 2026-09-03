# Funções de apresentação e streaming do supervisor.
# Este arquivo é carregado por sprint-supervisor.sh; não deve ser executado só.

# A saída interativa usa o mesmo vocabulário visual do Codex CLI, mas cai para
# texto simples quando o supervisor é redirecionado para um arquivo/CI.
UI_INITIALIZED=0
LAST_UI_STATUS_SIGNATURE=""
STREAM_ERROR_CONTEXT=""
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_CYAN=$'\033[36m'
  C_BLUE=$'\033[34m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
else
  C_RESET=''; C_BOLD=''; C_DIM=''; C_CYAN=''; C_BLUE=''
  C_GREEN=''; C_YELLOW=''; C_RED=''
fi

ui_header() {
  [[ "$MODE" == "run" ]] || return 0
  [[ -t 1 ]] || return 0
  (( UI_INITIALIZED == 0 )) || return 0
  UI_INITIALIZED=1
  printf '\n%s╭─ %sDESKVERSE · SPRINT SUPERVISOR%s ─────────────────────────╮%s\n' \
    "$C_DIM" "$C_BOLD" "$C_DIM" "$C_RESET"
  if [[ "${CONTROLLER:-chat}" == "chat" ]]; then
    printf '%s│%s supervisor %schat%s (modelo desta conversa)\n' "$C_DIM" "$C_RESET" "$C_CYAN" "$C_RESET"
  else
    printf '%s│%s runner     %s%s%s / %s%s%s\n' \
      "$C_DIM" "$C_RESET" "$C_CYAN" "${CODEX_MODEL:-—}" "$C_RESET" \
      "$C_YELLOW" "${CODEX_REASONING:-—}" "$C_RESET"
  fi
  printf '%s│%s subagentes %s%s%s / %s%s%s\n' \
    "$C_DIM" "$C_RESET" "$C_BLUE" "${SUBAGENT_MODEL:-—}" "$C_RESET" \
    "$C_YELLOW" "${SUBAGENT_REASONING:-—}" "$C_RESET"
  if [[ -n "${ACTIVE_ACCOUNT_ID:-}" ]]; then
    printf '%s│%s conta     %s%s%s\n' "$C_DIM" "$C_RESET" "$C_CYAN" "$ACTIVE_ACCOUNT_ID" "$C_RESET"
  fi
  printf '%s│%s push      %s%s%s (a cada %s commit(s))\n' \
    "$C_DIM" "$C_RESET" "$C_CYAN" "${PUSH_MODE:-never}" "$C_RESET" "${PUSH_EVERY:-4}"
  printf '%s╰──────────────────────────────────────────────────────────╯%s\n' "$C_DIM" "$C_RESET"
}

ui_render_status() {
  local phase="$1" message="$2" agent_count="$3"
  local icon='·' color="$C_CYAN" label
  label="${phase//_/ }"
  label="${label^^}"
  case "$phase" in
    running_codex) icon='⟳'; color="$C_CYAN" ;;
    validating_browser) icon='◌'; color="$C_BLUE" ;;
    completed) icon='✓'; color="$C_GREEN" ;;
    paused|paused_budget) icon='Ⅱ'; color="$C_YELLOW" ;;
    interrupted|needs_attention) icon='!'; color="$C_RED" ;;
  esac

  if [[ -t 1 ]]; then
    ui_header
    printf '%s%s %s%-19s%s %ssprint%s %-5s %seventos%s %-4s %scompact%s %-3s %sagentes%s %-3s%s\n' \
      "$color" "$icon" "$C_BOLD" "$label" "$C_RESET" "$C_DIM" "$C_RESET" \
      "${NEXT_ID:-—}" "$C_DIM" "$C_RESET" "${EVENT_COUNT:-0}" \
      "$C_DIM" "$C_RESET" "${COMPACTION_COUNT:-0}" "$C_DIM" "$C_RESET" "$agent_count" "$C_RESET"
    printf '  %s└─%s %s%s%s\n' "$C_DIM" "$color" "$message" "$C_RESET" "$C_RESET"
  else
    printf '[%s] %s fase=%s sprint=%s eventos=%s agentes=%s — %s\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "$icon" "$phase" "${NEXT_ID:-—}" \
      "${EVENT_COUNT:-0}" "$agent_count" "$message"
  fi
}

status_update() {
  local phase="$1" message="$2"
  STATUS_PATH="$STATE_ROOT/status.json" STATUS_MD_PATH="$STATE_ROOT/status.md" \
    STATUS_PHASE="$phase" STATUS_MESSAGE="$message" STATUS_RUN_ID="${RUN_ID:-}" \
    STATUS_SPRINT="${NEXT_ID:-}" STATUS_SESSION="${SESSION_ID:-}" \
    STATUS_EVENT_COUNT="${EVENT_COUNT:-}" STATUS_TURN_COUNT="${TURN_COUNT:-}" \
    STATUS_COMPACTION_COUNT="${COMPACTION_COUNT:-}" \
    STATUS_LAST_AGENT="${LAST_AGENT_MESSAGE:-}" STATUS_PAUSE_UNTIL="${PAUSE_UNTIL:-}" \
    STATUS_AGENTS_JSON="${AGENTS_JSON:-[]}" \
    STATUS_ACCOUNT="${ACTIVE_ACCOUNT_ID:-}" \
    STATUS_CONTROLLER="${CONTROLLER:-chat}" STATUS_SUPERVISOR_ROLE="${CONTROLLER:-chat}" \
    STATUS_MODEL="${CODEX_MODEL:-}" STATUS_REASONING="${CODEX_REASONING:-}" \
    STATUS_SUBAGENT_MODEL="${SUBAGENT_MODEL:-}" STATUS_SUBAGENT_REASONING="${SUBAGENT_REASONING:-}" \
    STATUS_PUSH_MODE="${PUSH_MODE:-never}" STATUS_PUSH_EVERY="${PUSH_EVERY:-4}" \
    node <<'NODE'
const fs = require('fs');
const path = process.env.STATUS_PATH;
let status = {};
if (fs.existsSync(path)) { try { status = JSON.parse(fs.readFileSync(path, 'utf8').replace(/^\uFEFF/, '')); } catch {} }
Object.assign(status, {
  phase: process.env.STATUS_PHASE,
  message: process.env.STATUS_MESSAGE,
  controller: process.env.STATUS_CONTROLLER || status.controller || 'chat',
  supervisor_role: process.env.STATUS_SUPERVISOR_ROLE === 'chat'
    ? 'supervisor do chat'
    : process.env.STATUS_SUPERVISOR_ROLE === 'runner'
      ? 'runner legado'
      : (status.supervisor_role || 'supervisor do chat'),
  run_id: process.env.STATUS_RUN_ID || null,
  sprint: process.env.STATUS_SPRINT || null,
  session_id: process.env.STATUS_SESSION || null,
  account: process.env.STATUS_ACCOUNT || status.account || null,
  event_count: process.env.STATUS_EVENT_COUNT === '' ? (status.event_count || 0) : Number(process.env.STATUS_EVENT_COUNT),
  turn_count: process.env.STATUS_TURN_COUNT === '' ? (status.turn_count || 0) : Number(process.env.STATUS_TURN_COUNT),
  compaction_count: process.env.STATUS_COMPACTION_COUNT === '' ? (status.compaction_count || 0) : Number(process.env.STATUS_COMPACTION_COUNT),
  last_agent_message: process.env.STATUS_LAST_AGENT === '' ? null : process.env.STATUS_LAST_AGENT,
  pause_until: process.env.STATUS_PAUSE_UNTIL === '' ? null : process.env.STATUS_PAUSE_UNTIL,
  model: process.env.STATUS_MODEL || status.model || null,
  reasoning_effort: process.env.STATUS_REASONING || status.reasoning_effort || null,
  subagent_model: process.env.STATUS_SUBAGENT_MODEL || status.subagent_model || null,
  subagent_reasoning_effort: process.env.STATUS_SUBAGENT_REASONING || status.subagent_reasoning_effort || null,
  push_mode: process.env.STATUS_PUSH_MODE || status.push_mode || 'never',
  push_every: Number(process.env.STATUS_PUSH_EVERY || status.push_every || 4),
  agents: (() => { try { return JSON.parse(process.env.STATUS_AGENTS_JSON || '[]'); } catch { return status.agents || []; } })(),
  updated_at: new Date().toISOString()
});
const tmp = `${path}.${process.pid}.tmp`;
fs.writeFileSync(tmp, JSON.stringify(status, null, 2));
fs.renameSync(tmp, path);
const mdValue = value => String(value ?? '—').replace(/\r?\n/g, ' ').replace(/\|/g, '\\|');
const agents = Array.isArray(status.agents) ? status.agents : [];
const agentRows = agents.length
  ? agents.map(agent => `| ${mdValue(agent.name || agent.id)} | ${mdValue(agent.status || 'unknown')} | ${mdValue(agent.reasoning_effort || '—')} | ${mdValue(agent.task || '—')} | ${mdValue(agent.message || '—')} |`).join('\n')
  : '| — | nenhum evento identificado | — | — | — |';
const md = `# Deskverse · Supervisor de sprints\n\n` +
  `> Painel operacional atualizado em **${mdValue(status.updated_at)}**.\n\n` +
  `| Campo | Valor |\n|---|---|\n` +
  `| Fase | **${mdValue(status.phase)}** |\n` +
  `| Sprint | ${mdValue(status.sprint)} |\n` +
  `| Mensagem | ${mdValue(status.message)} |\n` +
  `| Controlador | ${mdValue(status.controller === 'chat' ? 'Supervisor do chat' : 'Runner legado')} |\n` +
  `| Supervisor | ${mdValue(status.supervisor_role)} |\n` +
  `| Eventos JSONL | ${mdValue(status.event_count || 0)} |\n` +
  `| Turnos | ${mdValue(status.turn_count || 0)} |\n` +
  `| Compactações | ${mdValue(status.compaction_count || 0)} |\n` +
  `| Sessão | ${mdValue(status.session_id)} |\n` +
  `| Conta | ${mdValue(status.account)} |\n` +
  `| Executor / runner legado | ${mdValue(status.controller === 'chat' ? 'não iniciado pelo script' : `${status.model} / ${status.reasoning_effort}`)} |\n` +
  `| Subagentes nativos | ${mdValue(status.subagent_model)} / ${mdValue(status.subagent_reasoning_effort)} |\n` +
  `| Push | ${mdValue(status.push_mode)} (a cada ${mdValue(status.push_every)} commit(s)) |\n` +
  `| Pausa até | ${mdValue(status.pause_until)} |\n\n` +
  `## Agentes coordenados\n\n` +
  `| Agente | Estado | Raciocínio | Tarefa | Última atualização |\n|---|---|---|---|---|\n${agentRows}\n` +
  (status.last_agent_message ? `\n## Última mensagem do agente\n\n${mdValue(status.last_agent_message)}\n` : '');
const mdTmp = `${process.env.STATUS_MD_PATH}.${process.pid}.tmp`;
fs.writeFileSync(mdTmp, md);
fs.renameSync(mdTmp, process.env.STATUS_MD_PATH);
NODE
  if [[ "$MODE" == "run" ]]; then
    local agent_count
    agent_count="$(node -e 'try { const x=JSON.parse(process.argv[1]); process.stdout.write(String(x.length)); } catch { process.stdout.write("0"); }' "${AGENTS_JSON:-[]}")"
    local signature="${phase}|${message}|${agent_count}"
    if [[ "$signature" != "$LAST_UI_STATUS_SIGNATURE" ]]; then
      ui_render_status "$phase" "$message" "$agent_count"
      LAST_UI_STATUS_SIGNATURE="$signature"
    fi
  fi
}

print_final_status() {
  [[ "$MODE" == "run" && -t 1 ]] || return 0
  [[ -f "$STATE_ROOT/status.json" ]] || return 0
  printf '\n%s╭─ %sEXECUÇÃO FINALIZADA%s ───────────────────────────────╮%s\n' \
    "$C_DIM" "$C_BOLD" "$C_DIM" "$C_RESET"
  STATE_PATH="$STATE_ROOT/status.json" node <<'NODE'
const fs = require('fs');
  try {
    const s = JSON.parse(fs.readFileSync(process.env.STATE_PATH, 'utf8'));
    const value = v => String(v ?? '—').replace(/\r?\n/g, ' ');
  const agents = Array.isArray(s.agents) ? s.agents : [];
  console.log(`│ controlador ${value(s.controller === 'runner' ? 'runner legado' : 'supervisor do chat')}`);
  console.log(`│ fase        ${value(s.phase)}`);
  console.log(`│ sprint      ${value(s.sprint)}`);
  console.log(`│ conta       ${value(s.account)}`);
  console.log(`│ mensagem    ${value(s.message)}`);
  console.log(`│ eventos     ${value(s.event_count)}   turnos ${value(s.turn_count)}   compactações ${value(s.compaction_count || 0)}   agentes ${agents.length}`);
  console.log(`│ push        ${value(s.push_mode)}   limiar ${value(s.push_every || 4)} commit(s)`);
  if (agents.length) for (const a of agents) {
    const effort = a.reasoning_effort ? ` [${a.reasoning_effort}]` : '';
    console.log(`│   └─ ${value(a.name || a.id)} · ${value(a.status)}${effort}${a.message ? ` · ${value(a.message)}` : ''}`);
  }
  if (s.pause_until) console.log(`│ pausa       ${value(s.pause_until)}`);
} catch {}
NODE
  printf '%s╰──────────────────────────────────────────────────────────╯%s\n' "$C_DIM" "$C_RESET"
  printf '%s  arquivos: %s/status.json  ·  %s/status.md%s\n' "$C_DIM" "$STATE_ROOT" "$STATE_ROOT" "$C_RESET"
}

log() {
  local message="$*"
  if [[ "$MODE" != "run" ]]; then
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message"
  fi
  status_update "$STATUS_PHASE" "$message"
}

stream_codex_stdout() {
  local stream_path="$1"
  STREAM_PATH="$stream_path" node <<'NODE'
const fs = require('fs');
const readline = require('readline');
const raw = fs.createWriteStream(process.env.STREAM_PATH, { flags: 'a' });
raw.on('error', () => {});
const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
// A tarefa pode estar sendo executada sem um terminal persistente (Agendador,
// pipe do Git Bash ou painel do Codex). Se o consumidor da saída desaparecer,
// não encerre o leitor JSONL: o log em disco ainda precisa receber o restante.
let outputOpen = true;
process.stdout.on('error', error => {
  if (error && error.code === 'EPIPE') outputOpen = false;
});
process.stdin.on('error', () => rl.close());
const tty = Boolean(process.stdout.isTTY) && !process.env.NO_COLOR;
const colors = tty ? { reset: '\x1b[0m', dim: '\x1b[2m', cyan: '\x1b[36m', blue: '\x1b[34m', green: '\x1b[32m', yellow: '\x1b[33m', red: '\x1b[31m' } : { reset: '', dim: '', cyan: '', blue: '', green: '', yellow: '', red: '' };
const clean = value => String(value ?? '').replace(/\r?\n/g, ' ').trim().slice(-700);
const emit = (icon, message, color = 'dim') => {
  if (!outputOpen) return;
  try { process.stdout.write(`  ${colors[color] || ''}${icon}${colors.reset} ${clean(message)}\n`); } catch (error) {
    if (error && error.code === 'EPIPE') outputOpen = false;
  }
};
const progress = text => {
  const matches = String(text || '').matchAll(/AGENT_PROGRESS:\s*(\{.*?\})(?=$|\r?\n)/g);
  for (const match of matches) {
    try {
      const a = JSON.parse(match[1]);
      emit('├─', `agente ${a.name || a.id || '—'} · ${a.status || 'observado'}${a.reasoning_effort ? ` [${a.reasoning_effort}]` : ''} · ${a.message || a.task || '—'}`, a.status === 'failed' || a.status === 'blocked' ? 'red' : 'blue');
    } catch {}
  }
};
const format = line => {
  let event;
  try { event = JSON.parse(line); } catch { emit('│', line, 'red'); return; }
  const item = event.item || {};
  const type = String(event.type || item.type || '').toLowerCase();
  const text = item.text || item.message || event.message || '';
  progress(text);
  if (type === 'thread.started') emit('◆', `sessão ${event.thread_id || event.threadId || 'iniciada'}`, 'cyan');
  else if (type === 'turn.started') emit('›', 'turno iniciado', 'cyan');
  else if (type === 'turn.completed') {
    const usage = event.usage || {};
    emit('✓', `turno concluído · entrada ${usage.input_tokens || 0} · saída ${usage.output_tokens || 0}`, 'green');
  } else if (type === 'error' || type.endsWith('.error')) emit('!', text || event.error || 'erro reportado', 'red');
  else if (type === 'item.started') {
    const label = item.name || item.tool || item.command || item.type || 'atividade';
    const normalized = String(item.type || '').toLowerCase().replace(/[_-]/g, '');
    if (normalized === 'contextcompaction') emit('≈', 'compactação de contexto iniciada', 'yellow');
    else if (item.type !== 'agent_message') emit('↳', label, 'cyan');
  } else if (type === 'item.completed') {
    const normalized = String(item.type || '').toLowerCase().replace(/[_-]/g, '');
    if (normalized === 'contextcompaction') emit('✓', 'compactação de contexto concluída', 'yellow');
    else if (item.type === 'agent_message' && text) emit('│', text, 'green');
    else if (item.type === 'command_execution') emit('·', item.command || 'comando concluído', 'dim');
    else if (item.type === 'file_change') emit('·', 'alteração de arquivo concluída', 'dim');
  }
};
rl.on('line', line => { raw.write(`${line}\n`); if (line.trim()) format(line); });
rl.on('close', () => raw.end());
NODE
}

stream_codex_stderr() {
  local stream_path="$1" line
  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "$line" >> "$stream_path"
    local summary=""
    case "$line" in
      *apply_patch*verification\ failed*|*apply_patch*Failed\ to\ find\ expected\ lines*)
        summary='patch não corresponde ao arquivo'
        STREAM_ERROR_CONTEXT='apply_patch'
        ;;
      *code-mode\ host\ closed\ its\ stdout*)
        summary='canal do agente foi fechado'
        ;;
      *failed\ printing\ to\ stdout*)
        summary='saída do agente foi fechada'
        ;;
      *Reading\ additional\ input\ from\ stdin*)
        summary='agente verificou entrada padrão'
        ;;
      *ERROR*|*error=*|*panic*|*failed*)
        summary='erro técnico; consulte o log'
        ;;
    esac
    if [[ "$STREAM_ERROR_CONTEXT" == 'apply_patch' && -z "$summary" ]]; then
      # apply_patch prints the unmatched source lines on subsequent indented
      # stderr lines; keep those details only in the raw log.
      if [[ -z "$line" || "$line" =~ ^[[:space:]] ]]; then continue; fi
      STREAM_ERROR_CONTEXT=""
    fi
    [[ -n "$summary" ]] || summary="$line"
    if [[ -t 2 ]]; then
      printf '  %s⚠ stderr%s %s\n' "$C_RED" "$C_RESET" "$summary" >&2 || true
    else
      printf '[%s] stderr: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$summary" >&2 || true
    fi
  done
}

stream_browser_stdout() {
  local stream_path="$1" line
  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "$line" >> "$stream_path"
    if [[ -t 1 ]]; then
      printf '  %s│ browser%s %s\n' "$C_BLUE" "$C_RESET" "$line" || true
    else
      printf '[%s] browser: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$line" || true
    fi
  done
}

stream_browser_stderr() {
  local stream_path="$1" line
  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "$line" >> "$stream_path"
    if [[ -t 2 ]]; then
      printf '  %s⚠ browser%s %s\n' "$C_RED" "$C_RESET" "$line" >&2 || true
    else
      printf '[%s] browser stderr: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$line" >&2 || true
    fi
  done
}
