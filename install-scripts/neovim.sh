#!/bin/bash
# Neovim + LazyVim - the editor and, more to the point, the file tree.
#
# This exists because of the file explorer. Herdr gives you panes; it has no file
# browser of its own and no way to open one (its `goto` action is a session
# navigator, not a file picker). The tree in a herdr pane is Neovim's, drawn by
# snacks.explorer, which LazyVim ships and binds to Space E. So "a file explorer
# next to the agents" is a Neovim question that happens to be answered inside a
# herdr pane.
#
# LazyVim is installed the way upstream says to: clone the starter template into
# ~/.config/nvim and drop its .git. The plugins themselves are fetched by lazy.nvim
# on first launch, which this script does once, headless, so the first interactive
# start is not a two-minute progress bar.
#
# The config is deliberately NOT a tracked dotfile. The starter is meant to be
# forked and grown - lua/plugins/*.lua is yours - and vendoring a copy here would
# both freeze someone else's template and put copy.sh's wholesale directory
# replacement on top of your own plugin files every re-run. Same reasoning as the
# other machine-specific things in the README's "What is deliberately NOT in this
# repo".
#
# The colorscheme is the one exception, and it is installed from assets/nvim/
# rather than shipped as a dotfile, precisely so copy.sh's wholesale replacement
# never touches ~/.config/nvim. See "the theme" below for how the two files
# differ: the palette is ours, the file that selects it is yours after the first
# install.
#
# NOTE: $EDITOR is left alone. It is "vim" from UserConfigs/01-UserDefaults.lua and
# nothing here needs it to change - the herdr layouts name `nvim` outright. Change
# that one line yourself if you want nvim to be the system editor too.

neovim_pkg=(
  neovim
  ripgrep         # Space S G (grep with preview) and LazyVim's picker backend
  fd              # Space Space (fuzzy file find)
  lazygit         # Space G G, LazyVim's floating git UI

  # The next three are LazyVim's own tooling, and they come from the repos here
  # rather than from mason.nvim on purpose. mason installs asynchronously inside
  # a running nvim, and the headless "+Lazy! sync" below exits as soon as lazy is
  # done - which kills those installs mid-flight. On the machine this was tested
  # on that left nvim-treesitter reporting a hard
  #   Unmet requirements for nvim-treesitter `main`: ❌ tree-sitter (CLI)
  # with no parsers and no syntax highlighting, and mason logging "Neovim is
  # exiting while packages are still installing". Arch packages all three, so
  # pacman installs them synchronously and mason has nothing left to race.
  tree-sitter-cli # nvim-treesitter's `main` branch requires the CLI to build parsers
  stylua          # Lua formatter LazyVim configures out of the box
  shfmt           # shell formatter, same
)

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "${ERROR} Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_neovim.log"

printf "\n%s - Installing ${SKY_BLUE}Neovim${RESET} and its pickers .... \n" "${NOTE}"
for PKG in "${neovim_pkg[@]}"; do
  install_package "$PKG" "$LOG"
done

if ! command -v nvim >/dev/null 2>&1; then
  echo "${ERROR} neovim did not install - skipping the LazyVim config." | tee -a "$LOG"
  record_package_failure "neovim"
  exit 0
fi

# ------------------------------------------------------------ the LazyVim config
NVIM_CFG="$HOME/.config/nvim"

# An existing config is never merged over. If it is already LazyVim, leave it
# completely alone - re-running the installer must not throw away the plugin
# lockfile or anything under lua/plugins. Anything else gets backed up, the same
# timestamped way copy.sh backs up a config directory.
if [ -d "$NVIM_CFG" ] && [ -f "$NVIM_CFG/lua/config/lazy.lua" ]; then
  echo "${OK} LazyVim is already installed at $NVIM_CFG - left untouched." | tee -a "$LOG"
elif [ -e "$NVIM_CFG" ]; then
  backup="$NVIM_CFG.backup-$(date +%Y%m%d-%H%M%S)"
  _n=1
  while [ -e "$backup" ]; do backup="$NVIM_CFG.backup-$(date +%Y%m%d-%H%M%S)-$_n"; _n=$((_n + 1)); done
  if mv -T "$NVIM_CFG" "$backup"; then
    echo "${NOTE} Backed up existing nvim config to $(basename "$backup")" | tee -a "$LOG"
  else
    echo "${ERROR} Could not back up $NVIM_CFG - leaving it alone." | tee -a "$LOG"
    record_package_failure "lazyvim"
    exit 0
  fi
fi

if [ ! -d "$NVIM_CFG" ]; then
  printf "\n%s - Cloning the ${SKY_BLUE}LazyVim${RESET} starter .... \n" "${NOTE}"
  if git clone --depth 1 https://github.com/LazyVim/starter "$NVIM_CFG" >>"$LOG" 2>&1; then
    # The starter is a template, not a repo you track. Upstream says to drop its
    # history so your own config can become a repo of its own if you want one.
    rm -rf "$NVIM_CFG/.git"
    echo "${OK} LazyVim starter installed to $NVIM_CFG" | tee -a "$LOG"
  else
    echo "${ERROR} Could not clone the LazyVim starter - see $LOG" | tee -a "$LOG"
    record_package_failure "lazyvim"
    exit 0
  fi
fi

# ------------------------------------------------------------------- the theme
# The PyCharm-matched colorscheme, so a fresh machine looks like this one rather
# than like LazyVim's default tokyonight. Colours are JetBrains' new-UI "Dark",
# read out of app.jar!/themes/expUI/expUI_darkScheme.xml, and foot and herdr are
# configured from the same values - see Hyprland-Dots/config/{foot,herdr}.
#
# Two files, treated differently on purpose:
#
#   colors/pycharm-dark.lua      ours, overwritten every run. It is a palette
#                                asset like assets/ly/*.dur, not something you
#                                are expected to hand-edit.
#   lua/plugins/colorscheme.lua  written ONLY if absent. This directory is
#                                yours (see the header), so the installer may
#                                seed it on a fresh machine but must never
#                                overwrite a choice you made later - switch
#                                colorscheme in that file and a re-run keeps it.
if [ -d "$NVIM_CFG" ]; then
  mkdir -p "$NVIM_CFG/colors" "$NVIM_CFG/lua/plugins"
  if cp "$PARENT_DIR/assets/nvim/pycharm-dark.lua" "$NVIM_CFG/colors/pycharm-dark.lua"; then
    echo "${OK} Installed the pycharm-dark colorscheme." | tee -a "$LOG"
  else
    echo "${WARN} Could not install colors/pycharm-dark.lua - see $LOG" | tee -a "$LOG"
  fi

  if [ -e "$NVIM_CFG/lua/plugins/colorscheme.lua" ]; then
    echo "${NOTE} lua/plugins/colorscheme.lua already exists - left as yours." | tee -a "$LOG"
  elif cp "$PARENT_DIR/assets/nvim/colorscheme.lua" "$NVIM_CFG/lua/plugins/colorscheme.lua"; then
    echo "${OK} Set pycharm-dark as the LazyVim colorscheme." | tee -a "$LOG"
  else
    echo "${WARN} Could not write lua/plugins/colorscheme.lua - see $LOG" | tee -a "$LOG"
  fi
fi

# --------------------------------------------------------- pre-fetch the plugins
# lazy.nvim installs on first launch either way; doing it here means the first
# interactive nvim is instant instead of a progress bar. Non-fatal: a machine that
# is offline at this point still ends up with a working config, it just does the
# download the first time you open it.
#
# Treesitter parsers are NOT pre-fetched. On the `main` branch they are installed
# lazily, per language, the first time you open a matching file, and a headless
# run has no buffer to trigger that. `tree-sitter-cli` above is the part that has
# to be in place ahead of time; the parsers arrive on their own.
if [ -d "$NVIM_CFG" ]; then
  printf "\n%s - Pre-fetching ${SKY_BLUE}LazyVim${RESET} plugins (first launch is slow otherwise) .... \n" "${NOTE}"
  if timeout 600 nvim --headless "+Lazy! sync" +qa >>"$LOG" 2>&1; then
    echo "${OK} LazyVim plugins installed." | tee -a "$LOG"
  else
    echo "${WARN} Plugin pre-fetch did not finish - nvim will do it on first launch." | tee -a "$LOG"
  fi
fi

printf "\n${NOTE} ${SKY_BLUE}Neovim + LazyVim${RESET} installed. ${YELLOW}Space E${RESET} toggles the file tree, ${YELLOW}Ctrl+W W${RESET} hops between tree and editor, ${YELLOW}Space Space${RESET} finds a file, ${YELLOW}Space S G${RESET} greps with preview, ${YELLOW}Space G G${RESET} opens lazygit. Double-click works in the tree. Colours match PyCharm and your terminal (${MAGENTA}pycharm-dark${RESET}). Your own plugins go in ${SKY_BLUE}~/.config/nvim/lua/plugins/${RESET}, which this repo seeds once and then leaves alone.\n"
printf "\n%.0s" {1..2}
