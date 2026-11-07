#!/usr/bin/env python3
"""Read OpenRouter spend and optional model activity; never expose credentials."""
import json
import os
import stat
import sys
import urllib.error
import urllib.request
from pathlib import Path


def read_env_key(name, path, required=False):
    key = os.environ.get(name, "").strip()
    if key:
        return key
    try:
        mode = stat.S_IMODE(path.stat().st_mode)
        if mode & 0o077:
            raise ValueError(f"{path} permissions are too open; use chmod 600")
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[7:].lstrip()
            if "=" not in line:
                continue
            key_name, value = line.split("=", 1)
            if key_name.strip() == name:
                value = value.strip()
                if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                    value = value[1:-1]
                if value:
                    return value
    except FileNotFoundError:
        pass
    if required:
        raise ValueError(f"{name} not found in {path}")
    return ""


def read_key():
    # The inference key is read from Hermes's existing secure credential file.
    return read_env_key("OPENROUTER_API_KEY", Path.home() / ".hermes/.env", required=True)


def read_management_key():
    # Kept separately: a Management key has account-wide read permissions.
    return read_env_key("OPENROUTER_MANAGEMENT_KEY", Path.home() / ".config/omarchy/openrouter.env")


def request(path, key):
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1" + path,
        headers={"Authorization": "Bearer " + key, "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=12) as response:
        return json.load(response).get("data")


def number(obj, field):
    value = obj.get(field)
    try:
        return float(value) if value is not None else 0.0
    except (TypeError, ValueError):
        return 0.0


def post_json(path, key, payload):
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1" + path,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": "Bearer " + key,
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=20) as response:
        return json.load(response).get("data")


def main():
    key = read_key()
    item = request("/key", key)
    if not isinstance(item, dict):
        raise ValueError("OpenRouter returned unexpected key usage")
    management_key = read_management_key()
    models = []
    models_error = ""
    if management_key:
        try:
            # The analytics endpoint matches OpenRouter's dashboard. The
            # account has one active key; include key as a dimension and then
            # sum/group by model locally (a server-side key filter errors here).
            from datetime import datetime, timezone, timedelta
            end = datetime.now(timezone.utc).replace(microsecond=0)
            start = end - timedelta(days=30)
            api_keys = request("/keys", management_key)
            match = next((k for k in api_keys if isinstance(k, dict) and k.get("label") == item.get("label")), None) if isinstance(api_keys, list) else None
            key_name = match.get("name") if match else None
            payload = {
                "metrics": ["total_usage", "request_count", "tokens_total"],
                "dimensions": ["model", "api_key_id"],
                "time_range": {
                    "start": start.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "end": end.strftime("%Y-%m-%dT%H:%M:%SZ"),
                },
                "limit": 100,
                "order_by": {"field": "total_usage", "direction": "desc"},
            }
            response = post_json("/analytics/query", management_key, payload)
            rows = response.get("data", []) if isinstance(response, dict) else []
            if isinstance(rows, list):
                by_model = {}
                for row in rows:
                    if not isinstance(row, dict):
                        continue
                    # Restrict to the Hermes key client-side. The management
                    # key currently lists one active key, but this avoids
                    # accidentally mixing another key if one is added later.
                    if key_name and row.get("api_key_id") not in (key_name, None):
                        continue
                    name = str(row.get("model") or "Unknown model")
                    stats = by_model.setdefault(name, {"model": name, "spend": 0.0, "requests": 0, "tokens": 0})
                    stats["spend"] += number(row, "total_usage")
                    stats["requests"] += int(number(row, "request_count"))
                    stats["tokens"] += int(number(row, "tokens_total"))
                # Calculate percentages
                total_spend = sum(m["spend"] for m in by_model.values())
                total_tokens = sum(m["tokens"] for m in by_model.values())
                for m in by_model.values():
                    m["spend_pct"] = (m["spend"] / total_spend * 100.0) if total_spend > 0 else 0.0
                    m["tokens_pct"] = (m["tokens"] / total_tokens * 100.0) if total_tokens > 0 else 0.0
                models = sorted(by_model.values(), key=lambda row: row["spend"], reverse=True)[:8]
            else:
                models_error = "OpenRouter returned an unexpected analytics response."
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace")[:180]
            models_error = f"OpenRouter analytics request failed (HTTP {exc.code}): {detail}"
        except Exception:
            models_error = "Could not load model analytics; try refreshing later."
    else:
        models_error = "Add an OpenRouter Management key to ~/.config/omarchy/openrouter.env to see model breakdown (chmod 600)."
    result = {
        "daily": item.get("usage_daily"),
        "monthly": item.get("usage_monthly"),
        "total": item.get("usage"),
        "limit": item.get("limit"),
        "remaining": item.get("limit_remaining"),
        "label": item.get("label", "Current API key"),
        "key_count": 1,
        "models": models,
        "models_error": models_error,
        "model_days": 30,
    }
    print(json.dumps(result))


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:240]
        print(json.dumps({"error": f"OpenRouter HTTP {exc.code}: {detail}"}))
        sys.exit(2)
    except Exception as exc:
        print(json.dumps({"error": str(exc)}))
        sys.exit(3)
