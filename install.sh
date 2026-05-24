#!/usr/bin/env bash
set -euo pipefail

# DeepSeek OAuth Bridge -> Pi installer
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/gayakaci/deepseek-oauth/main/install.sh | bash
# Optional:
#   DEEPSEEK_EMAIL=you@example.com DEEPSEEK_PASSWORD='...' bash install.sh

APP_NAME="deepseek-oauth"
APP_DIR="${DEEPSEEK_OAUTH_DIR:-$HOME/.deepseek-oauth}"
PI_AGENT_DIR="${PI_AGENT_DIR:-$HOME/.pi/agent}"
CONFIG_PATH="${DEEPSEEK_OAUTH_CONFIG:-}"
KEY_SCRIPT="$PI_AGENT_DIR/deepseek-oauth-key.sh"
PI_MODELS_JSON="$PI_AGENT_DIR/models.json"
PORT="${DEEPSEEK_OAUTH_PORT:-5001}"
BASE_URL="${DEEPSEEK_OAUTH_BASE_URL:-http://127.0.0.1:${PORT}/v1}"
RAW_URL="https://raw.githubusercontent.com/gayakaci/deepseek-oauth/main/install.sh"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

random_key() {
  if command -v openssl >/dev/null 2>&1; then
    printf 'dso-%s\n' "$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=\n')"
  else
    python3 - <<'PY'
import secrets
print('dso-' + secrets.token_urlsafe(32))
PY
  fi
}

looks_like_placeholder_key() {
  [[ "$1" == *DEEPSEEK_OAUTH_CLIENT_KEY* || "$1" == '$'* ]]
}

prompt_read() {
  local prompt="$1"
  local secret="${2:-false}"
  local value
  if [[ -r /dev/tty ]]; then
    printf '%s' "$prompt" > /dev/tty
    if [[ "$secret" == "true" ]]; then
      IFS= read -rs value < /dev/tty
      printf '\n' > /dev/tty
    else
      IFS= read -r value < /dev/tty
    fi
  else
    printf '%s' "$prompt" >&2
    if [[ "$secret" == "true" ]]; then
      IFS= read -rs value
      printf '\n' >&2
    else
      IFS= read -r value
    fi
  fi
  printf '%s' "$value"
}

detect_running_ds2api_config() {
  command -v lsof >/dev/null 2>&1 || return 1
  command -v ps >/dev/null 2>&1 || return 1
  local pid command_line config_path
  pid="$(lsof -ti "tcp:${PORT}" 2>/dev/null | head -n 1 || true)"
  [[ -n "$pid" ]] || return 1
  command_line="$(ps eww -p "$pid" -o command= 2>/dev/null || true)"
  [[ "$command_line" == *DS2API_CONFIG_PATH=* ]] || return 1
  config_path="$(printf '%s\n' "$command_line" | sed -n 's/.*DS2API_CONFIG_PATH=\([^ ]*\).*/\1/p' | head -n 1)"
  [[ -n "$config_path" && -f "$config_path" ]] || return 1
  printf '%s\n' "$config_path"
}

need_cmd python3
need_cmd mkdir
need_cmd chmod

if [[ -z "$CONFIG_PATH" ]]; then
  CONFIG_PATH="$(detect_running_ds2api_config || true)"
  if [[ -n "$CONFIG_PATH" ]]; then
    echo "Detected running DS2API config: $CONFIG_PATH"
  else
    CONFIG_PATH="$APP_DIR/config.json"
  fi
fi

if ! command -v pi >/dev/null 2>&1; then
  echo "Warning: pi command not found. Install Pi first:" >&2
  echo "  npm install -g @earendil-works/pi-coding-agent" >&2
fi

mkdir -p "$APP_DIR" "$PI_AGENT_DIR" "$(dirname "$CONFIG_PATH")"
chmod 700 "$APP_DIR" "$PI_AGENT_DIR" "$(dirname "$CONFIG_PATH")" 2>/dev/null || true

if [[ -f "$CONFIG_PATH" ]]; then
  echo "Keeping existing $CONFIG_PATH"
else
  email="${DEEPSEEK_EMAIL:-}"
  password="${DEEPSEEK_PASSWORD:-}"
  client_key="${DEEPSEEK_OAUTH_CLIENT_KEY:-$(random_key)}"
  if looks_like_placeholder_key "$client_key"; then
    client_key="$(random_key)"
  fi

  if [[ -z "$email" ]]; then
    email="$(prompt_read 'DeepSeek email/mobile: ')"
  fi
  if [[ -z "$password" ]]; then
    password="$(prompt_read 'DeepSeek password: ' true)"
  fi

  umask 077
  python3 - "$CONFIG_PATH" "$email" "$password" "$client_key" "$PORT" <<'PY'
import json, pathlib, sys
path, email, password, client_key, port = sys.argv[1:6]
account = {"password": password}
if email.startswith('+') or email.replace(' ', '').replace('-', '').isdigit():
    account["mobile"] = email
else:
    account["email"] = email
cfg = {
  "listen": f"127.0.0.1:{port}",
  "keys": [client_key],
  "api_keys": [{
    "key": client_key,
    "name": "Pi",
    "remark": "deepseek-oauth local client"
  }],
  "accounts": [account],
  "default_model": "deepseek-v4-pro",
  "current_input_file": {
    "enabled": False
  }
}
pathlib.Path(path).write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  chmod 600 "$CONFIG_PATH"
  echo "Created $CONFIG_PATH"
fi

repaired_key="$(random_key)"
if python3 - "$CONFIG_PATH" "$repaired_key" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
new_key = sys.argv[2]
cfg = json.loads(path.read_text(encoding="utf-8"))
def bad_key(value):
    return not isinstance(value, str) or not value.strip() or "DEEPSEEK_OAUTH_CLIENT_KEY" in value or value.startswith("$")
def first_string(values):
    if isinstance(values, list):
        for value in values:
            if isinstance(value, str) and value.strip():
                return value.strip()
    return ""
key = first_string(cfg.get("keys"))
if bad_key(key):
    key = first_string(cfg.get("client_keys"))
if bad_key(key):
    key = new_key
changed = False
if cfg.get("keys") != [key]:
    cfg["keys"] = [key]
    changed = True
api_keys = cfg.get("api_keys")
valid_api_keys = isinstance(api_keys, list) and any(isinstance(item, dict) and item.get("key") == key for item in api_keys)
if not valid_api_keys:
    cfg["api_keys"] = [{"key": key, "name": "Pi", "remark": "deepseek-oauth local client"}]
    changed = True
for account in cfg.get("accounts") or []:
    if not isinstance(account, dict):
        continue
    secret = account.pop("secret", None)
    if secret is not None:
        changed = True
        if not account.get("password") and not account.get("token"):
            account["password"] = secret
if "client_keys" in cfg:
    del cfg["client_keys"]
    changed = True
current_input_file = cfg.get("current_input_file")
if isinstance(current_input_file, dict) and current_input_file.get("enabled") is True:
    current_input_file["enabled"] = False
    changed = True
if not changed:
    sys.exit(0)
path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
sys.exit(2)
PY
then
  :
else
  status=$?
  if [[ "$status" -eq 2 ]]; then
    chmod 600 "$CONFIG_PATH"
    echo "Updated client key config in $CONFIG_PATH"
  else
    echo "Failed to validate $CONFIG_PATH" >&2
    exit "$status"
  fi
fi

cat > "$KEY_SCRIPT" <<EOF
#!/usr/bin/env bash
set -euo pipefail
looks_like_placeholder_key() {
  [[ "\$1" == *DEEPSEEK_OAUTH_CLIENT_KEY* || "\$1" == '$'* ]]
}
if [[ -n "\${DEEPSEEK_OAUTH_CLIENT_KEY:-}" ]] && ! looks_like_placeholder_key "\$DEEPSEEK_OAUTH_CLIENT_KEY"; then
  printf '%s\\n' "\$DEEPSEEK_OAUTH_CLIENT_KEY"
  exit 0
fi
CONFIG_PATH="\${DEEPSEEK_OAUTH_CONFIG:-$CONFIG_PATH}"
python3 - "\$CONFIG_PATH" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    cfg = json.load(f)
keys = cfg.get('keys') or cfg.get('client_keys') or []
if isinstance(keys, list) and keys:
    key = keys[0]
    if isinstance(key, str) and 'DEEPSEEK_OAUTH_CLIENT_KEY' not in key and not key.startswith('$'):
        print(key)
        sys.exit(0)
sys.exit('No client key found in deepseek-oauth config')
PY
EOF
chmod 700 "$KEY_SCRIPT"
if ! "$KEY_SCRIPT" >/dev/null; then
  echo "Generated API-key helper failed: $KEY_SCRIPT" >&2
  exit 1
fi

python3 - "$PI_MODELS_JSON" "$BASE_URL" "$KEY_SCRIPT" <<'PY'
import json, pathlib, sys
models_path, base_url, key_script = sys.argv[1:4]
path = pathlib.Path(models_path)
if path.exists() and path.read_text(encoding='utf-8').strip():
    data = json.loads(path.read_text(encoding='utf-8'))
else:
    data = {}
providers = data.setdefault('providers', {})
zero = {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
def m(mid, name, images=False):
    return {
        "id": mid,
        "name": name,
        "reasoning": True,
        "input": ["text", "image"] if images else ["text"],
        "contextWindow": 128000,
        "maxTokens": 8192,
        "cost": zero
    }
providers['deepseek-oauth'] = {
    "baseUrl": base_url,
    "api": "openai-completions",
    "apiKey": f"!{key_script}",
    "compat": {
        "supportsDeveloperRole": True,
        "supportsReasoningEffort": True
    },
    "models": [
        m("deepseek-v4-flash", "DeepSeek OAuth V4 Flash"),
        m("deepseek-v4-pro", "DeepSeek OAuth V4 Pro"),
        m("deepseek-v4-flash-search", "DeepSeek OAuth V4 Flash Search"),
        m("deepseek-v4-pro-search", "DeepSeek OAuth V4 Pro Search"),
        m("deepseek-v4-vision", "DeepSeek OAuth V4 Vision", images=True)
    ]
}
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding='utf-8')
PY
chmod 600 "$PI_MODELS_JSON" 2>/dev/null || true

cat > "$APP_DIR/start.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
CONFIG="\${DEEPSEEK_OAUTH_CONFIG:-$CONFIG_PATH}"
if command -v deepseek-oauth >/dev/null 2>&1; then
  exec deepseek-oauth serve --config "\$CONFIG"
fi
echo "deepseek-oauth bridge binary not found." >&2
echo "Install/build the bridge, then run: deepseek-oauth serve --config \"\$CONFIG\"" >&2
exit 127
EOF
chmod 700 "$APP_DIR/start.sh"

echo
echo "Pi provider installed: deepseek-oauth"
echo "Config: $CONFIG_PATH"
echo "Start bridge: $APP_DIR/start.sh"
echo "Use Pi: pi --model deepseek-oauth/deepseek-v4-pro"
echo
echo "One-liner: curl -fsSL $RAW_URL | bash"
