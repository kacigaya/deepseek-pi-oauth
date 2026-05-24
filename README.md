<p align="center">
  <img src="logo.svg" alt="Logo" width="200">
</p>

<p align="center">
   <strong>Simple DeepSeek web-login/OAuth bridge installer for Pi.</strong><br>
   <em>Based on <a href="https://github.com/CJackHwang/ds2api/">CJackHwang/ds2api</a>.</em>
</p>

## One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/kacigaya/deepseek-oauth/main/install.sh | bash
```

Non-interactive:

```bash
DEEPSEEK_EMAIL='you@example.com' DEEPSEEK_PASSWORD='your-password' \
  curl -fsSL https://raw.githubusercontent.com/kacigaya/deepseek-oauth/main/install.sh | bash
```

## What the installer does

- Creates app config at `~/.deepseek-oauth/config.json`.
- Creates a Pi API-key helper at `~/.pi/agent/deepseek-oauth-key.sh`.
- Adds a `deepseek-oauth` Responses API provider to `~/.pi/agent/models.json`.
- Adds Pi models:
  - `deepseek-oauth/deepseek-v4-flash`
  - `deepseek-oauth/deepseek-v4-pro`
  - `deepseek-oauth/deepseek-v4-flash-search`
  - `deepseek-oauth/deepseek-v4-pro-search`
  - `deepseek-oauth/deepseek-v4-vision`

## Start bridge

After installing/building the bridge binary:

```bash
~/.deepseek-oauth/start.sh
```

Expected local OpenAI-compatible endpoint:

```text
http://127.0.0.1:5001/v1
```

If you run DS2API manually with `DS2API_CONFIG_PATH`, install against the same
config file so Pi and DS2API share the same client key:

```bash
DEEPSEEK_OAUTH_CONFIG=/path/to/ds2api/config.json ./install.sh
```

## Use with Pi

```bash
pi --model deepseek-oauth/deepseek-v4-pro
```

Or inside Pi, run `/model` and choose a `deepseek-oauth` model.

Tool calls use DS2API's Responses-compatible tool-call adaptation. The bridge
must translate DeepSeek's DSML/XML tool-call output into standard
`function_call` events for Pi to execute tools.

## Google-login DeepSeek accounts

If your DeepSeek account was created using Google login, password login may fail unless you set a normal DeepSeek password.

## DeepSeek account mutes

This bridge uses the DeepSeek web account behind DS2API. If DeepSeek mutes or
limits that account, Pi may show errors such as:

```text
Upstream service is unavailable and returned no output.
```

Check DS2API dev captures or account testing for upstream messages like
`user is muted`. Use another DeepSeek account or wait until the mute expires.

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `DEEPSEEK_EMAIL` | prompt | DeepSeek email or mobile |
| `DEEPSEEK_PASSWORD` | prompt | DeepSeek password |
| `DEEPSEEK_OAUTH_CLIENT_KEY` | generated | Local client key used by Pi |
| `DEEPSEEK_OAUTH_DIR` | `~/.deepseek-oauth` | App config directory |
| `DEEPSEEK_OAUTH_CONFIG` | `~/.deepseek-oauth/config.json` | DS2API config path |
| `DEEPSEEK_OAUTH_PORT` | `5001` | Local bridge port |
| `DEEPSEEK_OAUTH_BASE_URL` | `http://127.0.0.1:5001/v1` | Pi provider base URL |
| `PI_AGENT_DIR` | `~/.pi/agent` | Pi config directory |

## Files written

```text
~/.deepseek-oauth/config.json
~/.deepseek-oauth/start.sh
~/.pi/agent/deepseek-oauth-key.sh
~/.pi/agent/models.json
```

Keep `~/.deepseek-oauth/config.json` private; it contains credentials.
