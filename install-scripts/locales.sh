#!/bin/bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  #
# Generate the locales this setup actually uses

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || exit 1

source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_locales.log"

# Why this exists
#
# Setting LC_TIME to a locale that was never generated does not fail - glibc
# falls back to C, silently. So without this the clock goes 12-hour, the bar's
# calendar starts on Sunday, and the lock screen's date comes back in English
# instead of Cyrillic, with nothing anywhere saying why.
#
# Three consumers:
#   - environment.d/locale.conf and hypr/configs/ENVariables.conf set
#     LC_TIME=ru_RU.UTF-8. CalendarPopup.qml reads Qt.locale() for
#     firstDayOfWeek and for its "MMMM yyyy" heading, so this is what makes the
#     calendar start on Monday with Russian month names.
#   - SovietLock.py calls setlocale(LC_TIME, "ru_RU.utf8") and its own comment
#     says it falls back to C "if ru_RU is not generated on this machine" -
#     which is exactly what happened on a fresh install until now.
#   - es_US and en_US pair with the ES/US keyboard layouts.
#
# LANG stays whatever /etc/locale.conf says (en_US.UTF-8 here); only LC_TIME is
# Russian, so interfaces stay in English and just dates and times are localised.

LOCALE_GEN="/etc/locale.gen"

# Locales to generate.
wanted_locales=(
  "en_US.UTF-8 UTF-8"
  "es_US.UTF-8 UTF-8"
  "ru_RU.UTF-8 UTF-8"
)

# Locales to explicitly comment back out. de_DE used to provide LC_TIME here
# before the switch to ru_RU; nothing references it any more.
unwanted_locales=(
  "de_DE.UTF-8 UTF-8"
)

printf "\n${NOTE} Generating ${SKY_BLUE}locales${RESET}...\n"

if [ ! -f "$LOCALE_GEN" ]; then
  echo "${ERROR} $LOCALE_GEN not found - cannot generate locales." | tee -a "$LOG"
  exit 1
fi

changed=0

for _locale in "${wanted_locales[@]}"; do
  # Escape every regex metacharacter in the locale string. The dots in
  # "en_US.UTF-8" would otherwise match any character, so "#en_US.UTF-8 UTF-8"
  # could be matched by an unrelated line.
  _escaped=$(printf '%s' "$_locale" | sed 's/[][\.*^$/]/\\&/g')

  if grep -qE "^${_escaped}\s*$" "$LOCALE_GEN"; then
    echo "${OK} $_locale already enabled" | tee -a "$LOG"
  elif grep -qE "^#\s*${_escaped}\s*$" "$LOCALE_GEN"; then
    sudo sed -i -E "s/^#\s*${_escaped}\s*$/${_escaped}/" "$LOCALE_GEN"
    echo "${OK} Enabled $_locale" | tee -a "$LOG"
    changed=1
  else
    # Not present at all (a trimmed locale.gen). Append it.
    echo "$_locale" | sudo tee -a "$LOCALE_GEN" >/dev/null
    echo "${OK} Added $_locale" | tee -a "$LOG"
    changed=1
  fi
done

for _locale in "${unwanted_locales[@]}"; do
  _escaped=$(printf '%s' "$_locale" | sed 's/[][\.*^$/]/\\&/g')
  if grep -qE "^${_escaped}\s*$" "$LOCALE_GEN"; then
    sudo sed -i -E "s/^${_escaped}\s*$/#${_escaped}/" "$LOCALE_GEN"
    echo "${NOTE} Disabled $_locale (no longer used)" | tee -a "$LOG"
    changed=1
  fi
done

# locale-gen rebuilds every enabled locale, so only run it if something moved.
if [ "$changed" -eq 1 ]; then
  printf "${NOTE} Running locale-gen (this takes a few seconds)...\n"
  if sudo locale-gen 2>&1 | tee -a "$LOG"; then
    echo "${OK} Locales generated" | tee -a "$LOG"
  else
    echo "${ERROR} locale-gen failed - check $LOG" | tee -a "$LOG"
    exit 1
  fi
else
  echo "${NOTE} No locale changes needed, skipping locale-gen" | tee -a "$LOG"
fi

# Verify, because a missing locale is otherwise invisible until the clock is
# wrong. locale -a reports the generated names in normalised form (ru_RU.utf8).
printf "\n${NOTE} Verifying generated locales...\n"
_available=$(locale -a 2>/dev/null)
for _locale in "${wanted_locales[@]}"; do
  _name="${_locale%% *}"                       # en_US.UTF-8
  _normalised=$(echo "$_name" | tr 'A-Z' 'a-z' | tr -d '-')   # en_us.utf8
  if echo "$_available" | tr 'A-Z' 'a-z' | tr -d '-' | grep -qx "$_normalised"; then
    echo "${OK} $_name" | tee -a "$LOG"
  else
    echo "${WARN} $_name is NOT available - anything using it falls back to C" | tee -a "$LOG"
  fi
done

printf "\n%.0s" {1..2}
