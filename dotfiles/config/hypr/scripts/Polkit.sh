#!/usr/bin/env bash
# This script starts the first available Polkit agent from a list of possible locations

# The quickshell bar is the polkit agent (bar/PolkitState.qml). Polkit takes one
# agent per session, so starting another one here would take the bar's slot.
# Only when the installed quickshell has the module - otherwise fall through.
if [ -f "$HOME/.config/quickshell/bar/PolkitState.qml" ] \
   && [ -d /usr/lib/qt6/qml/Quickshell/Services/Polkit ]; then
  echo "Polkit agent provided by the quickshell bar - not starting another."
  exit 0
fi

# List of potential Polkit agent file paths
polkit=(
  "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"
  "/usr/libexec/hyprpolkitagent"
  "/usr/lib/hyprpolkitagent"
  "/usr/lib/hyprpolkitagent/hyprpolkitagent"
  "/usr/lib/polkit-kde-authentication-agent-1"
  "/usr/lib/polkit-gnome-authentication-agent-1"
  "/usr/libexec/polkit-gnome-authentication-agent-1"
  "/usr/libexec/polkit-mate-authentication-agent-1"
  "/usr/lib/x86_64-linux-gnu/libexec/polkit-kde-authentication-agent-1"
  "/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1"
)

executed=false

# Loop through the list of paths
for file in "${polkit[@]}"; do
  if [ -e "$file" ] && [ ! -d "$file" ]; then
    echo "Found: $file — executing..."
    exec "$file"
    executed=true
    break
  fi
done

# Fallback message if nothing executed
if [ "$executed" == false ]; then
  echo "No valid Polkit agent found. Please install one."
fi
