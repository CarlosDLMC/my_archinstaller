# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="agnoster_modificado"

plugins=(
    git
    archlinux
    zsh-autosuggestions
    zsh-syntax-highlighting
)

[ -r "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"

# Check archlinux plugin commands here
# https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/archlinux

# Display Pokemon-colorscripts
# Project page: https://gitlab.com/phoneybadger/pokemon-colorscripts#on-other-distros-and-macos
#pokemon-colorscripts --no-title -s -r #without fastfetch
#pokemon-colorscripts --no-title -s -r | fastfetch -c $HOME/.config/fastfetch/config-pokemon.jsonc --logo-type file-raw --logo-height 10 --logo-width 5 --logo -
[ -x "$HOME/pokefetch_perfect" ] && ~/pokefetch_perfect

# Every external-tool hook below is guarded: this file is deployed verbatim
# onto fresh machines by the installer, where fnm/brew/cargo/uv are absent
# and an unguarded eval or source errors on every shell start.

# Machine-local credentials live outside the dotfiles repo, in
# ~/.config/zsh/secrets.zsh (chmod 600). Create it on a new machine with the
# exports this shell needs, e.g. ANTHROPIC_API_KEY, CLOUDFLARE_API_KEY,
# BITBUCKET_TOKEN. Absent, the shell just starts without them.
[ -r "$HOME/.config/zsh/secrets.zsh" ] && . "$HOME/.config/zsh/secrets.zsh"

# fastfetch. Will be disabled if above colorscript was chosen to install
#fastfetch -c $HOME/.config/fastfetch/config-compact.jsonc

# Set-up icons for files/directories in terminal using lsd
alias ls='lsd'
alias l='ls -l'
alias la='ls -a'
alias lla='ls -la'
alias lt='ls --tree'

# Set-up FZF key bindings (CTRL R for fuzzy history finder)
command -v fzf >/dev/null && source <(fzf --zsh)

HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory
command -v fnm >/dev/null && eval "$(fnm env --use-on-cd)"

# The next line updates PATH for the Google Cloud SDK.
if [ -f "$HOME/Downloads/google-cloud-sdk/path.zsh.inc" ]; then . "$HOME/Downloads/google-cloud-sdk/path.zsh.inc"; fi

# The next line enables shell command completion for gcloud.
if [ -f "$HOME/Downloads/google-cloud-sdk/completion.zsh.inc" ]; then . "$HOME/Downloads/google-cloud-sdk/completion.zsh.inc"; fi

# Ruby gems
export PATH="$HOME/.local/share/gem/ruby/3.4.0/bin:$PATH"

# Homebrew
[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"

# ~/.local/bin is where this repo installs the herdr binary and every helper
# script copy.sh ships (herdr-*, flag-switch, pokefetch-merge), and nothing else
# puts it on PATH: systemd's user environment does not carry it, and the
# ~/.local/bin/env line below is uv's shim, which only exists if you installed
# uv. On a fresh machine that left `herdr` on disk but not on PATH. The helper
# scripts are always called by absolute path, so this only ever showed up as
# "herdr: command not found". The guard keeps a re-sourced .zshrc from stacking
# duplicate entries.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

[ -r "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
[ -r "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# One shared cargo build cache across every checkout, including the git
# worktrees herdr creates under ~/.herdr/worktrees. Without this each worktree
# grows its own target/ - ~20GB apiece on a large Rust repo, which fills a
# 225GB disk after three branches.
export CARGO_TARGET_DIR="$HOME/.cache/cargo-target"
