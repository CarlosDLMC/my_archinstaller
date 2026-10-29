#!/bin/bash
# Diagnostic script to check what went wrong with the installation

# Set colors
OK="$(tput setaf 2)[OK]$(tput sgr0)"
ERROR="$(tput setaf 1)[ERROR]$(tput sgr0)"
NOTE="$(tput setaf 3)[NOTE]$(tput sgr0)"
INFO="$(tput setaf 4)[INFO]$(tput sgr0)"
WARN="$(tput setaf 1)[WARN]$(tput sgr0)"
RESET="$(tput sgr0)"

# Resolve the repo from this script's own location. These paths used to be
# hardcoded to $REPO_DIR - the upstream project's name - so
# every check below reported "not found" no matter how healthy the install was.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

printf "\n${NOTE} Running diagnostic checks...\n\n"

# Every [ERROR] / [WARN] below counts: the verdict at the end is not "looks
# good" while the config, the bar or a package is missing.
problems=0

# Check if copy logs exist
printf "${INFO} Checking if dotfiles installation was attempted...\n"
if [ -d $REPO_DIR/Install-Logs ]; then
    if ls $REPO_DIR/Install-Logs/dotfiles-copy-*.log 1> /dev/null 2>&1; then
        printf "  ${OK} Dotfiles copy log found\n"
        latest_log=$(ls -t $REPO_DIR/Install-Logs/dotfiles-copy-*.log 2>/dev/null | head -1)
        printf "  ${INFO} Latest log: $latest_log\n"
        if [ -f "$latest_log" ]; then
            printf "  ${INFO} Last 10 lines of copy log:\n"
            tail -10 "$latest_log" | sed 's/^/    /'
        fi
    else
        problems=$((problems + 1)); printf "  ${WARN} No dotfiles copy log found (installation may not have run)\n"
    fi
else
    problems=$((problems + 1)); printf "  ${WARN} Install-Logs directory not found\n"
fi

# The mango config: there, and accepted. mango writes no default config of its
# own - without this file it runs on its built-in defaults, none of the binds,
# bar or theming in place.
printf "\n${INFO} Checking the mango configuration...\n"
if [ -f ~/.config/mango/config.conf ]; then
    if ! command -v mango &>/dev/null; then
        problems=$((problems + 1)); printf "  ${ERROR} ~/.config/mango/config.conf is there, but mango is not installed\n"
    # mango -p exits 0 even when it reports errors: the verdict is any [ERROR].
    elif _mango_out=$(mango -c ~/.config/mango/config.conf -p 2>&1) && ! grep -qF "[ERROR]" <<<"$_mango_out"; then
        printf "  ${OK} Using the custom mango config, and mango accepts it\n"
    else
        problems=$((problems + 1)); printf "  ${ERROR} mango rejects ~/.config/mango/config.conf - see: mango -c ~/.config/mango/config.conf -p\n"
    fi
else
    problems=$((problems + 1)); printf "  ${ERROR} ~/.config/mango/config.conf not found at all (PROBLEM FOUND)\n"
    printf "  ${NOTE} The custom dotfiles were NOT copied properly\n"
fi

# Check how many directories in ~/.config
printf "\n${INFO} Checking ~/.config directories...\n"
config_count=$(ls -d ~/.config/*/ 2>/dev/null | wc -l)
printf "  ${INFO} Found $config_count directories in ~/.config\n"
if [ "$config_count" -lt 15 ]; then
    problems=$((problems + 1)); printf "  ${WARN} Only $config_count directories (expected 15+). Custom dotfiles likely NOT copied.\n"
    printf "  ${INFO} Directories found: $(ls -d ~/.config/*/ 2>/dev/null | xargs -n1 basename | tr '\n' ' ')\n"
else
    printf "  ${OK} Found $config_count directories (looks good)\n"
fi

# Check if custom config sources exist
printf "\n${INFO} Checking critical custom directories...\n"
# hypr/ still holds the scripts every bind runs, and hyprlock/hypridle's files.
if [ -d ~/.config/hypr/scripts ] && [ -f ~/.config/hypr/hyprlock.conf ]; then
    printf "  ${OK} ~/.config/hypr (scripts, lock screen) exists\n"
else
    problems=$((problems + 1)); printf "  ${ERROR} ~/.config/hypr scripts or hyprlock.conf MISSING (custom config not installed)\n"
fi

if [ -d ~/.config/quickshell ]; then
    printf "  ${OK} ~/.config/quickshell exists\n"
else
    problems=$((problems + 1)); printf "  ${ERROR} ~/.config/quickshell MISSING (the bar's scripts and wallust palette - dotfiles not copied)\n"
fi

if [ -d ~/.config/wallust ]; then
    printf "  ${OK} ~/.config/wallust exists\n"
else
    problems=$((problems + 1)); printf "  ${ERROR} ~/.config/wallust MISSING\n"
fi

# Check if installation directory is complete
printf "\n${INFO} Checking installer directory...\n"
if [ -d $REPO_DIR ]; then
    printf "  ${OK} $REPO_DIR exists\n"
    if [ -d $REPO_DIR/dotfiles ]; then
        printf "  ${OK} dotfiles subdirectory exists\n"
        if [ -f $REPO_DIR/dotfiles/copy.sh ]; then
            printf "  ${OK} copy.sh exists in dotfiles\n"
        else
            problems=$((problems + 1)); printf "  ${ERROR} copy.sh NOT found in dotfiles\n"
        fi
    else
        problems=$((problems + 1)); printf "  ${ERROR} dotfiles subdirectory MISSING (this is the problem!)\n"
        printf "  ${NOTE} The installation cannot work without this directory\n"
    fi
else
    problems=$((problems + 1)); printf "  ${ERROR} $REPO_DIR directory not found\n"
fi

# Check essential packages
printf "\n${INFO} Checking essential packages...\n"
essential_packages=(
    "mangowm"
    "hyprlock"
    "hypridle"
    "hyprpolkitagent"
    # dunst, not mako: dunst is the notification daemon this setup runs.
    "dunst"
    "xdg-desktop-portal-wlr"
    "rust-bar"
    "foot"
    "wlsunset"
    "wlopm"
    "wireguard-tools"
)

missing_packages=()
build_bar=false
for pkg in "${essential_packages[@]}"; do
    if pacman -Qi "$pkg" &>/dev/null; then
        printf "  ${OK} $pkg is installed\n"
    elif [ "$pkg" = rust-bar ]; then
        # Built from the repo's rust-bar/ crate: no repository and not the AUR
        # has it, so `yay -S` below would fail for the whole list.
        problems=$((problems + 1)); printf "  ${ERROR} rust-bar (the bar) is MISSING\n"
        build_bar=true
    else
        problems=$((problems + 1)); printf "  ${ERROR} $pkg is MISSING\n"
        missing_packages+=("$pkg")
    fi
done

# Check pokefetch scripts
printf "\n${INFO} Checking pokefetch scripts...\n"
if [ -f ~/pokefetch_perfect ]; then
    printf "  ${OK} ~/pokefetch_perfect exists\n"
else
    problems=$((problems + 1)); printf "  ${ERROR} ~/pokefetch_perfect MISSING\n"
fi

if [ -f ~/.local/bin/pokefetch-merge ]; then
    printf "  ${OK} ~/.local/bin/pokefetch-merge exists\n"
else
    problems=$((problems + 1)); printf "  ${ERROR} ~/.local/bin/pokefetch-merge MISSING\n"
fi

# Check the login manager. This setup uses ly on tty2, not SDDM - checking for
# SDDM meant a healthy machine always reported its login manager as missing.
printf "\n${INFO} Checking login manager...\n"
if systemctl is-enabled ly@tty2.service &>/dev/null; then
    printf "  ${OK} ly is enabled on tty2\n"
elif systemctl is-enabled ly &>/dev/null; then
    problems=$((problems + 1)); printf "  ${WARN} ly is enabled, but not as ly@tty2.service\n"
else
    problems=$((problems + 1)); printf "  ${WARN} ly is NOT enabled - run: sudo systemctl enable ly@tty2.service\n"
fi

# Summary
printf "\n${NOTE} ========== SUMMARY ==========\n"
if [ ${#missing_packages[@]} -gt 0 ]; then
    problems=$((problems + 1)); printf "${ERROR} Missing packages found: ${missing_packages[*]}\n"
    printf "${INFO} To install missing packages, run:\n"
    printf "  yay -S ${missing_packages[*]}\n\n"
fi
if [ "$build_bar" = true ]; then
    printf "${INFO} To build and install the bar from rust-bar/, run:\n"
    printf "  $REPO_DIR/install-scripts/rust-bar.sh\n\n"
fi

if [ ! -f ~/.config/mango/config.conf ]; then
    printf "\n${WARN} ========== FIX REQUIRED ==========\n"
    printf "${INFO} Your dotfiles were not copied. To fix this:\n\n"
    printf "1. Run the copy script manually:\n"
    printf "   cd $REPO_DIR/dotfiles\n"
    printf "   chmod +x copy.sh\n"
    printf "   ./copy.sh\n\n"
    printf "2. Log out of mango (CTRL+ALT+Delete, or: mmsg dispatch quit) and back in\n\n"
    printf "   (or reboot your system)\n"
elif [ "$problems" -eq 0 ]; then
    printf "${OK} Configuration looks good!\n"
else
    printf "${WARN} $problems problem(s) found above - see the [ERROR] and [WARN] lines.\n"
fi

printf "\n"
[ "$problems" -eq 0 ]
