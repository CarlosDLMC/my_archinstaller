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
if [ -f '/home/mentefria/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '/home/mentefria/Downloads/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/home/mentefria/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '/home/mentefria/Downloads/google-cloud-sdk/completion.zsh.inc'; fi

# Ruby gems
export PATH="$HOME/.local/share/gem/ruby/3.4.0/bin:$PATH"

# Homebrew
[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"

[ -r "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
[ -r "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
