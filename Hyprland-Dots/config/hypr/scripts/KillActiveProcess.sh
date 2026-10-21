#!/usr/bin/env bash

# Copied from Discord post. Thanks to @Zorg


# The active window's pid, from the JSON. The plain-text output prints the
# window's title before its pid, and grepping that for "pid: N" also matched a
# title containing it (a terminal running a command that mentions a pid, a
# browser tab) - so process N was killed along with the window.
# With nothing focused mango answers {"error": ...}, which has no pid.
active_pid=$(mmsg get focusing-client | jq -r '.pid // empty')

# Close active window
[ -n "$active_pid" ] && [ "$active_pid" -gt 0 ] && kill "$active_pid"
