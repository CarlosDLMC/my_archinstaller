#
# ~/.bash_profile
#

[[ -f ~/.bashrc ]] && . ~/.bashrc

# Guarded: rustup and uv are per-machine tooling the installer does not ship,
# so on a fresh machine neither file exists and an unguarded source printed two
# errors on every bash login.
[ -r "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
[ -r "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
