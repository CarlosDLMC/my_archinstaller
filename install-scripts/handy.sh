#!/bin/bash
# Handy - free, open-source, offline speech-to-text
# Adds a Hyprland keybind (CTRL+SUPER+F8) that toggles transcription
# and an autostart entry so Handy is ready to receive the IPC toggle.
# NOTE: must run AFTER dotfiles-main.sh so the KooL UserConfigs/ files exist.

handy_pkg=(
  handy-bin
  wtype
  gtk-layer-shell
)

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "${ERROR} Failed to change directory to $PARENT_DIR"; exit 1; }

# Source the global functions script
if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%d-%H%M%S)_handy.log"

# Install packages (handy-bin is AUR; wtype + gtk-layer-shell are repo)
printf "\n%s - Installing ${SKY_BLUE}Handy speech-to-text${RESET} packages .... \n" "${NOTE}"
for PKG in "${handy_pkg[@]}"; do
  install_package "$PKG" "$LOG"
done

USER_KEYBINDS="$HOME/.config/hypr/UserConfigs/UserKeybinds.conf"
STARTUP_APPS="$HOME/.config/hypr/UserConfigs/Startup_Apps.conf"
USER_SCRIPTS_DIR="$HOME/.config/hypr/UserScripts"
HANDY_LAUNCHER="$USER_SCRIPTS_DIR/handy-start.sh"

# Wrapper that opens Handy visibly until a model is selected, then hidden after.
# Lets the user see the UI on first login (to pick Parakeet V3) without it
# popping up every subsequent boot.
if [ -d "$USER_SCRIPTS_DIR" ]; then
  cat > "$HANDY_LAUNCHER" <<'LAUNCHER'
#!/bin/bash
# First login → open Handy visibly so the user picks a model.
# After a model is selected, start hidden on every subsequent login.
SETTINGS="$HOME/.local/share/com.pais.handy/settings.json"
if grep -q '"selected_model"[[:space:]]*:[[:space:]]*"[^"]\+"' "$SETTINGS" 2>/dev/null; then
  exec handy --start-hidden
else
  exec handy
fi
LAUNCHER
  chmod +x "$HANDY_LAUNCHER"
  echo "${OK} Wrote $HANDY_LAUNCHER" | tee -a "$LOG"
else
  echo "${WARN} $USER_SCRIPTS_DIR not found — Handy will autostart hidden (model picker won't open on first login)." | tee -a "$LOG"
fi

# Add Hyprland keybind (CTRL+SUPER+F8 → notify + toggle Handy)
if [ -f "$USER_KEYBINDS" ]; then
  if ! grep -q "handy --toggle-transcription" "$USER_KEYBINDS"; then
    {
      echo ""
      echo "# Handy speech-to-text: press to start, press again to stop & transcribe"
      echo 'bindd = CTRL $mainMod, F8, Handy toggle transcription, exec, notify-send -t 1500 -i audio-input-microphone "Handy" "Toggling transcription" && handy --toggle-transcription'
    } >> "$USER_KEYBINDS"
    echo "${OK} Added Handy keybind (CTRL+SUPER+F8) to UserKeybinds.conf" | tee -a "$LOG"
  else
    echo "${INFO} Handy keybind already present in UserKeybinds.conf, skipping." | tee -a "$LOG"
  fi
else
  echo "${WARN} $USER_KEYBINDS not found — install KooL dotfiles first to get the keybind." | tee -a "$LOG"
fi

# Autostart DISABLED by default to save RAM (~460MB: Handy + its embedded WebKit
# processes). Handy is rarely used, so it's launched on demand via CTRL+SUPER+F8
# instead. The line below is written commented-out so it's easy to re-enable:
# uncomment it in ~/.config/hypr/UserConfigs/Startup_Apps.conf. The launcher's
# visible-then-hidden logic is preserved in $HANDY_LAUNCHER for when you do.
# NOTE: with autostart off, the first-login model picker won't open automatically —
# run `handy` once manually to pick a model (Parakeet V3).
if [ -f "$STARTUP_APPS" ]; then
  if [ -x "$HANDY_LAUNCHER" ]; then
    AUTOSTART_LINE="# exec-once = $HANDY_LAUNCHER"
  else
    AUTOSTART_LINE="# exec-once = handy --start-hidden"
  fi
  if ! grep -qE "exec-once *= *(handy|.*handy-start\.sh)" "$STARTUP_APPS"; then
    {
      echo ""
      echo "# Handy autostart disabled by default to save RAM — uncomment to enable (launch on demand via CTRL+SUPER+F8)"
      echo "$AUTOSTART_LINE"
    } >> "$STARTUP_APPS"
    echo "${OK} Added Handy autostart (commented/disabled) to Startup_Apps.conf" | tee -a "$LOG"
  else
    echo "${INFO} Handy autostart already present in Startup_Apps.conf, skipping." | tee -a "$LOG"
  fi
else
  echo "${WARN} $STARTUP_APPS not found — autostart not added." | tee -a "$LOG"
fi

printf "\n${NOTE} ${SKY_BLUE}Handy${RESET} installed. Autostart is ${YELLOW}disabled${RESET} to save RAM — run ${MAGENTA}handy${RESET} once manually to pick a model (${MAGENTA}Parakeet V3${RESET} recommended, auto-detects 25 languages) and let it download. Afterwards, ${YELLOW}CTRL+SUPER+F8${RESET} launches it on demand and toggles transcription. To autostart it again, uncomment the exec-once line in ${SKY_BLUE}Startup_Apps.conf${RESET}.\n"
printf "\n%.0s" {1..2}
