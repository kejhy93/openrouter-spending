# OpenRouter Spending (local Omarchy widget)

A native bar popup showing spend for the API key Hermes Agent uses: today, this month, and all time. It also supports a ranked model spend/token/request breakdown for the last 30 completed UTC days.

## Install on a new machine

The repo is private, so the machine needs GitHub access over SSH first (`gh auth login --git-protocol ssh` can generate and upload a key).

```sh
# 1. Download and enable the plugin (lands in ~/.config/omarchy/plugins/openrouter.spending)
omarchy plugin add git@github.com:kejhy93/openrouter-spending.git --enable

# 2. API key used for daily/monthly/all-time spend (required)
mkdir -p ~/.hermes
(umask 077 && touch ~/.hermes/.env) && chmod 600 ~/.hermes/.env
$EDITOR ~/.hermes/.env    # add: OPENROUTER_API_KEY=...

# 3. Management key for the per-model breakdown (optional)
(umask 077 && touch ~/.config/omarchy/openrouter.env) && chmod 600 ~/.config/omarchy/openrouter.env
$EDITOR ~/.config/omarchy/openrouter.env    # add: OPENROUTER_MANAGEMENT_KEY=...
```

Alternatively copy both files from an existing machine, keeping mode 600:

```sh
scp -p otherbox:.hermes/.env ~/.hermes/.env
scp -p otherbox:.config/omarchy/openrouter.env ~/.config/omarchy/openrouter.env
```

Then click the widget in the bar, or run `omarchy-shell openrouter.spending open`.

### Updating

```sh
omarchy plugin update openrouter.spending
```

To change the plugin, edit it in `~/.config/omarchy/plugins/openrouter.spending/` (it hot-reloads), then `git commit` and `git push` from there.

## Credentials

The widget reuses `OPENROUTER_API_KEY` from Hermes's existing `~/.hermes/.env` for current-key daily/monthly/all-time spend and limit. For model-level breakdown, OpenRouter requires a separate Management key. Add it locally (never paste it into chat) to:

`~/.config/omarchy/openrouter.env`

Create/protect that file with:

```sh
install -m 600 /dev/null ~/.config/omarchy/openrouter.env
$EDITOR ~/.config/omarchy/openrouter.env
```

Add this line:

```sh
OPENROUTER_MANAGEMENT_KEY=your_management_key
```

The widget reads it from that file or from `OPENROUTER_MANAGEMENT_KEY` in the shell environment. It uses `/activity` to group the last 30 completed UTC days by model; the regular Hermes key cannot access that endpoint. Model breakdown is account-wide because `/activity` requires a Management key. Current daily/monthly totals remain scoped to Hermes's regular API key.

The keys are sent only to OpenRouter's HTTPS API, never placed in process arguments or logs. Both credential files should have mode 600. No prompts or generation content are requested.

## Controls

- Left-click bar icon: open/close popup
- Middle-click or popup refresh: refresh
- IPC: `omarchy-shell openrouter.spending refresh|toggle|open`
- Disable: `omarchy plugin disable openrouter.spending`

## Files

- `manifest.json` — plugin registration
- `BarWidget.qml` / `Panel.qml` — bar button and popup
- `fetch.py` — HTTPS API client

Privacy: helper output contains spend/usage aggregates only, plus a non-secret key label.