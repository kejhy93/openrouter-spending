# OpenRouter Spending (local Omarchy widget)

A native bar popup showing spend for the API key Hermes Agent uses: today, this month, and all time. It also supports a ranked model spend/token/request breakdown for the last 30 completed UTC days.

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