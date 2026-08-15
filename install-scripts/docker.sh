#!/bin/bash
# Docker - installed with SOCKET ACTIVATION instead of boot autostart.
# Rationale: the Docker daemon + idle containers cost ~350MB of RAM at every
# boot. This machine only needs Docker occasionally, so instead of enabling
# docker.service (starts dockerd at boot) we enable docker.socket. The daemon
# then starts on-demand the first time any `docker` command touches the socket,
# and costs 0MB until then. Stop it with `sudo systemctl stop docker` when done.

docker_pkg=(
  docker
  docker-compose
)

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "${ERROR} Failed to change directory to $PARENT_DIR"; exit 1; }

# Source the global functions script
if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%d-%H%M%S)_docker.log"

# Install packages
printf "\n%s - Installing ${SKY_BLUE}Docker${RESET} packages .... \n" "${NOTE}"
for PKG in "${docker_pkg[@]}"; do
  install_package "$PKG" "$LOG"
done

# Add the current user to the docker group (so `docker` works without sudo)
printf "\n${NOTE} Adding ${SKY_BLUE}$USER${RESET} to the docker group...\n" | tee -a "$LOG"
sudo usermod -aG docker "$USER" 2>&1 | tee -a "$LOG"
echo "${INFO} Log out/in (or reboot) for docker group membership to take effect." | tee -a "$LOG"

# Socket activation: daemon starts on-demand, NOT at boot (saves ~350MB idle RAM).
# Make sure the boot-autostart service is OFF and the socket is ON.
printf "\n${NOTE} Configuring ${SKY_BLUE}Docker socket activation${RESET} (on-demand, no boot autostart)...\n" | tee -a "$LOG"
sudo systemctl disable docker.service 2>&1 | tee -a "$LOG"
sudo systemctl enable docker.socket 2>&1 | tee -a "$LOG"

if [ "$(systemctl is-enabled docker.socket 2>/dev/null)" = "enabled" ] && \
   [ "$(systemctl is-enabled docker.service 2>/dev/null)" != "enabled" ]; then
  echo "${OK} Docker set to socket-activation. Daemon starts on first \`docker\` command." | tee -a "$LOG"
else
  echo "${WARN} Docker socket-activation state unexpected — check: systemctl is-enabled docker.service docker.socket" | tee -a "$LOG"
fi

printf "\n${NOTE} ${SKY_BLUE}Docker${RESET} installed with ${YELLOW}socket activation${RESET}: it does not run at boot. Any \`docker\` command auto-starts the daemon; stop it with ${MAGENTA}sudo systemctl stop docker${RESET} to reclaim RAM. Containers with a restart policy will relaunch when the daemon activates.\n"
printf "\n%.0s" {1..2}
