#!/bin/sh
# The Changes popup: nvim with this plugin's own config. NVIM_APPNAME keeps its
# state apart from the normal nvim setup; -i NONE skips shada.
here=$(dirname "$0")
[ -n "$HERDR_PLUGIN_ROOT" ] && here="$HERDR_PLUGIN_ROOT"
export GIT_CHANGES_ROOT="${GIT_CHANGES_ROOT:-$PWD}"
exec env NVIM_APPNAME=herdr-git-changes nvim -i NONE -u "$here/nvim/init.lua"
