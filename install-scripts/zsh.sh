#!/bin/bash
# zsh and oh my zsh#

zsh_pkg=(
  lsd
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
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

# Source the global functions script
if ! source "$SCRIPT_DIR/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi



# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_zsh.log"

# Installing core zsh packages
printf "\n%s - Installing ${SKY_BLUE}zsh packages${RESET} .... \n" "${NOTE}"
# Not `for ZSH in ...`: ZSH is the variable the oh-my-zsh installer reads as
# its install directory. When install.sh is started from a zsh that exports it
# (the repo .zshrc does), the loop left ZSH=zsh-completions in the exported
# environment and oh-my-zsh installed itself into <repo>/zsh-completions.
for _zpkg in "${zsh_pkg[@]}"; do
  install_package "$_zpkg" "$LOG"
done
# And pin it for the installer below, whatever the parent exported.
export ZSH="$HOME/.oh-my-zsh"



# Check if the zsh-completions directory exists
if [ -d "zsh-completions" ]; then
    rm -rf zsh-completions
fi

# Install Oh My Zsh, plugins, and set zsh as default shell
if command -v zsh >/dev/null; then
  printf "${NOTE} Installing ${SKY_BLUE}Oh My Zsh and plugins${RESET} ...\n"
  # Test for the file .zshrc sources, not the directory: the plugin clones below
  # create ~/.oh-my-zsh themselves, so after one failed download the directory
  # existed, this branch was skipped forever, and .zshrc sourced nothing.
  if [ ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]; then
    # The upstream installer refuses to run when $ZSH already exists ("You'll
    # need to remove it"), so a ~/.oh-my-zsh left holding only custom/plugins
    # from an earlier failed run made every re-run exit here. Move it aside;
    # the plugin clones below recreate what it held.
    if [ -e "$HOME/.oh-my-zsh" ]; then
      _omz_bak="$HOME/.oh-my-zsh.incomplete-$(date +%Y%m%d-%H%M%S)"
      mv -T "$HOME/.oh-my-zsh" "$_omz_bak"
      echo "${NOTE} ~/.oh-my-zsh had no oh-my-zsh.sh - moved it to $(basename "$_omz_bak") and reinstalling." | tee -a "$LOG"
    fi
    # A plain clone, not https://install.ohmyz.sh piped into a shell: that script
    # came unpinned from a separate deployment (Vercel, not the GitHub repo) and
    # ran unread, with passwordless sudo already in place - and with
    # --unattended --keep-zshrc all it did was this clone, plus a template
    # .zshrc that had to be thrown away again. Same git settings and umask as
    # its own clone, so `omz update` works as usual. Not fatal: this used to
    # `exit 1`, which also skipped chsh and everything else below that does not
    # need Oh My Zsh. The final check reports a missing ~/.oh-my-zsh.
    if (umask g-w,o-w; git clone --quiet --depth=1 --branch master \
          -c core.eol=lf -c core.autocrlf=false -c fsck.zeroPaddedFilemode=ignore \
          -c fetch.fsck.zeroPaddedFilemode=ignore -c receive.fsck.zeroPaddedFilemode=ignore \
          -c oh-my-zsh.remote=origin -c oh-my-zsh.branch=master \
          https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh") >> "$LOG" 2>&1; then
      echo "${OK} Oh My Zsh cloned to ~/.oh-my-zsh" | tee -a "$LOG"
    else
      echo "${ERROR} Could not clone Oh My Zsh (network?) - continuing without it" | tee -a "$LOG"
    fi
  else
    echo "${INFO} Directory .oh-my-zsh already exists. Skipping re-installation." 2>&1 | tee -a "$LOG"
  fi
  
  # Guarded clones. Global_functions.sh runs `set -e`, so a bare failing
  # `git clone` (a network blip, a GitHub hiccup) used to end zsh.sh right here -
  # skipping .zshrc, chsh, fzf and the themes, with bash left as the login
  # shell. A failed plugin is now reported and the rest carries on; the final
  # check names it.
  _omz_plugins="$HOME/.oh-my-zsh/custom/plugins"
  for _plugin in \
      "zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions" \
      "zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git"; do
    _pname="${_plugin%% *}"; _purl="${_plugin#* }"
    if [ -d "$_omz_plugins/$_pname" ]; then
      echo "${INFO} Directory $_pname already exists. Cloning Skipped." 2>&1 | tee -a "$LOG"
    elif git clone "$_purl" "$_omz_plugins/$_pname" >> "$LOG" 2>&1; then
      echo "${OK} Cloned $_pname" | tee -a "$LOG"
    else
      # A partial clone would make the -d test above skip it forever.
      rm -rf "$_omz_plugins/$_pname"
      echo "${ERROR} Could not clone $_pname - re-run install-scripts/zsh.sh once the network is back." | tee -a "$LOG"
    fi
  done
  
  # Copying the preconfigured .zshrc, .zprofile and pokefetch_perfect
  #
  # These come from Hyprland-Dots/, which is the single source for every shell
  # file: it is what copy.sh deploys, so it is the version that actually ends up
  # on the machine. assets/ used to carry a second copy of .zshrc that drifted -
  # it kept the unguarded `source $ZSH/oh-my-zsh.sh` and `source <(fzf --zsh)`
  # and never sourced ~/.config/zsh/secrets.zsh - and this script copied *that*
  # one.
  #
  # Skipped when 'dots' is selected, like pokefetch.jsonc below: copy.sh deploys
  # all three a few seconds later (the option loop runs dots after zsh) and
  # backs up whatever differs to <file>.backup-<stamp> first. Copying them here
  # as well made copy.sh find ~/.zshrc already identical to the repo, so it
  # never made that backup - and the `cp -b ~/.zshrc ~/.zshrc-backup` that stood
  # in for it keeps one generation plus a `~`, so an alias you had added was
  # gone for good after the third re-run. Without dots this is the only deploy,
  # and it does what copy.sh does: back up only a file that differs, to a
  # stamped name that no later run overwrites.
  if [[ " ${INSTALL_SELECTED_OPTIONS:-} " == *" dots "* ]]; then
      echo "${NOTE} .zshrc, .zprofile and pokefetch_perfect come with the dotfiles (dots selected), not copied here." 2>&1 | tee -a "$LOG"
  else
      _shell_stamp="$(date +%Y%m%d-%H%M%S)"
      for _file in .zshrc .zprofile pokefetch_perfect; do
          [ -f "Hyprland-Dots/$_file" ] || continue
          if [ -f "$HOME/$_file" ] && ! cmp -s "Hyprland-Dots/$_file" "$HOME/$_file"; then
              cp "$HOME/$_file" "$HOME/$_file.backup-$_shell_stamp" &&
                  echo "${NOTE} Backed up existing $_file to $_file.backup-$_shell_stamp" | tee -a "$LOG"
          fi
          cp "Hyprland-Dots/$_file" "$HOME/" && echo "${OK} Copied $_file" | tee -a "$LOG"
      done
      if [ -f "$HOME/pokefetch_perfect" ]; then chmod +x "$HOME/pokefetch_perfect"; fi
  fi

  # pokefetch-merge (python helper) into ~/.local/bin. With dots selected that is
  # copy.sh's, like the files above: it deploys all of .local/bin a few seconds
  # later and backs up whatever differs. Copied here first, an edited helper was
  # overwritten before copy.sh could see the difference - gone, no backup.
  # Without dots this is its only deploy, and it backs up the same way.
  if [[ " ${INSTALL_SELECTED_OPTIONS:-} " == *" dots "* ]]; then
      echo "${NOTE} pokefetch-merge comes with the dotfiles (dots selected), not copied here." 2>&1 | tee -a "$LOG"
  elif [ -f 'Hyprland-Dots/.local/bin/pokefetch-merge' ]; then
      mkdir -p ~/.local/bin
      if [ -f ~/.local/bin/pokefetch-merge ] && ! cmp -s 'Hyprland-Dots/.local/bin/pokefetch-merge' ~/.local/bin/pokefetch-merge; then
          _pm_bak="$HOME/.local/bin/pokefetch-merge.backup-$(date +%Y%m%d-%H%M%S)"
          cp ~/.local/bin/pokefetch-merge "$_pm_bak" && chmod -x "$_pm_bak" &&
              echo "${NOTE} Backed up your pokefetch-merge to $(basename "$_pm_bak")" | tee -a "$LOG"
      fi
      cp 'Hyprland-Dots/.local/bin/pokefetch-merge' ~/.local/bin/
      chmod +x ~/.local/bin/pokefetch-merge
  fi

  # Copy pokefetch.jsonc fastfetch config - from the dotfiles, which are the
  # single copy now that the duplicate assets/fastfetch/ has gone.
  #
  # Skipped when 'dots' is selected: copy.sh deploys the whole fastfetch/
  # directory later and backs up anything already there, so creating it here
  # left a fastfetch.backup-<stamp> holding this one file on every fresh install.
  if [[ " ${INSTALL_SELECTED_OPTIONS:-} " == *" dots "* ]]; then
      echo "${NOTE} pokefetch.jsonc comes with the dotfiles (dots selected), not copied here." 2>&1 | tee -a "$LOG"
  elif [ -f 'Hyprland-Dots/config/fastfetch/pokefetch.jsonc' ]; then
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
for _zpkg in "${zsh_pkg2[@]}"; do
  install_package "$_zpkg" "$LOG"
done

# copy additional oh-my-zsh themes from assets. One that differs from the
# repo's - edited in place, agnoster_modificado say - is backed up first, the
# way copy.sh treats dotfiles: a re-run used to overwrite it with nothing left
# of the edit.
if [ -d "$HOME/.oh-my-zsh/themes" ]; then
    _theme_stamp="$(date +%Y%m%d-%H%M%S)"
    for _theme in assets/add_zsh_theme/*; do
        _theme_dst="$HOME/.oh-my-zsh/themes/${_theme##*/}"
        if [ -f "$_theme_dst" ] && ! cmp -s "$_theme" "$_theme_dst"; then
            cp "$_theme_dst" "$_theme_dst.backup-$_theme_stamp" &&
                echo "${NOTE} Backed up your ${_theme##*/} to ${_theme##*/}.backup-$_theme_stamp" | tee -a "$LOG"
        fi
        cp -r "$_theme" "$HOME/.oh-my-zsh/themes/" >> "$LOG" 2>&1
    done
fi

printf "\n%.0s" {1..2}
