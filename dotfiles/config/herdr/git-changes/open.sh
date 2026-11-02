#!/bin/sh
# Action behind ALT+G: open the Changes popup on the git worktree of the
# focused pane (the agent's worktree), whatever folder the agent is in.
H="${HERDR_BIN_PATH:-herdr}"

if [ -n "$HERDR_PLUGIN_STATE_DIR" ]; then
    printf '%s\n' "$HERDR_PLUGIN_CONTEXT_JSON" > "$HERDR_PLUGIN_STATE_DIR/last-context.json" 2>/dev/null
fi

# Pane id: from the env, else from the context JSON. Its cwd: the foreground
# process's (the agent's) cwd, else the pane's.
dir=$(H="$H" python3 -I - <<'EOF'
import json, os, subprocess
H = os.environ["H"]
ctx = {}
try:
    ctx = json.loads(os.environ.get("HERDR_PLUGIN_CONTEXT_JSON") or "{}")
except ValueError:
    pass

def find(obj, keys):
    if isinstance(obj, dict):
        for k in keys:
            v = obj.get(k)
            if isinstance(v, str) and v:
                return v
        for v in obj.values():
            r = find(v, keys)
            if r:
                return r
    return None

pane = (os.environ.get("HERDR_PANE_ID") or os.environ.get("HERDR_ACTIVE_PANE_ID")
        or find(ctx, ["pane_id", "focused_pane_id"]))
cwd = None
if pane:
    try:
        out = subprocess.run([H, "pane", "get", pane], capture_output=True, text=True).stdout
        p = json.loads(out)["result"]["pane"]
        cwd = p.get("foreground_cwd") or p.get("cwd")
    except Exception:
        pass
cwd = cwd or find(ctx, ["checkout_path", "foreground_cwd", "cwd"]) or os.environ.get("HERDR_ACTIVE_PANE_CWD") or os.getcwd()
print(cwd)
EOF
)

root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || root="$dir"

exec "$H" plugin pane open --plugin git-changes --entrypoint changes \
    --cwd "$root" --env GIT_CHANGES_ROOT="$root"
