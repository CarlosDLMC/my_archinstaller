#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '
[ -r "$HOME/.config/byobu/prompt" ] && . "$HOME/.config/byobu/prompt"   #byobu-prompt#
# Guarded: rustup and uv are per-machine tooling the installer does not ship.
[ -r "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
[ -r "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
