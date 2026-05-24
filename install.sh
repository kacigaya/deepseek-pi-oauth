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
CONFIG_PATH="$APP_DIR/config.json"
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

need_cmd python3
need_cmd mkdir
need_cmd chmod

if ! command -v pi >/dev/null 2>&1; then
  echo "Warning: pi command not found. Install Pi first:" >&2
  echo "  npm install -g @earendil-works/pi-coding-agent" >&2
fi

mkdir -p "$APP_DIR" "$PI_AGENT_DIR"
chmod 700 "$APP_DIR" "$PI_AGENT_DIR" 2>/dev/null || true

if [[ -f "$CONFIG_PATH" ]]; then
  echo "Keeping existing $CONFIG_PATH"
else
  email="${DEEPSEEK_EMAIL:-}"
  password="${DEEPSEEK_PASSWORD:-}"
  client_key="${DEEPSEEK_OAUTH_CLIENT_KEY:-$(random_key)}"

  if [[ -z "$email" ]]; then
    printf 'DeepSeek email/mobile: '
    read -r email
  fi
  if [[ -z "$password" ]]; then
    printf 'DeepSeek password/token: '
    read -rs password
    printf '\n'
  fi

  umask 077
  python3 - "$CONFIG_PATH" "$email" "$password" "$client_key" "$PORT" <<'PY'
import json, pathlib, sys
path, email, secret, client_key, port = sys.argv[1:6]
account = {"secret": secret}
if email.startswith('+') or email.replace(' ', '').replace('-', '').isdigit():
    account["mobile"] = email
else:
    account["email"] = email
cfg = {
  "listen": f"127.0.0.1:{port}",
  "client_keys": [client_key],
  "accounts": [account],
  "default_model": "deepseek-v4-pro"
}
pathlib.Path(path).write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  chmod 600 "$CONFIG_PATH"
  echo "Created $CONFIG_PATH"
fi

cat > "$KEY_SCRIPT" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "\${DEEPSEEK_OAUTH_CLIENT_KEY:-}" ]]; then
  printf '%s\\n' "\$DEEPSEEK_OAUTH_CLIENT_KEY"
  exit 0
fi
CONFIG_PATH="\${DEEPSEEK_OAUTH_CONFIG:-$CONFIG_PATH}"
python3 - "\$CONFIG_PATH" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    cfg = json.load(f)
keys = cfg.get('client_keys') or []
if keys:
    print(keys[0])
    sys.exit(0)
sys.exit('No client key found in deepseek-oauth config')
PY
EOF
chmod 700 "$KEY_SCRIPT"

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
