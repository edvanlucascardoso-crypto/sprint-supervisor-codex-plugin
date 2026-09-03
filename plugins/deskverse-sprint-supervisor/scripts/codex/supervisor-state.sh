# Persistência, fila, orçamento e leitura de agentes do supervisor.
# Este arquivo é carregado por sprint-supervisor.sh; não deve ser executado só.

agents_snapshot() {
  local stream_path="$1"
  STDOUT_PATH="$stream_path" node <<'NODE'
const fs = require('fs');
const path = process.env.STDOUT_PATH;
const agents = new Map();
const shortWords = (value, limit = 5) => String(value ?? '')
  .replace(/\s+/g, ' ')
  .trim()
  .split(' ')
  .filter(Boolean)
  .slice(0, limit)
  .join(' ');
if (fs.existsSync(path)) for (const line of fs.readFileSync(path, 'utf8').split(/\r?\n/)) {
  let event; try { event = JSON.parse(line); } catch { continue; }
  const item = event.item || event;
  const type = String(item.type || event.type || '').toLowerCase();
  let args = item.arguments || item.input || item.params || {};
  if (typeof args === 'string') { try { args = JSON.parse(args); } catch {} }
  const agentish = /subagent|collab|spawn[_ -]?agent|delegate/.test(`${type} ${item.name || ''} ${item.tool || ''}`.toLowerCase());
  let id = item.agent_id || item.agentId || item.subagent_id || item.subagentId || args.agent_id || args.agentId;
  if (!id && agentish && item.id) id = `event:${item.id}`;
  if (!id) {
    const text = item.text || item.message || '';
    for (const match of String(text).matchAll(/^AGENT_PROGRESS:\s*(\{.*\})$/gmi)) {
      try {
        const progress = JSON.parse(match[1]);
        if (progress.id) {
          if (progress.message) progress.message = shortWords(progress.message);
          agents.set(progress.id, {...agents.get(progress.id), ...progress});
        }
      } catch {}
    }
    continue;
  }
  const previous = agents.get(id) || { id };
  const status = item.status || (event.type === 'item.completed' ? 'completed' : event.type === 'item.started' ? 'running' : previous.status || 'observed');
  const message = item.last_assistant_message || item.text || item.message || item.output || previous.message || null;
  agents.set(id, {
    ...previous, id,
    name: item.agent_type || item.agentType || args.agent_type || args.agentType || item.name || previous.name || id,
    task: item.task || item.prompt || args.task || args.prompt || previous.task || null,
    status, message: message ? shortWords(String(message)) : null,
    event_type: item.type || event.type
  });
}
console.log(JSON.stringify([...agents.values()]));
NODE
}

activity_snapshot() {
  local stream_path="$1"
  STDOUT_PATH="$stream_path" node <<'NODE'
const fs = require('fs');
const path = process.env.STDOUT_PATH;
if (!fs.existsSync(path)) { process.stdout.write('iniciando execução'); process.exit(0); }
const shortWords = (value, limit = 5) => String(value ?? '')
  .replace(/\s+/g, ' ')
  .trim()
  .split(' ')
  .filter(Boolean)
  .slice(0, limit)
  .join(' ');
const commandSummary = command => {
  const text = String(command || '').toLowerCase();
  if (/npm\s+(run\s+)?test|vitest|jest/.test(text)) return 'executando testes';
  if (/playwright|chromium|browser/.test(text)) return 'validando no navegador';
  if (/npm\s+(run\s+)?build|next\s+build/.test(text)) return 'executando build';
  if (/git\s+(add|commit)/.test(text)) return 'preparando commit';
  if (/git\s+(status|diff)|rg\s|findstr\s|select-string/.test(text)) return 'inspecionando arquivos';
  if (/get-content|type\s/.test(text)) return 'lendo arquivos';
  return 'executando comando';
};
let activity = '';
for (const line of fs.readFileSync(path, 'utf8').split(/\r?\n/)) {
  if (!line.trim()) continue;
  let event; try { event = JSON.parse(line); } catch { continue; }
  const item = event.item || event;
  const eventType = String(event.type || '').toLowerCase();
  const itemType = String(item.type || '').toLowerCase();
  if (eventType === 'item.started') {
    if (itemType === 'command_execution') activity = commandSummary(item.command);
    else if (itemType.includes('contextcompaction')) activity = 'compactando contexto';
    else if (itemType.includes('mcp') || itemType.includes('tool')) activity = 'usando ferramenta';
    else if (itemType === 'agent_message') activity = 'preparando atualização';
    else activity = shortWords(item.name || itemType || 'processando sprint');
  }
  if (eventType === 'turn.started') activity = 'iniciando turno';
}
process.stdout.write(activity || 'processando sprint');
NODE
}

account_selection() {
  local accounts_json="$1" preferred="${2:-}"
  ACCOUNTS_JSON="$accounts_json" ACCOUNT_PREFERRED="$preferred" STATE_PATH="$STATE_PATH" node <<'NODE'
const fs = require('fs');
const os = require('os');
const path = require('path');
const raw = JSON.parse(process.env.ACCOUNTS_JSON || '{}');
const state = fs.existsSync(process.env.STATE_PATH)
  ? JSON.parse(fs.readFileSync(process.env.STATE_PATH, 'utf8').replace(/^\uFEFF/, ''))
  : {};
const profiles = Array.isArray(raw) ? raw : (Array.isArray(raw.profiles) ? raw.profiles : []);
if (raw.enabled === false || profiles.length === 0) {
  console.log(JSON.stringify({ action: 'disabled' }));
  process.exit(0);
}
const expand = value => {
  let result = String(value || '').trim();
  result = result.replace(/%([^%]+)%/g, (_, key) => process.env[key] || `%${key}%`);
  result = result.replace(/\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/g, (_, key) => process.env[key] || `$${key}`);
  if (result === '~') result = os.homedir();
  else if (result.startsWith(`~${path.sep}`) || result.startsWith('~/')) result = path.join(os.homedir(), result.slice(2));
  return path.resolve(result);
};
const cooldowns = state.account_cooldowns || {};
const now = Date.now();
const normalized = profiles.map((profile, index) => ({
  id: String(profile.id || `account-${index + 1}`),
  rawHome: String(profile.codex_home || profile.home || '').trim(),
  home: expand(profile.codex_home || profile.home || ''),
  enabled: profile.enabled !== false,
  index,
})).filter(profile => profile.enabled && profile.rawHome);
const ready = profile => {
  const until = cooldowns[profile.id];
  if (until && Date.parse(until) > now) return false;
  return fs.existsSync(path.join(profile.home, 'auth.json')) || Boolean(process.env.CODEX_ACCESS_TOKEN);
};
const preferred = process.env.ACCOUNT_PREFERRED || '';
const ordered = [...normalized].sort((a, b) => {
  if (a.id === preferred) return -1;
  if (b.id === preferred) return 1;
  return a.index - b.index;
});
const selected = ordered.find(ready);
if (selected) {
  console.log(JSON.stringify({ action: 'selected', id: selected.id, home: selected.home }));
  process.exit(0);
}
const future = normalized
  .map(profile => cooldowns[profile.id])
  .filter(Boolean)
  .map(value => Date.parse(value))
  .filter(value => Number.isFinite(value) && value > now)
  .sort((a, b) => a - b);
const missing = normalized.filter(profile => !fs.existsSync(path.join(profile.home, 'auth.json'))).map(profile => profile.id);
console.log(JSON.stringify({
  action: missing.length ? 'needs_setup' : (future.length ? 'all_exhausted' : 'needs_setup'),
  pause_until: future.length ? new Date(future[0]).toISOString() : null,
  missing,
}));
NODE
}

validate_accounts() {
  ACCOUNTS_JSON="$1" node <<'NODE'
const raw = JSON.parse(process.env.ACCOUNTS_JSON || '{}');
if (raw.enabled === false) process.exit(0);
const profiles = Array.isArray(raw.profiles) ? raw.profiles : [];
const ids = new Set();
for (const [index, profile] of profiles.entries()) {
  const id = String(profile?.id || `account-${index + 1}`).trim();
  const home = String(profile?.codex_home || profile?.home || '').trim();
  if (!home) { console.error(`Conta ${id} não possui codex_home.`); process.exit(1); }
  if (ids.has(id)) { console.error(`ID de conta duplicado: ${id}`); process.exit(1); }
  ids.add(id);
}
if (profiles.length === 0) { console.error('accounts.enabled exige ao menos um profile.'); process.exit(1); }
NODE
}

is_ignored_checkout_path() {
  local path="$1"
  # Git status uses the path after the two-character status prefix. Remove
  # optional quoting before checking reserved Windows device names and the
  # supervisor's root-level scratch directory.
  path="${path#\"}"
  path="${path%\"}"
  [[ "$path" =~ (^|/)(nul|con|prn|aux|clock\$)(/|$) || "$path" =~ ^work(/|$) ]]
}

filter_ignored_checkout_paths() {
  local line path
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    path="${line:3}"
    if is_ignored_checkout_path "$path"; then
      if [[ "$path" =~ ^work(/|$) ]]; then
        log "Ignorando scratch local do supervisor: $path" >&2
      else
        log "Ignorando arquivo não editável/bloqueado pelo Windows: $path" >&2
      fi
      continue
    fi
    printf '%s\n' "$line"
  done
}

checkout_dirty_without_ignored() {
  local dirty_paths
  dirty_paths="$(git status --porcelain)"
  [[ -n "$dirty_paths" ]] || return 0
  filter_ignored_checkout_paths <<< "$dirty_paths"
}

commit_dirty_checkpoint() {
  local dirty_paths="$1"
  local safe_dirty_paths
  if [[ "$AUTO_COMMIT_DIRTY" != "true" ]]; then
    return 1
  fi
  safe_dirty_paths="$(filter_ignored_checkout_paths <<< "$dirty_paths")"
  if [[ -z "$safe_dirty_paths" ]]; then
    log 'Somente arquivos ignorados (scratch ou bloqueados) foram encontrados; a sprint continuará.'
    return 0
  fi
  if printf '%s\n' "$safe_dirty_paths" | grep -Eiq '(^|[[:space:]])(.env($|\.)|.*(secret|credential|token|password|\.pem$|\.key$))'; then
    log 'Alterações sensíveis detectadas; checkpoint automático bloqueado.'
    return 1
  fi
  log "Criando checkpoint commit para $NEXT_ID antes da execução."
  # Stage tracked changes first, then add only safe untracked paths. A single
  # reserved/uneditable path must not make `git add -A` abort the checkpoint.
  if ! git add -u; then
    log 'Não foi possível preparar todas as alterações rastreadas; continuando com os arquivos disponíveis.'
  fi
  while IFS= read -r -d '' path; do
    if is_ignored_checkout_path "$path"; then
      if [[ "$path" =~ ^work(/|$) ]]; then
        log "Ignorando scratch local do supervisor: $path"
      else
        log "Ignorando arquivo não editável/bloqueado pelo Windows: $path"
      fi
      continue
    fi
    if ! git add -- "$path"; then
      log "Não foi possível adicionar $path; arquivo ignorado e execução continuará."
    fi
  done < <(git ls-files --others --exclude-standard -z)
  if git diff --cached --quiet; then return 0; fi
  if ! git commit -m "chore(supervisor): checkpoint pending changes for $NEXT_ID"; then
    log 'Não foi possível criar o checkpoint commit.'
    return 1
  fi
  if ! maybe_push_after_commit false; then return 1; fi
  log "Checkpoint commit criado; a sprint continuará a partir dele."
}

ensure_state() {
  if [[ -f "$STATE_PATH" ]]; then return; fi
  STATE_PATH="$STATE_PATH" QUEUE_PATH="$QUEUE_PATH" node <<'NODE'
const fs = require('fs');
const statePath = process.env.STATE_PATH;
const queue = JSON.parse(fs.readFileSync(process.env.QUEUE_PATH, 'utf8').replace(/^\uFEFF/, ''));
const state = {
  completed: [], current: null, status: 'idle',
  session_id: null, pause_until: null, started_at: null, finished_at: null,
  active_account: null, session_account: null, account_cooldowns: {},
  last_commit: null, last_error: null, budget_remaining_percent: null,
  budget_decision: null,
  push_base_commit: null, commits_since_push: 0, last_push_at: null, last_push_error: null,
  usage: { input_tokens: 0, cached_input_tokens: 0, output_tokens: 0, turns: 0 }
};
fs.writeFileSync(`${statePath}.tmp`, JSON.stringify(state, null, 2));
fs.renameSync(`${statePath}.tmp`, statePath);
NODE
}

reconcile_completed_sprints() {
  STATE_PATH="$STATE_PATH" QUEUE_PATH="$QUEUE_PATH" REPO_ROOT="$REPO_ROOT" node <<'NODE'
const fs = require('fs');
const path = require('path');
const sprintSort = (a, b) => String(a).localeCompare(String(b), undefined, { numeric: true, sensitivity: 'base' });
const statePath = process.env.STATE_PATH;
const state = JSON.parse(fs.readFileSync(statePath, 'utf8').replace(/^\uFEFF/, ''));
const repo = process.env.REPO_ROOT;
const completed = new Set();
const documentIds = new Set();
const walk = dir => fs.existsSync(dir) ? fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
  const full = path.join(dir, entry.name);
  return entry.isDirectory() ? walk(full) : [full];
}) : [];
for (const file of walk(path.join(repo, 'docs', 'sprints'))) {
  const id = path.basename(file).match(/^sprint-(\d+[a-z]?)-/i)?.[1];
  if (!id) continue;
  documentIds.add(id);
  const text = fs.readFileSync(file, 'utf8').slice(0, 2500);
  const status = text.match(/^\s*\*\*Status:\*\*\s*([^\r\n]+)/im)?.[1] || '';
  const normalized = status.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  if (normalized.startsWith('conclu')) completed.add(id);
}
// O documento é a fonte de verdade quando uma sprint é reaberta. Preserve
// apenas evidências antigas cujo documento não esteja mais disponível.
for (const id of state.completed || []) if (!documentIds.has(id)) completed.add(id);
state.completed = [...completed].sort(sprintSort);
fs.writeFileSync(`${statePath}.tmp`, JSON.stringify(state, null, 2));
fs.renameSync(`${statePath}.tmp`, statePath);
NODE
}

state_field() {
  local field="$1"
  STATE_PATH="$STATE_PATH" FIELD="$field" node <<'NODE'
const fs = require('fs');
const state = JSON.parse(fs.readFileSync(process.env.STATE_PATH, 'utf8').replace(/^\uFEFF/, ''));
const value = state[process.env.FIELD];
if (value !== null && value !== undefined) process.stdout.write(typeof value === 'string' ? value : JSON.stringify(value));
NODE
}

state_patch() {
  local patch_json="$1"
  STATE_PATH="$STATE_PATH" PATCH_JSON="$patch_json" node <<'NODE'
const fs = require('fs');
const path = process.env.STATE_PATH;
const state = JSON.parse(fs.readFileSync(path, 'utf8').replace(/^\uFEFF/, ''));
Object.assign(state, JSON.parse(process.env.PATCH_JSON));
fs.writeFileSync(`${path}.tmp`, JSON.stringify(state, null, 2));
fs.renameSync(`${path}.tmp`, path);
NODE
}

# Canal assíncrono supervisor -> executor. Cada mensagem é um arquivo próprio
# para que uma escrita concorrente nunca seja perdida durante a leitura da fila.
message_queue_init() {
  mkdir -p "$STATE_ROOT/messages/pending" "$STATE_ROOT/messages/processing" "$STATE_ROOT/messages/delivered"
}

message_enqueue() {
  local message="$1"
  message_queue_init
  STATE_ROOT="$STATE_ROOT" MESSAGE_TEXT="$message" node <<'NODE'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const root = path.join(process.env.STATE_ROOT, 'messages');
const text = String(process.env.MESSAGE_TEXT || '').trim();
if (!text) { console.error('Mensagem vazia.'); process.exit(2); }
const id = `${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
const payload = { id, created_at: new Date().toISOString(), message: text };
fs.writeFileSync(path.join(root, 'pending', `${id}.json`), JSON.stringify(payload, null, 2));
console.log(JSON.stringify(payload));
NODE
}

message_pending_count() {
  message_queue_init
  STATE_ROOT="$STATE_ROOT" node <<'NODE'
const fs = require('fs');
const path = require('path');
const root = path.join(process.env.STATE_ROOT, 'messages');
const count = name => fs.existsSync(path.join(root, name))
  ? fs.readdirSync(path.join(root, name)).filter(file => file.endsWith('.json')).length : 0;
console.log(count('pending') + count('processing'));
NODE
}

message_recover_processing() {
  message_queue_init
  STATE_ROOT="$STATE_ROOT" node <<'NODE'
const fs = require('fs');
const path = require('path');
const root = path.join(process.env.STATE_ROOT, 'messages');
const processing = path.join(root, 'processing');
const pending = path.join(root, 'pending');
for (const file of fs.readdirSync(processing).filter(name => name.endsWith('.json'))) {
  try { fs.renameSync(path.join(processing, file), path.join(pending, file)); } catch {}
}
NODE
}

# Move uma leva para processing antes de entregá-la ao Codex. O JSON devolvido
# mantém as mensagens intactas para que possam ser confirmadas ou devolvidas.
message_claim_pending() {
  message_queue_init
  STATE_ROOT="$STATE_ROOT" node <<'NODE'
const fs = require('fs');
const path = require('path');
const root = path.join(process.env.STATE_ROOT, 'messages');
const pending = path.join(root, 'pending');
const processing = path.join(root, 'processing');
const files = fs.readdirSync(pending).filter(file => file.endsWith('.json')).sort();
const claimed = [];
for (const file of files) {
  try {
    fs.renameSync(path.join(pending, file), path.join(processing, file));
    claimed.push(JSON.parse(fs.readFileSync(path.join(processing, file), 'utf8')));
  } catch {}
}
console.log(JSON.stringify(claimed));
NODE
}

message_finish_claim() {
  local claim_json="$1"
  STATE_ROOT="$STATE_ROOT" CLAIM_JSON="$claim_json" node <<'NODE'
const fs = require('fs');
const path = require('path');
const root = path.join(process.env.STATE_ROOT, 'messages');
const processing = path.join(root, 'processing');
const delivered = path.join(root, 'delivered');
for (const item of JSON.parse(process.env.CLAIM_JSON || '[]')) {
  const file = `${item.id}.json`;
  try {
    const payload = {...item, delivered_at: new Date().toISOString()};
    fs.writeFileSync(path.join(delivered, file), JSON.stringify(payload, null, 2));
    fs.unlinkSync(path.join(processing, file));
  } catch {}
}
NODE
}

message_release_claim() {
  local claim_json="$1"
  STATE_ROOT="$STATE_ROOT" CLAIM_JSON="$claim_json" node <<'NODE'
const fs = require('fs');
const path = require('path');
const root = path.join(process.env.STATE_ROOT, 'messages');
const processing = path.join(root, 'processing');
const pending = path.join(root, 'pending');
for (const item of JSON.parse(process.env.CLAIM_JSON || '[]')) {
  const file = `${item.id}.json`;
  try { fs.renameSync(path.join(processing, file), path.join(pending, file)); } catch {}
}
NODE
}

add_usage() {
  local usage_json="$1"
  STATE_PATH="$STATE_PATH" USAGE_JSON="$usage_json" node <<'NODE'
const fs = require('fs');
const path = process.env.STATE_PATH;
const state = JSON.parse(fs.readFileSync(path, 'utf8').replace(/^\uFEFF/, ''));
const add = JSON.parse(process.env.USAGE_JSON);
state.usage ||= { input_tokens: 0, cached_input_tokens: 0, output_tokens: 0, turns: 0 };
for (const key of ['input_tokens','cached_input_tokens','output_tokens','turns']) state.usage[key] = Number(state.usage[key] || 0) + Number(add[key] || 0);
fs.writeFileSync(`${path}.tmp`, JSON.stringify(state, null, 2));
fs.renameSync(`${path}.tmp`, path);
NODE
}

add_completed() {
  local sprint_id="$1" commit_hash="$2"
  STATE_PATH="$STATE_PATH" SPRINT_ID="$sprint_id" COMMIT_HASH="$commit_hash" node <<'NODE'
const fs = require('fs');
const path = process.env.STATE_PATH;
const state = JSON.parse(fs.readFileSync(path, 'utf8').replace(/^\uFEFF/, ''));
state.completed ||= [];
if (!state.completed.includes(process.env.SPRINT_ID)) state.completed.push(process.env.SPRINT_ID);
state.status = 'idle'; state.current = null; state.last_commit = process.env.COMMIT_HASH; state.last_error = null;
fs.writeFileSync(`${path}.tmp`, JSON.stringify(state, null, 2));
fs.renameSync(`${path}.tmp`, path);
NODE
}

update_budget() {
  local token_count="$1"
  [[ -f "$BUDGET_PATH" ]] || return 0
  STATE_PATH="$BUDGET_PATH" TOKEN_COUNT="$token_count" node <<'NODE'
const fs = require('fs');
const path = process.env.STATE_PATH;
const budget = JSON.parse(fs.readFileSync(path, 'utf8').replace(/^\uFEFF/, ''));
if (Number(budget.total_tokens || 0) > 0) budget.consumed_tokens = Number(budget.consumed_tokens || 0) + Number(process.env.TOKEN_COUNT || 0);
fs.writeFileSync(`${path}.tmp`, JSON.stringify(budget, null, 2));
fs.renameSync(`${path}.tmp`, path);
NODE
}

now_plus_hours() {
  HOURS="$1" node -e 'console.log(new Date(Date.now()+Number(process.env.HOURS)*3600000).toISOString())'
}

validate_queue() {
  REPO_ROOT="$REPO_ROOT" QUEUE_PATH="$QUEUE_PATH" STATE_PATH="$STATE_PATH" node <<'NODE'
const fs = require('fs');
const path = require('path');
const repo = process.env.REPO_ROOT;
const queue = JSON.parse(fs.readFileSync(process.env.QUEUE_PATH, 'utf8').replace(/^\uFEFF/, ''));
const items = Array.isArray(queue.items) ? queue.items : [];
const state = fs.existsSync(process.env.STATE_PATH)
  ? JSON.parse(fs.readFileSync(process.env.STATE_PATH, 'utf8').replace(/^\uFEFF/, ''))
  : {};
const completed = new Set(state.completed || []);
const ids = new Set(items.map(item => item.id));
const errors = [];
const walk = dir => fs.existsSync(dir) ? fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
  const full = path.join(dir, entry.name);
  return entry.isDirectory() ? walk(full) : [full];
}) : [];
const sprintDocs = walk(path.join(repo, 'docs', 'sprints'))
  .filter(file => /^sprint-\d+[a-z]?-.+\.md$/i.test(path.basename(file)));
for (const file of sprintDocs) {
  const id = path.basename(file).match(/^sprint-(\d+[a-z]?)-/i)?.[1];
  const text = fs.readFileSync(file, 'utf8').slice(0, 2500);
  const status = text.match(/^\s*\*\*Status:\*\*\s*([^\r\n]+)/im)?.[1] || '';
  const normalized = status.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  if (id && normalized.startsWith('conclu')) completed.add(id);
  else if (id) completed.delete(id);
}
for (const item of items) {
  if (!item.id || !item.document) errors.push(`item inválido: ${JSON.stringify(item)}`);
  if (item.document && !fs.existsSync(path.join(repo, item.document))) errors.push(`${item.id}: documento ausente (${item.document})`);
  for (const dependency of item.depends_on || []) if (!ids.has(dependency) && !completed.has(dependency)) errors.push(`${item.id}: dependência ausente (${dependency})`);
}
const pendingDocs = sprintDocs.filter(file => {
  const id = path.basename(file).match(/^sprint-(\d+[a-z]?)-/i)?.[1];
  return id && !completed.has(id);
});
const queuedDocs = new Set(items.map(item => path.normalize(item.document)));
for (const file of pendingDocs) {
  const relative = path.normalize(path.relative(repo, file));
  const sprintId = path.basename(file).match(/^sprint-(\d+[a-z]?)-/i)?.[1];
  if (sprintId && completed.has(sprintId)) continue;
  if (!queuedDocs.has(relative)) errors.push(`sprint pendente fora da fila: ${relative}`);
}
if (errors.length) { for (const error of errors) console.error(`Fila inválida: ${error}`); process.exit(1); }
NODE
}

context_summary_read() {
  local summary_path="$STATE_ROOT/context-summary.md"
  [[ -s "$summary_path" ]] || return 0
  head -c "${SUMMARY_MAX_CHARS:-8000}" "$summary_path"
}

context_summary_write() {
  local sprint="$1" phase="$2" commit_hash="${3:-}" final_text="${4:-}" error_text="${5:-}"
  local summary_path="$STATE_ROOT/context-summary.md"
  mkdir -p "$STATE_ROOT"
  {
    printf '# Contexto compactado do supervisor\n\n'
    printf -- '- Sprint: %s\n- Fase: %s\n- Commit: %s\n- Atualizado: %s\n\n' \
      "${sprint:-—}" "${phase:-—}" "${commit_hash:-—}" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    if [[ -n "$error_text" ]]; then
      printf '## Bloqueio ou erro\n\n%s\n\n' "$error_text"
    fi
    if [[ -n "$final_text" ]]; then
      printf '## Última entrega do executor\n\n'
      printf '%s' "$final_text" | tail -c "${SUMMARY_MAX_CHARS:-8000}"
      printf '\n'
    fi
  } > "${summary_path}.tmp"
  mv "${summary_path}.tmp" "$summary_path"
}
