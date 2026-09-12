#!/bin/bash
# zsh and oh my zsh#

zsh_pkg=(
  lsd
  mercurial
  zsh
  zsh-completions
)

zsh_pkg2=(
  fzf
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
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_zsh.log"

# Installing core zsh packages
printf "\n%s - Installing ${SKY_BLUE}zsh packages${RESET} .... \n" "${NOTE}"
for ZSH in "${zsh_pkg[@]}"; do
  install_package "$ZSH" "$LOG"
done 



# Check if the zsh-completions directory exists
if [ -d "zsh-completions" ]; then
    rm -rf zsh-completions
fi

# Install Oh My Zsh, plugins, and set zsh as default shell
if command -v zsh >/dev/null; then
  printf "${NOTE} Installing ${SKY_BLUE}Oh My Zsh and plugins${RESET} ...\n"
  if [ ! -d "$HOME/.oh-my-zsh" ]; then  
    sh -c "$(curl -fsSL https://install.ohmyz.sh)" "" --unattended  	       
  else
    echo "${INFO} Directory .oh-my-zsh already exists. Skipping re-installation." 2>&1 | tee -a "$LOG"
  fi
  
  # Check if the directories exist before cloning the repositories
  if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]; then
      git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions 
  else
      echo "${INFO} Directory zsh-autosuggestions already exists. Cloning Skipped." 2>&1 | tee -a "$LOG"
  fi

  if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]; then
      git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting 
  else
      echo "${INFO} Directory zsh-syntax-highlighting already exists. Cloning Skipped." 2>&1 | tee -a "$LOG"
  fi
  
  # Check if ~/.zshrc and .zprofile exists, create a backup, and copy the new configuration
  if [ -f "$HOME/.zshrc" ]; then
      cp -b "$HOME/.zshrc" "$HOME/.zshrc-backup" || true
  fi

  if [ -f "$HOME/.zprofile" ]; then
      cp -b "$HOME/.zprofile" "$HOME/.zprofile-backup" || true
  fi
  
  # Copying the preconfigured zsh themes and profile
  #
  # These come from Hyprland-Dots/, which is the single source for every shell
  # file: it is what copy.sh deploys, so it is the version that actually ends up
  # on the machine. assets/ used to carry a second copy of .zshrc that drifted -
  # it kept the unguarded `source $ZSH/oh-my-zsh.sh` and `source <(fzf --zsh)`
  # and never sourced ~/.config/zsh/secrets.zsh - and this script copied *that*
  # one. Nothing broke only because the option loop happens to run dots after
  # zsh, so copy.sh overwrote it a few seconds later.
  cp -r 'Hyprland-Dots/.zshrc' ~/
  cp -r 'Hyprland-Dots/.zprofile' ~/

  # Copy custom pokefetch_perfect script and dependencies
  if [ -f 'Hyprland-Dots/pokefetch_perfect' ]; then
      cp 'Hyprland-Dots/pokefetch_perfect' ~/
      chmod +x ~/pokefetch_perfect
  fi

  # Copy pokefetch-merge python helper to ~/.local/bin/
  if [ -f 'Hyprland-Dots/.local/bin/pokefetch-merge' ]; then
      mkdir -p ~/.local/bin
      cp 'Hyprland-Dots/.local/bin/pokefetch-merge' ~/.local/bin/
      chmod +x ~/.local/bin/pokefetch-merge
  fi

  # Copy pokefetch.jsonc fastfetch config - from the dotfiles, which are the
  # single copy now that the duplicate assets/fastfetch/ has gone.
  if [ -f 'Hyprland-Dots/config/fastfetch/pokefetch.jsonc' ]; then
      mkdir -p ~/.config/fastfetch
      cp 'Hyprland-Dots/config/fastfetch/pokefetch.jsonc' ~/.config/fastfetch/
  fi

  # Prefer the zsh listed in /etc/shells over `command -v zsh`.
  #
  # /usr/sbin is a symlink to /usr/bin on Arch and can come first in PATH, so
  # `command -v zsh` may answer /usr/sbin/zsh - which is the same binary but is
  # NOT in /etc/shells. chsh warns and sets it anyway, leaving a login shell
  # that anything validating against /etc/shells (ftp/su/some PAM setups) will
  # reject, and that never compares equal to the /usr/bin/zsh already in passwd
  # - so this block would re-run chsh on every single install.
  zsh_path=""
  while read -r _sh; do
    case "$_sh" in */zsh) [ -x "$_sh" ] && { zsh_path="$_sh"; break; } ;; esac
  done < /etc/shells
  [ -n "$zsh_path" ] || zsh_path=$(command -v zsh)

  # Read the login shell out of the passwd database rather than $SHELL, which
  # is inherited from whatever launched this script and can disagree with the
  # real entry. Compare resolved paths so /bin/zsh and /usr/bin/zsh - the same
  # binary through a compat symlink - do not read as a difference.
  current_shell=$(getent passwd "$USER" | cut -d: -f7)

  if [ "$(readlink -f "$current_shell" 2>/dev/null)" != "$(readlink -f "$zsh_path")" ]; then
    printf "${NOTE} Changing default shell to ${MAGENTA}zsh${RESET}...\n"

    # `sudo chsh -s ... "$USER"`, not a bare `chsh`. /etc/pam.d/chsh is
    # `auth required pam_unix.so`, so an unprivileged chsh prompts for the
    # user's password itself - a second, separate password prompt in the middle
    # of what --preset advertises as an unattended run. The old `while ! chsh`
    # loop around it then spun forever on a wrong answer, printing the same
    # error once a second with no exit but Ctrl-C. Under sudo, pam_rootok
    # short-circuits the prompt and this reuses the sudo session the install
    # already has.
    if sudo chsh -s "$zsh_path" "$USER" >> "$LOG" 2>&1; then
      printf "${INFO} Shell changed successfully to ${MAGENTA}zsh${RESET}\n" | tee -a "$LOG"
    else
      # Not fatal: everything else in the install still works, you just land in
      # bash until this is set. Failing the whole run over it would be worse.
      echo "${WARN} Could not change the login shell. Set it yourself with: chsh -s $zsh_path" | tee -a "$LOG"
    fi
  else
    echo "${NOTE} Your shell is already set to ${MAGENTA}zsh${RESET}."
  fi
  
fi

# Installing core zsh packages
printf "\n%s - Installing ${SKY_BLUE}fzf${RESET} .... \n" "${NOTE}"
for ZSH2 in "${zsh_pkg2[@]}"; do
  install_package "$ZSH2" "$LOG"
done

# copy additional oh-my-zsh themes from assets
if [ -d "$HOME/.oh-my-zsh/themes" ]; then
    cp -r assets/add_zsh_theme/* ~/.oh-my-zsh/themes >> "$LOG" 2>&1
fi

printf "\n%.0s" {1..2}
