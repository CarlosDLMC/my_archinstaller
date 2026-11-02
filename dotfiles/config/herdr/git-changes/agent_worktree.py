"""Print the git worktree an agent pane is working in.

usage: agent_worktree.py PANE_JSON_FILE_OR_- FALLBACK_DIR

herdr only knows the pane's folder. Agents are often started in the main
checkout and do their work in a linked worktree (`cd ../repo-feature && ...`,
`git -C ...`, file edits by absolute path), which never changes that folder.
So, for a Claude Code pane, read the agent's transcript and take the
worktree (linked, or the main checkout) its most recent tool calls name. Falls back to the transcript's own
cwd (Claude Code's built-in worktrees), then to FALLBACK_DIR's checkout.
"""
import glob, json, os, re, subprocess, sys

MAX_BYTES = 8 * 1024 * 1024   # read at most the last 8 MB of the transcript


def toplevel(d):
    r = subprocess.run(["git", "-C", d, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def worktrees(d):
    r = subprocess.run(["git", "-C", d, "worktree", "list", "--porcelain"], capture_output=True, text=True)
    out = []
    for line in r.stdout.splitlines():
        if line.startswith("worktree "):
            out.append(line[9:])
    return out


def transcript(session_id):
    if not session_id or not re.fullmatch(r"[0-9A-Za-z_-]+", session_id):
        return None
    hits = glob.glob(os.path.expanduser(f"~/.claude/projects/*/{session_id}.jsonl"))
    return max(hits, key=os.path.getmtime) if hits else None


def tail_lines(path):
    with open(path, "rb") as f:
        f.seek(0, 2)
        size = f.tell()
        f.seek(max(0, size - MAX_BYTES))
        data = f.read()
    lines = data.split(b"\n")
    if size > MAX_BYTES:
        lines = lines[1:]           # first one is cut
    return lines


def main():
    src, fallback = sys.argv[1], sys.argv[2]
    pane = json.load(sys.stdin if src == "-" else open(src))
    base = toplevel(fallback) or fallback
    if pane.get("agent") != "claude":
        print(base)
        return
    sid = (pane.get("agent_session") or {}).get("value")
    tpath = transcript(sid)
    if not tpath:
        print(base)
        return

    trees = worktrees(base)
    main_tree = trees[0] if trees else base
    # longest first: main/.claude/worktrees/x must win over main itself
    known = sorted((t for t in trees if os.path.isdir(t)), key=len, reverse=True)
    # a worktree path, then a path boundary (so repo-x does not match repo-xa)
    pat = re.compile("(?:" + "|".join(re.escape(t) for t in known) + r")(?=$|[/\"'\s\\:;,)\]}])") if len(known) > 1 else None

    last_cwd = None
    for raw in reversed(tail_lines(tpath)):
        if not raw.strip():
            continue
        try:
            msg = json.loads(raw)
        except ValueError:
            continue
        if last_cwd is None and isinstance(msg.get("cwd"), str):
            last_cwd = msg["cwd"]
        if pat is None or msg.get("type") != "assistant":
            continue
        content = (msg.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        for item in reversed(content):
            if isinstance(item, dict) and item.get("type") == "tool_use":
                text = json.dumps(item.get("input"), ensure_ascii=False)
                found = list(pat.finditer(text))
                if found:
                    print(found[-1].group(0))
                    return

    # Claude Code's own worktree mode moves the session's cwd
    if last_cwd:
        t = toplevel(last_cwd)
        if t:
            print(t)
            return
    print(main_tree if base == main_tree else base)


main()
