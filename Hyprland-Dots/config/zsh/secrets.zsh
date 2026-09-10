# ═══════════════════════════════════════════════════════════════════════════
#  secrets.zsh - machine-local credentials
# ═══════════════════════════════════════════════════════════════════════════
#
#  ⚠  THIS COPY IS TRACKED IN GIT AND THE REPO IS PUBLIC.
#     Every value below is FAKE and must stay fake. Never put a real key in
#     this file - git history is permanent, and deleting a secret in a later
#     commit does not remove it from the history that is already pushed.
#
#     Your real keys go in the deployed copy, ~/.config/zsh/secrets.zsh,
#     which lives outside the repo and is never committed.
#
# ───────────────────────────────────────────────────────────────────────────
#  How this works
# ───────────────────────────────────────────────────────────────────────────
#
#  1. copy.sh deploys this file to ~/.config/zsh/secrets.zsh at mode 600,
#     but ONLY if you do not already have one. A re-run of the installer
#     never overwrites it, so the keys you fill in survive a re-install.
#
#  2. .zshrc sources it, guarded:
#
#         [ -r "$HOME/.config/zsh/secrets.zsh" ] && . "$HOME/.config/zsh/secrets.zsh"
#
#     The guard is the point: a shell on a machine without this file still
#     starts normally. It just will not have the keys, so only the tools that
#     actually need one will fail.
#
#  3. On a new machine, open ~/.config/zsh/secrets.zsh and replace the fake
#     values below with the real ones from your password manager. Nothing in
#     this repo can restore them for you - that is the whole point.
#
#         ${EDITOR:-nano} ~/.config/zsh/secrets.zsh
#
#  Keep the mode at 600 (owner read/write only):
#
#         chmod 600 ~/.config/zsh/secrets.zsh
#
#  One export per line keeps the file greppable. Adding a key here does not
#  affect a shell that is already open - either `source` the file again or
#  open a new terminal.
#
# ───────────────────────────────────────────────────────────────────────────

# ── Anthropic ──────────────────────────────────────────────────────────────
# Needed only for DIRECT API use: SDK scripts, curl, anything calling the
# Messages API yourself.
#
# Claude Code does NOT read this. It authenticates by OAuth and keeps its own
# token in ~/.claude/.credentials.json, so leaving this fake breaks nothing in
# Claude Code itself.
export ANTHROPIC_API_KEY="sk-ant-1234"

# ── Cloudflare ─────────────────────────────────────────────────────────────
# The email pairs with the global API key; both are needed together.
export CLOUDFLARE_EMAIL="you@example.com"
export CLOUDFLARE_API_KEY="cf-1234"

# ── Bitbucket ──────────────────────────────────────────────────────────────
# App password / access token, used for git over HTTPS and the API.
export BITBUCKET_TOKEN="bb-1234"

# ── Add your own below ─────────────────────────────────────────────────────
# Examples of the shape, all commented out:
#
# export GITHUB_TOKEN="ghp-1234"
# export OPENAI_API_KEY="sk-1234"
# export AWS_ACCESS_KEY_ID="AKIA1234"
# export AWS_SECRET_ACCESS_KEY="secret-1234"
