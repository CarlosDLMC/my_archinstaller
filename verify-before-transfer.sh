#!/bin/bash
# Run this script BEFORE transferring to verify everything is ready

OK="$(tput setaf 2)[OK]$(tput sgr0)"
ERROR="$(tput setaf 1)[ERROR]$(tput sgr0)"
NOTE="$(tput setaf 3)[NOTE]$(tput sgr0)"
INFO="$(tput setaf 4)[INFO]$(tput sgr0)"
RESET="$(tput sgr0)"

# Resolve the repo and its name from this script's own location, rather than
# hardcoding the upstream project's name.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_NAME="$(basename "$REPO_DIR")"
# Every check below uses repo-relative paths.
cd "$REPO_DIR" || exit 1

printf "\n${NOTE} Verifying $REPO_NAME directory is ready for transfer...\n\n"

# Check if we're in the right directory
if [ ! -f "$REPO_DIR/install.sh" ]; then
    printf "${ERROR} This script must be run from the $REPO_NAME directory\n"
    printf "${INFO} Run: cd $REPO_DIR && ./verify-before-transfer.sh\n"
    exit 1
fi

all_good=true

# What a run actually reads. A fixed list of 8 files used to pass trees the new
# machine could not install from: a copy without dotfiles/wallpapers (the
# obvious thing to drop) or yay-bin/PKGBUILD got "All critical files and
# directories are present!", and install.sh then stopped at "No working AUR
# helper", or the wallpaper check failed. The scripts come from install.sh itself
# (every execute_script / run_required call), so a new one is covered as well.
check_file() {
    if [ -f "$1" ]; then
        printf "  ${OK} $1\n"
    else
        printf "  ${ERROR} $1 MISSING\n"
        all_good=false
    fi
}
check_dir() { # non-empty
    if [ -d "$1" ] && [ -n "$(ls -A "$1" 2>/dev/null)" ]; then
        printf "  ${OK} $1/\n"
    else
        printf "  ${ERROR} $1/ MISSING or empty\n"
        all_good=false
    fi
}

printf "${INFO} Checking the scripts install.sh runs...\n"
check_file install.sh
while read -r _script; do
    check_file "install-scripts/$_script"
done < <(grep -oE '(execute_script|run_required) "[^"$]+\.sh"' install.sh | sed -E 's/.* "(.*)"/\1/' | sort -u)

printf "\n${INFO} Checking what those scripts read...\n"
# rust-bar.sh builds the bar from pkgbuilds/rust-bar and the rust-bar/ crate;
# Cargo.lock too, the build is --locked.
for _file in install-scripts/Global_functions.sh install-scripts/nvidia_detect.sh \
             install-scripts/checksum-skip.conf custom-preset.conf yay-bin/PKGBUILD \
             pkgbuilds/rust-bar/PKGBUILD rust-bar/Cargo.toml rust-bar/Cargo.lock \
             dotfiles/copy.sh dotfiles/.zshrc dotfiles/pokefetch_perfect \
             dotfiles/.local/bin/pokefetch-merge diagnose.sh; do
    check_file "$_file"
done
# icons/: the logo cuts plymouth.sh and hackbgrt.sh render from. GTK-themes-icons/:
# the GTK theme, icons and cursor gtk_themes.sh extracts.
for _dir in assets icons GTK-themes-icons rust-bar/src dotfiles/wallpapers dotfiles/.local/bin dotfiles/config/hypr \
            dotfiles/config/mango dotfiles/config/rust-bar dotfiles/config/wallust \
            dotfiles/config/foot dotfiles/config/rofi; do
    check_dir "$_dir"
done

# What a clone gets. A `git clone` on the new machine has only what was
# committed and pushed; a tarball or rsync of this folder has the working tree.
# Said, not failed: which one you use is up to you.
if git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    printf "\n${INFO} Checking what a git clone would get...\n"
    _dirty=$(git status --porcelain 2>/dev/null | wc -l)
    if [ "$_dirty" -gt 0 ]; then
        printf "  ${NOTE} $_dirty changed or untracked file(s) are not committed - a clone will not have them (a tarball or rsync of this folder will):\n"
        git status --short 2>/dev/null | head -10 | sed 's/^/      /'
    else
        printf "  ${OK} Working tree is committed\n"
    fi
    if _ahead=$(git rev-list --count '@{u}..HEAD' 2>/dev/null); then
        if [ "$_ahead" -gt 0 ]; then
            printf "  ${NOTE} $_ahead commit(s) not pushed - push before cloning on the new machine\n"
        else
            printf "  ${OK} Everything committed is pushed\n"
        fi
    fi
fi

# Show directory size
printf "\n${INFO} Directory size:\n"
du -sh . 2>/dev/null | sed 's/^/  /'
printf "\n${INFO} dotfiles size:\n"
du -sh dotfiles/ 2>/dev/null | sed 's/^/  /'

# Summary
printf "\n${NOTE} ========== SUMMARY ==========\n"
if [ "$all_good" = true ]; then
    printf "${OK} All critical files and directories are present!\n\n"
    printf "${INFO} Ready to transfer. Use one of these methods:\n\n"
    printf "1. USB Transfer:\n"
    printf "   tar -czf ~/$REPO_NAME.tar.gz -C $(dirname "$REPO_DIR") $REPO_NAME\n"
    printf "   # Copy ~/$REPO_NAME.tar.gz to USB\n\n"
    printf "2. Network transfer (if both computers are networked):\n"
    printf "   rsync -av $REPO_DIR/ user@newcomputer:~/Documents/$REPO_NAME/\n\n"
    printf "3. On new computer after transfer:\n"
    printf "   cd ~/Documents/$REPO_NAME\n"
    printf "   ./install.sh --preset custom-preset.conf\n\n"
else
    printf "${ERROR} Some files are missing! Fix these before transferring.\n"
    exit 1
fi
