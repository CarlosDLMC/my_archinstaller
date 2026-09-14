#!/usr/bin/env python3
"""Claude Code usage for the bar's agents card.

Ported from Omarchy's omarchy-agent-usage-claude (omacom/omarchy, MIT, DHH):
the OAuth usage endpoint, the plan label derivation, the percent-scale
handling and the shape of the record are his. Reduced to the one agent this
machine runs, and given an incremental cache, because a full rescan of
~/.claude/projects reads 160MB and takes about 1.5s - far too slow to sit
behind a panel that opens on a click.

Three modes:
  limits   the OAuth probe only
  stats    the transcript scan only - NO network call whatsoever
  full     both

The split exists to keep the endpoint quiet. The allowance figures describe a
5-hour and a 7-day window, so re-probing them every half minute is pointless
as well as rude; the transcript counts are local and change as you work, so
those are what a refresh while the card is open should re-read.

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
from datetime import datetime, time as dtime, timedelta, timezone
from pathlib import Path

USAGE_ENDPOINT = "https://api.anthropic.com/api/oauth/usage"

# How many days the by-day chart covers. The by-model chart is all time, so
# there is no file-mtime cutoff any more: every transcript is read, and the
# per-file cache is what makes that affordable.
WINDOW_DAYS = 7


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
    """Session and weekly utilisation, or a human reason why not.

    Returns (limits, error, retry_advised). retry_advised is True only when the
    endpoint was never reached at all - no route, no DNS, typically the seconds
    after login before the network is up. An HTTP status, 429 included, means a
    server answered: retrying sooner is pointless, and against a rate limiter it
    is how you stay rate limited. This is the distinction Omarchy's collector
    draws with its `transport` flag, and honouring it is why there is no retry
    treadmill here.
    """
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
            return [], "Anthropic is rate limiting usage checks" + suffix + ".", False
        if e.code in (401, 403):
            return [], "Claude Code is not signed in, or its token expired.", False
        return [], f"Anthropic's usage endpoint returned {e.code}.", False
    except Exception:
        # Nothing answered. This is the one case worth trying again soon.
        return [], "Couldn't reach Anthropic's usage endpoint.", True

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

    return out, "", False


# ----------------------------------------------------------------- transcripts

def hour_of(ts: str):
    """The UTC hour a record falls in, as an integer epoch hour."""
    try:
        return int(datetime.fromisoformat(
            ts.replace("Z", "+00:00")).timestamp() // 3600)
    except Exception:
        return None


# Cache format version. Bump when the shape of a scanned file's record
# changes, so an old cache is discarded rather than misread.
SCAN_VERSION = 3


def scan_file(path: Path):
    """One transcript, bucketed by UTC hour and model.

    Hour buckets rather than whole days because the window this is later
    filtered to can start at an arbitrary instant - Anthropic's weekly
    allowance resets at 16:00 UTC, not at midnight. Storing epoch hours rather
    than formatted dates also keeps the cache correct across a timezone change,
    which matters here: the VPN widget moves the system timezone.

    The bucket is (epoch_hour, model) so both charts can be filtered by exactly
    the same window afterwards. Keeping the cache window-independent is the
    point - it is keyed on the file's mtime and size, and must not silently
    become wrong when the window moves.
    """
    buckets = defaultdict(lambda: [0, 0, 0, 0])  # (hour, model) -> [in, out, cr, cc]
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
                hour = hour_of(str(rec.get("timestamp") or ""))
                if hour is None:
                    continue
                model = str(msg.get("model") or "")
                if not model:
                    continue
                b = buckets[(hour, model)]
                b[0] += int(usage.get("input_tokens") or 0)
                b[1] += int(usage.get("output_tokens") or 0)
                b[2] += int(usage.get("cache_read_input_tokens") or 0)
                b[3] += int(usage.get("cache_creation_input_tokens") or 0)
    except OSError:
        pass
    return {"b": [[h, m] + v for (h, m), v in buckets.items()]}


def scan_transcripts():
    """Tokens by day for the last 7 days, and by model for all time.

    Two different scopes, which is what Omarchy does and is deliberate there:
    the day chart answers "what have I been doing this week" and the model
    chart answers "what do I actually run". Its collector filters recentDays to
    `today-6 .. today` while accumulating usage_by_model with no day filter at
    all, over every transcript with no mtime filter either.

    Note the day chart is the last seven CALENDAR days, not the seven days of
    the current weekly allowance - those are different windows that happen to
    be the same length, and the meter above is the thing that tracks the
    allowance.

    Every file is read, because the model totals are all-time. That is what the
    per-file cache is for: the cold pass is the expensive one, and after it only
    the transcript being written to has changed.
    """
    root = claude_dir() / "projects"

    try:
        cache = json.loads(cache_path().read_text(encoding="utf-8"))
        if not isinstance(cache, dict) or cache.get("v") != SCAN_VERSION:
            cache = {}
    except Exception:
        cache = {}
    files = cache.get("files") if isinstance(cache.get("files"), dict) else {}

    fresh = {}
    # The day chart's window: midnight 6 days ago, local time, through now.
    first_day = datetime.now().astimezone().date() - timedelta(days=WINDOW_DAYS - 1)
    start_hour = int(datetime.combine(
        first_day, dtime(0, 0)).astimezone().timestamp() // 3600)

    days = defaultdict(lambda: [0, 0])
    models = defaultdict(lambda: [0, 0, 0, 0])
    all_hours = []

    if root.is_dir():
        for path in root.rglob("*.jsonl"):
            try:
                st = path.stat()
            except OSError:
                continue
            key = str(path)
            sig = [int(st.st_mtime), st.st_size]
            hit = files.get(key)
            entry = hit if isinstance(hit, dict) and hit.get("sig") == sig \
                else {"sig": sig, **scan_file(path)}
            fresh[key] = entry

            for hour, model, i, o, cr, cc in entry.get("b", []):
                all_hours.append(hour)
                # Models: everything, all time.
                m = models[model]
                m[0] += i
                m[1] += o
                m[2] += cr
                m[3] += cc
                # Days: only the last week.
                if hour < start_hour:
                    continue
                day = datetime.fromtimestamp(hour * 3600).astimezone().strftime("%Y-%m-%d")
                d = days[day]
                d[0] += i
                d[1] += o

    try:
        cache_path().write_text(
            json.dumps({"v": SCAN_VERSION, "files": fresh}), encoding="utf-8")
    except OSError:
        pass

    # Seven rows, oldest first, today last - a quiet day is a short bar, not a
    # missing row.
    by_day = []
    for back in range(WINDOW_DAYS - 1, -1, -1):
        key = (datetime.now().astimezone().date() - timedelta(days=back)).strftime("%Y-%m-%d")
        i, o = days.get(key, [0, 0])
        by_day.append({"day": key, "tokens": i + o})

    # The earliest record still on disk. Claude Code prunes its own transcripts
    # (cleanupPeriodDays, 30 by default), so the model chart's "all time" only
    # ever reaches back as far as the oldest surviving one - and that moves
    # forward as old files are deleted. The card shows this date rather than
    # claiming a total it cannot have.
    oldest = min((h for h in all_hours), default=0)

    models = {k: v for k, v in models.items() if not k.startswith("<")}

    by_model = sorted(
        ({"model": name,
          "tokens": v[0] + v[1],
          "input": v[0], "output": v[1],
          "cacheRead": v[2], "cacheCreate": v[3]}
         for name, v in models.items()),
        key=lambda r: r["tokens"], reverse=True)

    return by_day, by_model[:6], oldest


# ----------------------------------------------------------------------- main

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "full"
    out = {"ok": False, "plan": "", "limits": [], "limitsError": "",
           "byDay": [], "byModel": [], "at": int(time.time()),
           # Whether this run talked to the network at all. The reader must not
           # treat a stats-only run's empty limits as "the probe failed".
           "probed": mode in ("limits", "full")}

    # Whether Claude Code exists on this machine at all, which is a different
    # question from whether this probe returned anything. The widget hides
    # itself on "not installed"; it must NOT hide on "the usage endpoint is
    # rate limiting us right now", which is easy to provoke and transient.
    d = claude_dir()
    out["installed"] = (d / ".credentials.json").exists() or (d / "projects").is_dir()

    if not out["probed"]:
        try:
            out["byDay"], out["byModel"], out["oldestHour"] = scan_transcripts()
        except Exception as e:
            out["scanError"] = type(e).__name__
        out["ok"] = bool(out["byDay"])
        json.dump(out, sys.stdout)
        sys.stdout.write("\n")
        return

    token, plan = oauth_login()
    out["plan"] = plan
    if not token:
        out["limitsError"] = "No Claude Code credentials found."
    else:
        out["limits"], out["limitsError"], out["retryAdvised"] = probe_limits(token)

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
            out["byDay"], out["byModel"], out["oldestHour"] = scan_transcripts()
        except Exception as e:
            out["scanError"] = type(e).__name__

    out["ok"] = bool(out["limits"]) or bool(out["byDay"])
    json.dump(out, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
