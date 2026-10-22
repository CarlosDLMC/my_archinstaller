#!/usr/bin/env python3
"""Herdr startup + event hook: Agents tab ordered blocked, working, done, idle.

herdr's own orders cannot do this: "spaces" groups by workspace, and
"priority" (the attention queue) puts done above working. What herdr does
offer is a declarative Agent view (agent.view.set) that sorts on built-in
fields and on pane tokens a plugin reports. So this hook

  - tags every agent with the pane token agent_order: "1" while it is blocked
    or working, "2" otherwise (done, idle, unknown), and
  - installs the view: agent_order ascending, then herdr's attention score
    descending (blocked 4 > done 3 > working 2 > idle 1 > unknown 0), then
    workspace / tab / pane order so rows in the same state keep their places.

Done and idle share "2" on purpose: looking at a done agent turns it idle
without any event, so a token that told them apart would go stale. The
attention score, which herdr keeps current itself, splits them instead.

Herdr runs it on every pane.agent_status_changed and once at startup (tokens
and views do not survive a server restart). Each run sets the view again,
re-tags all agents and only reports the ones whose token is wrong. Tokens are not part of the agent's
presentation, so reporting them fires no further status event.
"""
import json
import os
import socket

SOURCE = "plugin:" + (os.environ.get("HERDR_PLUGIN_ID") or "agent-order")
SOCK = os.environ.get("HERDR_SOCKET_PATH") or os.path.join(
    os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"),
    "herdr", "herdr.sock")
TOKEN = "agent_order"

VIEW = {
    "source": SOURCE,
    "sort": [
        {"field": {"token": TOKEN}, "order": "asc"},
        {"field": "attention", "order": "desc"},
        {"field": "workspace_order", "order": "asc"},
        {"field": "tab_order", "order": "asc"},
        {"field": "pane_order", "order": "asc"},
    ],
}


def call(method, params):
    """One request on its own connection; returns the result or raises."""
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(5)
        s.connect(SOCK)
        s.sendall((json.dumps({"id": "agent-order", "method": method,
                               "params": params}) + "\n").encode())
        buf = b""
        while not buf.endswith(b"\n"):
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
    reply = json.loads(buf)
    if "error" in reply:
        raise RuntimeError("%s: %s" % (method, reply["error"]))
    return reply.get("result")


def main():
    # Every run, not only at startup: enabling the plugin again drops the view.
    call("agent.view.set", VIEW)
    for agent in call("agent.list", {}).get("agents", []):
        rank = "1" if agent.get("agent_status") in ("blocked", "working") else "2"
        if (agent.get("tokens") or {}).get(TOKEN) != rank:
            call("pane.report_metadata", {"pane_id": agent["pane_id"],
                                          "source": SOURCE,
                                          "tokens": {TOKEN: rank}})


if __name__ == "__main__":
    main()
