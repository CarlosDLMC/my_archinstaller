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

  # tree-sitter-cli comes from the repos rather than from mason.nvim on purpose.
  # nvim-treesitter's `main` branch needs the CLI on PATH to build any parser, and
  # when it is missing LazyVim fetches it through mason - asynchronously, inside
  # the headless pre-fetch below. On the machine this was tested on, the
  # pre-fetch quit while that was still running and left a hard
  #   Unmet requirements for nvim-treesitter `main`: ❌ tree-sitter (CLI)
  # with no parsers and no syntax highlighting. From pacman it is simply there
  # before nvim starts.
  #
  # stylua and shfmt do NOT save mason any work, although that was the idea.
  # LazyVim decides whether to install them by asking mason's own registry
  # (p:is_installed()), not PATH, so mason downloads its own copies into
  # ~/.local/share/nvim/mason regardless - and those, not these, are what nvim
  # runs, because mason puts its bin dir first on nvim's PATH. The 09-18 log
  # showed "Installation was aborted. - shfmt - stylua" with both packages
  # installed. The pacman copies are still handy from a shell; the pre-fetch
  # below is what makes sure mason's copies actually finish.
  tree-sitter-cli # nvim-treesitter's `main` branch requires the CLI to build parsers
  stylua          # Lua formatter LazyVim configures out of the box
  shfmt           # shell formatter, same
)

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

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

# ------------------------------------------------------------- rust-analyzer
# The LazyVim Rust extra (seeded in lazyvim.json below) runs rust-analyzer through
# rustaceanvim, which looks it up on PATH. It is what tells a trait from a struct,
# underlines `let mut` bindings and marks unsafe calls - the RustRover colours in
# pycharm-dark.lua need it; treesitter alone cannot tell those apart.
#
# With rustup, ~/.cargo/bin/rust-analyzer exists before the component does - it is
# a proxy that only prints
#   error: Unknown binary 'rust-analyzer' in official toolchain
# and ~/.cargo/bin sits ahead of /usr/bin on PATH, so a pacman copy would be
# shadowed by it. Hence: the rustup component when rustup is here, the Arch
# package otherwise.
RUSTUP="$(command -v rustup || true)"
[ -z "$RUSTUP" ] && [ -x "$HOME/.cargo/bin/rustup" ] && RUSTUP="$HOME/.cargo/bin/rustup"
if [ -n "$RUSTUP" ]; then
  if "$RUSTUP" component add rust-analyzer >>"$LOG" 2>&1; then
    echo "${OK} Installed rust-analyzer as a rustup component." | tee -a "$LOG"
  else
    echo "${WARN} rustup could not add rust-analyzer - see $LOG" | tee -a "$LOG"
  fi
else
  install_package rust-analyzer "$LOG"
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
#
# after/queries/python/highlights.scm goes with the palette and is overwritten the
# same way: it adds the treesitter captures the Python section needs (keyword
# arguments and __dunder__ names), which nvim-treesitter's own query lumps in with
# other nodes.
if [ -d "$NVIM_CFG" ]; then
  mkdir -p "$NVIM_CFG/colors" "$NVIM_CFG/lua/plugins" "$NVIM_CFG/after/queries/python"
  if cp "$PARENT_DIR/assets/nvim/pycharm-dark.lua" "$NVIM_CFG/colors/pycharm-dark.lua"; then
    echo "${OK} Installed the pycharm-dark colorscheme." | tee -a "$LOG"
  else
    echo "${WARN} Could not install colors/pycharm-dark.lua - see $LOG" | tee -a "$LOG"
  fi
  if ! cp "$PARENT_DIR/assets/nvim/python-highlights.scm" "$NVIM_CFG/after/queries/python/highlights.scm"; then
    echo "${WARN} Could not install after/queries/python/highlights.scm - see $LOG" | tee -a "$LOG"
  fi

  if [ -e "$NVIM_CFG/lua/plugins/colorscheme.lua" ]; then
    echo "${NOTE} lua/plugins/colorscheme.lua already exists - left as yours." | tee -a "$LOG"
  elif cp "$PARENT_DIR/assets/nvim/colorscheme.lua" "$NVIM_CFG/lua/plugins/colorscheme.lua"; then
    echo "${OK} Set pycharm-dark as the LazyVim colorscheme." | tee -a "$LOG"
  else
    echo "${WARN} Could not write lua/plugins/colorscheme.lua - see $LOG" | tee -a "$LOG"
  fi
fi

# ------------------------------------------------------------- LazyVim extras
# lazyvim.json is where :LazyExtras records what you turned on. The starter ships
# without one and LazyVim writes it on first launch, so on a fresh machine it is
# absent here and gets seeded with lang.rust (rustaceanvim, crates.nvim, the
# rust/ron treesitter parsers, and codelldb through mason). Same rule as
# colorscheme.lua: written only if absent, so extras you toggled later survive a
# re-run. It carries install_version 8 because LazyVim treats a lazyvim.json
# without one as a pre-v8 install and switches on legacy defaults.
#
# This runs before the pre-fetch below so rustaceanvim, codelldb and the Rust
# parsers are downloaded with the rest.
if [ -d "$NVIM_CFG" ]; then
  if [ -e "$NVIM_CFG/lazyvim.json" ]; then
    echo "${NOTE} lazyvim.json already exists - extras left as yours." | tee -a "$LOG"
  elif cp "$PARENT_DIR/assets/nvim/lazyvim.json" "$NVIM_CFG/lazyvim.json"; then
    echo "${OK} Enabled the LazyVim Rust extra." | tee -a "$LOG"
  else
    echo "${WARN} Could not write lazyvim.json - see $LOG" | tee -a "$LOG"
  fi
fi

# --------------------------------------------------------- pre-fetch the plugins
# lazy.nvim installs on first launch either way; doing it here means the first
# interactive nvim is instant instead of a progress bar. Non-fatal: a machine that
# is offline at this point still ends up with a working config, it just does the
# download the first time you open it.
#
# "+Lazy! install" is only the first half of that download. Its build steps load
# mason.nvim and nvim-treesitter, and LazyVim's config for those two then starts
# background installs: every tool in mason's ensure_installed (stylua, shfmt,
# and codelldb from lang.rust) and every parser in LazyVim's treesitter
# ensure_installed (bash, lua, toml, markdown, ... and rust/ron from lang.rust).
# Quitting the moment lazy was done killed all of that - the 09-18 log ends with
# mason's "Installation was aborted. - shfmt - stylua" and a dozen parsers still
# at "Downloading", followed by an [OK]. So the same nvim now goes on to run
# wait.lua (below), which blocks until those installs have finished and exits 3
# with a one-line summary if something did not make it.
#
# It has to be the same nvim, not a second one afterwards. nvim-treesitter copies
# a parser's .so first and links its queries last, and counts a language as
# installed from the .so alone - so a parser killed between the two looks
# installed to it and to LazyVim, nvim never redoes it on its own, and that
# language has no highlighting until :TSInstall!. (wait.lua also repairs any
# parser an older run of this script left in that state.)

# lazy.nvim itself is cloned here rather than by the starter. The starter's
# lua/config/lazy.lua bootstraps it with this same clone, but when that fails it
# prints "Press any key to exit..." and calls getchar() - which in --headless
# waits for a key that can never arrive, so the pre-fetch would sit there for
# the whole ten-minute timeout. The starter only checks that the directory
# exists, so with it already cloned it skips its bootstrap. If the clone fails
# here, the pre-fetch is skipped and your first interactive launch does the
# bootstrap, where the prompt can actually be answered.
LAZY_NVIM="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/lazy.nvim"
if [ -d "$NVIM_CFG" ] && [ ! -e "$LAZY_NVIM" ]; then
  printf "\n%s - Cloning ${SKY_BLUE}lazy.nvim${RESET} .... \n" "${NOTE}"
  if git clone --filter=blob:none --branch=stable https://github.com/folke/lazy.nvim.git "$LAZY_NVIM" >>"$LOG" 2>&1; then
    echo "${OK} lazy.nvim cloned to $LAZY_NVIM" | tee -a "$LOG"
  else
    echo "${WARN} Could not clone lazy.nvim - skipping the plugin pre-fetch; nvim will bootstrap it on first launch." | tee -a "$LOG"
  fi
fi

if [ -d "$NVIM_CFG" ] && [ -e "$LAZY_NVIM" ] && PREFETCH_TMP=$(mktemp -d); then
  cat >"$PREFETCH_TMP/wait.lua" <<'LUA'
-- Runs in the headless nvim right after "Lazy! install" and blocks until the
-- installs that started in the background are done. On success it returns and
-- the +qa after it exits 0; otherwise it writes a one-line summary to
-- $LAZYVIM_PREFETCH_DIR/report and exits 3.
local dir = vim.env.LAZYVIM_PREFETCH_DIR
local deadline = tonumber(vim.env.LAZYVIM_PREFETCH_DEADLINE) or (os.time() + 300)

local function ms_left()
  return math.max(0, deadline - os.time()) * 1000
end

-- A plugin's resolved opts, extras included - the same thing LazyVim.opts() gives.
local function opts(name)
  local plugin = require("lazy.core.config").plugins[name]
  return plugin and require("lazy.core.plugin").values(plugin, "opts", false) or {}
end

local function main()
  -- Requiring a module loads its plugin through lazy.nvim, and that runs
  -- LazyVim's config for it, which is what starts the installs. On a fresh
  -- machine the build steps of Lazy! install already did this; on a re-run
  -- nothing did, and this is what finishes whatever an earlier run left out.
  local has_mason, mr = pcall(require, "mason-registry")
  local tools = has_mason and (opts("mason.nvim").ensure_installed or {}) or {}
  -- LazyVim calls install() from its own refresh callback, and mason can run
  -- ours first - so the flag only flips on the next tick, after LazyVim's
  -- callback has run and its tools report is_installing().
  local refreshed = not has_mason
  if has_mason then
    mr.refresh(function()
      vim.schedule(function()
        refreshed = true
      end)
    end)
  end

  -- get_installed() is the `main` branch API. A checkout without it is the old
  -- `master` branch, left in ~/.local/share/nvim/lazy by whatever lazy.nvim
  -- config was there before the starter (kickstart.nvim, say): Lazy! install
  -- only clones plugins that are missing, so it never switches the branch, and
  -- LazyVim's config for it stops at "Please use `:Lazy` and update
  -- `nvim-treesitter`" without installing a single parser. That used to be
  -- skipped here and end in [OK]. It is only wrong when the spec asks for
  -- `main`, as LazyVim's does - an older LazyVim that still wanted `master` is
  -- left alone, since there is no `main` API to check it with.
  local ts_loaded, TS = pcall(require, "nvim-treesitter")
  local has_ts = ts_loaded and type(TS.get_installed) == "function"
  local ts_spec = require("lazy.core.config").plugins["nvim-treesitter"]
  local ts_stale = ts_loaded and not has_ts and ts_spec and ts_spec.branch == "main"
  local langs = {}
  if has_ts then
    -- Adds the query-only languages they depend on (ecma, jsx, dtd, ...).
    langs = require("nvim-treesitter.config").norm_languages(
      opts("nvim-treesitter").ensure_installed or {},
      { unsupported = true }
    )
  end

  local function mason_state()
    local busy, missing = false, {}
    for _, name in ipairs(tools) do
      local p = mr.has_package(name) and mr.get_package(name)
      busy = busy or (p and p:is_installing()) or false
      if not (p and p:is_installed()) then
        missing[#missing + 1] = name
      end
    end
    return busy, missing
  end

  -- A language is done when its parser .so is in place AND its queries are
  -- linked - the last step of an install. nvim-treesitter's own "installed" is
  -- satisfied by the .so alone, which is how a killed install used to pass.
  local function ts_missing()
    if not has_ts then
      return {}
    end
    local parsers = require("nvim-treesitter.parsers")
    local runtime = require("nvim-treesitter.install").get_package_path("runtime", "queries")
    local so, q, missing = {}, {}, {}
    for _, l in ipairs(TS.get_installed("parsers")) do
      so[l] = true
    end
    for _, l in ipairs(TS.get_installed("queries")) do
      q[l] = true
    end
    for _, lang in ipairs(langs) do
      local info = parsers[lang] and parsers[lang].install_info
      local has_queries = (info and info.queries) or vim.uv.fs_stat(runtime .. "/" .. lang)
      if (info and not so[lang]) or (has_queries and not q[lang]) then
        missing[#missing + 1] = lang
      end
    end
    return missing
  end

  -- mason can say when a tool is still installing; nvim-treesitter cannot. But
  -- every step of a parser install is a child process (curl, tar, tree-sitter
  -- build), so once nothing has run for 3 s, a parser that is still missing has
  -- failed - no need to sit out the deadline waiting for it.
  local pid, busy_at = vim.fn.getpid(), vim.uv.hrtime()
  local function quiet()
    if #vim.api.nvim_get_proc_children(pid) > 0 then
      busy_at = vim.uv.hrtime()
    end
    return vim.uv.hrtime() - busy_at > 3e9
  end

  local settled = vim.wait(ms_left(), function()
    local idle = quiet() -- sampled every time, so busy_at is never stale
    return refreshed and not mason_state() and (idle or #ts_missing() == 0)
  end, 250)

  -- A parser still missing now either failed, or is one an older run killed
  -- between its .so and its queries - which nothing else would ever redo. One
  -- forced reinstall covers both, and unlike LazyVim's it can be waited on.
  local ts_left = ts_missing()
  if settled and #ts_left > 0 then
    TS.install(ts_left, { force = true }):pwait(ms_left())
    ts_left = ts_missing()
  end

  local lost = {}
  for _, p in ipairs(require("lazy").plugins()) do
    if not p._.installed then
      lost[#lost + 1] = p.name
    end
  end

  local problems = {}
  local function add(what, list)
    if #list > 0 then
      problems[#problems + 1] = what .. ": " .. table.concat(list, ", ")
    end
  end
  add("plugins", lost)
  add("mason", select(2, mason_state()))
  add("treesitter", ts_left)
  if ts_stale then
    problems[#problems + 1] = "treesitter: nvim-treesitter is still on its old `master` branch, which"
      .. " LazyVim cannot use and a restart will not change - run :Lazy update"
  end
  return problems, settled
end

local ok, problems, settled = pcall(main)
if not ok then
  problems, settled = { "wait.lua failed: " .. tostring(problems) }, true
end
if #problems > 0 then
  local msg = (settled and "not installed - " or "still installing at the deadline - ")
    .. table.concat(problems, "; ")
  io.stdout:write("\n[LazyVim pre-fetch] " .. msg .. "\n")
  local f = dir and io.open(dir .. "/report", "w")
  if f then
    f:write(msg)
    f:close()
  end
  vim.cmd("cquit 3")
end
LUA

  printf "\n%s - Pre-fetching ${SKY_BLUE}LazyVim${RESET} plugins, mason tools and treesitter parsers (first launch is slow otherwise) .... \n" "${NOTE}"
  # timeout 600 stays the hard stop. wait.lua gives up 30 s before it, so it can
  # still say what was left unfinished instead of being killed mid-install.
  # `|| _rc=$?` because Global_functions.sh runs this script under set -e.
  _rc=0
  LAZYVIM_PREFETCH_DIR="$PREFETCH_TMP" LAZYVIM_PREFETCH_DEADLINE=$(( $(date +%s) + 570 )) \
    timeout 600 nvim --headless "+Lazy! install" "+lua dofile(vim.env.LAZYVIM_PREFETCH_DIR .. '/wait.lua')" +qa >>"$LOG" 2>&1 || _rc=$?
  case "$_rc" in
    0)   echo "${OK} LazyVim plugins, mason tools and treesitter parsers installed." | tee -a "$LOG" ;;
    3)   echo "${WARN} LazyVim pre-fetch: $(cat "$PREFETCH_TMP/report" 2>/dev/null). nvim retries missing ones on its next start - see $LOG" | tee -a "$LOG" ;;
    124) echo "${WARN} LazyVim pre-fetch hit the 10-minute timeout - nvim will finish it on first launch." | tee -a "$LOG" ;;
    *)   echo "${WARN} Plugin pre-fetch did not finish (nvim exited $_rc) - nvim will do it on first launch. See $LOG" | tee -a "$LOG" ;;
  esac
  rm -rf "$PREFETCH_TMP"
fi

printf "\n${NOTE} ${SKY_BLUE}Neovim + LazyVim${RESET} installed. ${YELLOW}Space E${RESET} toggles the file tree, ${YELLOW}Ctrl+W W${RESET} hops between tree and editor, ${YELLOW}Space Space${RESET} finds a file, ${YELLOW}Space S G${RESET} greps with preview, ${YELLOW}Space G G${RESET} opens lazygit. Double-click works in the tree. Colours match PyCharm and your terminal (${MAGENTA}pycharm-dark${RESET}), and Rust files match RustRover. Your own plugins go in ${SKY_BLUE}~/.config/nvim/lua/plugins/${RESET}, which this repo seeds once and then leaves alone.\n"
printf "\n%.0s" {1..2}
