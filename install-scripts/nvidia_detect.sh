#!/bin/bash
# Which NVIDIA driver branch can drive this machine's GPU(s)?
#
# Prints exactly one word:
#   none         no NVIDIA display controller
#   open         Turing (GTX 16xx / RTX 20xx) or newer - nvidia-open-dkms
#   580xx        Maxwell, Pascal or Volta - the legacy nvidia-580xx branch (AUR)
#   unsupported  Kepler or older - no maintained driver; keep nouveau
#
# With several NVIDIA GPUs the OLDEST one decides, since one driver has to
# drive all of them.
#
# Why this exists: install.sh used to answer "NVIDIA?" with `lspci | grep -i
# nvidia` and then always install nvidia-open-dkms. The open modules only bind
# to Turing and newer, so a GTX 1060 got a driver that never loaded, nouveau
# blacklisted on top, and a reboot into no GPU driver at all.
#
# Read-only and dependency-free (lspci only), so install.sh can run it during
# hardware detection, before anything is installed.
#
# The generation is read from the PCI device ID, which NVIDIA assigns in
# ascending blocks per architecture:
#   < 0x1340        Kepler, Fermi and older   (GK208 tops out at 0x12ba)
#   0x1340-0x1dff   Maxwell (GM108 0x1340..), Pascal, Volta (GV100 0x1dbx)
#   >= 0x1e00       Turing (TU102 0x1e02..) and everything after it
#
# Display controllers only (PCI class 0300 VGA, 0302 3D, 0380 other display):
# the HDMI audio function and old nForce chipsets also say "NVIDIA" and used
# to count as a GPU.

tier_rank() { case "$1" in unsupported) echo 0 ;; 580xx) echo 1 ;; open) echo 2 ;; esac; }

result="none"
while read -r _id; do
    [ -n "$_id" ] || continue
    _dec=$((16#$_id))
    if [ "$_dec" -ge $((16#1e00)) ]; then
        _tier="open"
    elif [ "$_dec" -ge $((16#1340)) ]; then
        _tier="580xx"
    else
        _tier="unsupported"
    fi
    if [ "$result" = "none" ] || [ "$(tier_rank "$_tier")" -lt "$(tier_rank "$result")" ]; then
        result="$_tier"
    fi
done < <(for _class in 0300 0302 0380; do
             lspci -n -d "10de::$_class" 2>/dev/null
         done | awk '{ split($3, a, ":"); print a[2] }')

echo "$result"
