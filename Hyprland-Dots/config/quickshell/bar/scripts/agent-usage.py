#!/usr/bin/env python3
"""Claude Code usage for the bar's agents card.

Ported from Omarchy's omarchy-agent-usage-claude (omacom/omarchy, MIT, DHH):
the OAuth usage endpoint, the plan label derivation, the percent-scale
handling and the shape of the record are his. Reduced to the one agent this
machine runs, and given an incremental cache, because a full rescan of
~/.claude/projects reads 160MB and takes about 1.5s - far too slow to sit
behind a panel that opens on a click.

Two modes:
  limits   the OAuth probe only (fast; this is what the bar readout needs)
  full     limits plus the transcript scan (tokens by day and by model)

Prints one JSON object on stdout. Failures are reported inside it rather than
on stderr, so the card can say what went wrong instead of going blank.

On credentials: the access token is read from the Claude CLI's own store and
goes exactly one place - the Authorization header of Anthropic's usage
endpoint, which is the API that exists to report your own usage. It is never
printed, never cached, and never sent anywhere else. Only the plan label
("Max 5x") reaches the output.
"""

import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

USAGE_ENDPOINT = "https://api.anthropic.com/api/oauth/usage"

# Only the last week is ever drawn, so only files touched in that window can
# contribute. This is what keeps the scan to 129 files instead of 329.
WINDOW_DAYS = 7
SCAN_SLACK_DAYS = 1


def claude_dir() -> Path:
    return Path(os.path.expanduser(os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude"))


def last_good_path() -> Path:
    """Where the most recent successful probe is kept.

    The usage endpoint rate limits, and when it does it returns nothing useful
    - so without this the bar had no numbers at all until the next success,
    including across a restart. A stale reading with its age attached is far
    more use than a dash: allowances move slowly, and "48% as of 6 minutes
    ago" is a perfectly good answer to "how much room do I have".
    """
    base = Path(os.path.expanduser(
        os.environ.get("XDG_CACHE_HOME") or "~/.cache")) / "quickshell"
    base.mkdir(parents=True, exist_ok=True)
    return base / "agent-usage-last.json"


def cache_path() -> Path:
    base = Path(os.path.expanduser(
        os.environ.get("XDG_CACHE_HOME") or "~/.cache")) / "quickshell"
    base.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha1(str(claude_dir()).encode()).hexdigest()[:12]
    return base / f"agent-usage-scan-{digest}.json"


# --------------------------------------------------------------------- limits

def plan_label(tier: str, subscription: str) -> str:
    if tier:
        m = re.search(r"max_(\d+x)", tier, re.IGNORECASE)
        if m:
            return "Max " + m.group(1)
    if subscription:
        return subscription[0].upper() + subscription[1:]
    return ""


def oauth_login():
    try:
        data = json.loads((claude_dir() / ".credentials.json").read_text(encoding="utf-8"))
    except Exception:
        return "", ""
    login = data.get("claudeAiOauth")
    if not isinstance(login, dict):
        return "", ""
    plan = plan_label(str(login.get("rateLimitTier") or ""),
                      str(login.get("subscriptionType") or ""))
    return str(login.get("accessToken") or ""), plan


def parse_pct(value):
    try:
        return float(str(value).strip().replace("%", ""))
    except Exception:
        return float("nan")


def probe_limits(token: str):
    """Session and weekly utilisation, or a human reason why not."""
    req = urllib.request.Request(USAGE_ENDPOINT, headers={
        "Authorization": "Bearer " + token,
        "anthropic-beta": "oauth-2025-04-20",
        "Accept": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            payload = json.loads(resp.read().decode("utf-8", errors="replace"))
    except urllib.error.HTTPError as e:
        if e.code == 429:
            # The endpoint sends "Retry-After: 0" while still refusing, so the
            # header is not worth repeating - saying "retry in 0s" next to a
            # request that keeps failing reads as a bug in the widget.
            retry = str((e.headers or {}).get("retry-after", "")).strip()
            suffix = ""
            try:
                if retry and float(retry) > 0:
                    suffix = f" (retry in {retry}s)"
            except ValueError:
                pass
            return [], "Anthropic is rate limiting usage checks" + suffix + "."
        if e.code in (401, 403):
            return [], "Claude Code is not signed in, or its token expired."
        return [], f"Anthropic's usage endpoint returned {e.code}."
    except Exception:
        return [], "Couldn't reach Anthropic's usage endpoint."

    buckets = [
        ("Session", "5 hours", payload.get("five_hour")),
        ("Weekly", "7 days", payload.get("seven_day_oauth_apps") or payload.get("seven_day")),
        ("Opus", "7 days", payload.get("seven_day_opus")),
        ("Sonnet", "7 days", payload.get("seven_day_sonnet")),
    ]

    # One payload speaks one convention. Anthropic currently reports percentages
    # (37.0), but older ones used fractions (0.37); any value >= 1 settles it as
    # percent-scaled, so 1.0 renders as 1% rather than 100%.
    raw = [b.get("utilization") for _, _, b in buckets if isinstance(b, dict)]
    percent_scale = any(parse_pct(v) >= 1 for v in raw)

    out = []
    for name, window, bucket in buckets:
        if not isinstance(bucket, dict):
            continue
        pct = parse_pct(bucket.get("utilization"))
        if not (pct >= 0):
            continue
        if not percent_scale:
            pct *= 100.0
        out.append({
            "label": name,
            "window": window,
            "percent": round(pct, 1),
            "severity": "",
            "active": False,
            "resetsAt": str(bucket.get("resets_at") or ""),
        })

    # The per-model budgets, which are NOT in the top-level buckets - they live
    # only in the "limits" array, keyed by scope.model.display_name. Skipping
    # them hid the limit actually closest to being spent: this account reads
    # 22% session and 49% weekly while a model-scoped weekly sits at 78% and is
    # the only entry the server marks is_active.
    #
    # Anthropic also grades each entry itself (severity normal/warning/...),
    # which is a better warning trigger than a threshold guessed here.
    entries = payload.get("limits")
    if isinstance(entries, list):
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            if entry.get("kind") != "weekly_scoped":
                continue
            pct = parse_pct(entry.get("percent"))
            if not (pct >= 0):
                continue
            if not percent_scale:
                pct *= 100.0
            scope = entry.get("scope") or {}
            model = (scope.get("model") or {}).get("display_name") or "Scoped"
            out.append({
                "label": str(model),
                "window": "7 days",
                "percent": round(pct, 1),
                "severity": str(entry.get("severity") or ""),
                "active": entry.get("is_active") is True,
                "resetsAt": str(entry.get("resets_at") or ""),
            })

    # Carry the server's own grading onto the two headline buckets too, so the
    # card colours everything by the same rule.
    by_kind = {}
    if isinstance(entries, list):
        for entry in entries:
            if isinstance(entry, dict):
                by_kind[str(entry.get("kind") or "")] = entry
    for row, kind in (("Session", "session"), ("Weekly", "weekly_all")):
        entry = by_kind.get(kind)
        if not isinstance(entry, dict):
            continue
        for item in out:
            if item["label"] == row:
                item["severity"] = str(entry.get("severity") or "")
                item["active"] = entry.get("is_active") is True

    return out, ""


# ----------------------------------------------------------------- transcripts

def day_of(ts: str) -> str:
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().strftime("%Y-%m-%d")
    except Exception:
        return ""


def scan_file(path: Path):
    """Per-day and per-model token counts for one transcript."""
    days = defaultdict(lambda: [0, 0])          # day -> [input, output]
    models = defaultdict(lambda: [0, 0, 0, 0])  # model -> [in, out, cacheRead, cacheCreate]
    try:
        with path.open("r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                # Cheap reject before the JSON parse: most lines are not
                # assistant messages and parsing all of them dominates the scan.
                if '"usage"' not in line:
                    continue
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                msg = rec.get("message")
                if not isinstance(msg, dict):
                    continue
                usage = msg.get("usage")
                if not isinstance(usage, dict):
                    continue
                i = int(usage.get("input_tokens") or 0)
                o = int(usage.get("output_tokens") or 0)
                cr = int(usage.get("cache_read_input_tokens") or 0)
                cc = int(usage.get("cache_creation_input_tokens") or 0)
                day = day_of(str(rec.get("timestamp") or ""))
                if day:
                    d = days[day]
                    d[0] += i
                    d[1] += o
                model = str(msg.get("model") or "")
                if model:
                    m = models[model]
                    m[0] += i
                    m[1] += o
                    m[2] += cr
                    m[3] += cc
    except OSError:
        pass
    return {"days": {k: v for k, v in days.items()},
            "models": {k: v for k, v in models.items()}}


def scan_transcripts():
    """Aggregate the last week, reusing per-file results that have not changed.

    The cache is keyed by path and invalidated by (mtime, size). Between two
    runs usually one transcript has changed - the session you are in - so a
    refresh re-reads one file rather than 160MB.
    """
    root = claude_dir() / "projects"
    cutoff = time.time() - (WINDOW_DAYS + SCAN_SLACK_DAYS) * 86400

    try:
        cache = json.loads(cache_path().read_text(encoding="utf-8"))
        if not isinstance(cache, dict):
            cache = {}
    except Exception:
        cache = {}
    files = cache.get("files") if isinstance(cache.get("files"), dict) else {}

    fresh = {}
    days = defaultdict(lambda: [0, 0])
    models = defaultdict(lambda: [0, 0, 0, 0])

    if root.is_dir():
        for path in root.rglob("*.jsonl"):
            try:
                st = path.stat()
            except OSError:
                continue
            if st.st_mtime < cutoff:
                continue
            key = str(path)
            sig = [int(st.st_mtime), st.st_size]
            hit = files.get(key)
            if isinstance(hit, dict) and hit.get("sig") == sig:
                entry = hit
            else:
                entry = {"sig": sig, **scan_file(path)}
            fresh[key] = entry

            for day, (i, o) in entry["days"].items():
                d = days[day]
                d[0] += i
                d[1] += o
            for model, vals in entry["models"].items():
                m = models[model]
                for idx in range(4):
                    m[idx] += vals[idx]

    try:
        cache_path().write_text(json.dumps({"files": fresh}), encoding="utf-8")
    except OSError:
        pass

    today = datetime.now().astimezone().date()
    by_day = []
    for back in range(WINDOW_DAYS - 1, -1, -1):
        key = (today.fromordinal(today.toordinal() - back)).strftime("%Y-%m-%d")
        i, o = days.get(key, [0, 0])
        by_day.append({"day": key, "tokens": i + o})

    # Claude Code records a "<synthetic>" pseudo-model for its own bookkeeping
    # turns. It is not a model anyone chose and it distorts the chart, so it
    # never reaches the card.
    models = {k: v for k, v in models.items() if not k.startswith("<")}

    by_model = sorted(
        ({"model": name,
          "tokens": v[0] + v[1],
          "input": v[0], "output": v[1],
          "cacheRead": v[2], "cacheCreate": v[3]}
         for name, v in models.items()),
        key=lambda r: r["tokens"], reverse=True)

    return by_day, by_model[:6]


# ----------------------------------------------------------------------- main

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "full"
    out = {"ok": False, "plan": "", "limits": [], "limitsError": "",
           "byDay": [], "byModel": [], "at": int(time.time())}

    # Whether Claude Code exists on this machine at all, which is a different
    # question from whether this probe returned anything. The widget hides
    # itself on "not installed"; it must NOT hide on "the usage endpoint is
    # rate limiting us right now", which is easy to provoke and transient.
    d = claude_dir()
    out["installed"] = (d / ".credentials.json").exists() or (d / "projects").is_dir()

    token, plan = oauth_login()
    out["plan"] = plan
    if not token:
        out["limitsError"] = "No Claude Code credentials found."
    else:
        out["limits"], out["limitsError"] = probe_limits(token)

    if out["limits"]:
        try:
            last_good_path().write_text(json.dumps({
                "plan": out["plan"], "limits": out["limits"], "at": out["at"],
            }), encoding="utf-8")
        except OSError:
            pass
    else:
        # Nothing came back. Fall back to the last good reading rather than
        # reporting no allowances at all, and say how old it is so the card
        # can be honest about showing history.
        try:
            cached = json.loads(last_good_path().read_text(encoding="utf-8"))
            if isinstance(cached, dict) and cached.get("limits"):
                out["limits"] = cached["limits"]
                out["stale"] = True
                out["staleAt"] = int(cached.get("at") or 0)
                if not out["plan"]:
                    out["plan"] = cached.get("plan") or ""
        except Exception:
            pass

    if mode == "full":
        try:
            out["byDay"], out["byModel"] = scan_transcripts()
        except Exception as e:
            out["scanError"] = type(e).__name__

    out["ok"] = bool(out["limits"]) or bool(out["byDay"])
    json.dump(out, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
