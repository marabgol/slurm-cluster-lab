#!/usr/bin/env bash
# Prepare an Ubuntu host to build and run slurm-cluster-lab.
# Tested on Ubuntu 22.04 (x86_64) and Ubuntu 26.04 (arm64).
#
#   ./setup-host.sh                 # install and configure
#   ./setup-host.sh --git-mirrors   # also add git mirror rules for sourceware.org
#   ./setup-host.sh --check         # report only, change nothing
#
# Safe to re-run: every step checks before it changes anything.
set -euo pipefail

CHECK_ONLY=0
GIT_MIRRORS=0
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    --git-mirrors) GIT_MIRRORS=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$*"; }
fail() { printf '  \033[31mfail\033[0m  %s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
run()  { if [ "$CHECK_ONLY" = 1 ]; then echo "  would run: $*"; else "$@"; fi; }

[ "$(id -u)" = 0 ] && { echo "Run as your normal user; the script uses sudo where needed." >&2; exit 1; }
. /etc/os-release
ARCH=$(uname -m)

step "Host"
[ "$ID" = ubuntu ] && ok "$PRETTY_NAME" || warn "$PRETTY_NAME is untested (Ubuntu 22.04/26.04 are tested)"
ok "architecture $ARCH"
cpus=$(nproc); mem_gb=$(awk '/MemTotal/{printf "%d", $2/1048576}' /proc/meminfo)
disk_gb=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
[ "$cpus" -ge 8 ]    && ok "$cpus CPUs"           || warn "$cpus CPUs (8 recommended; build will be slow)"
[ "$mem_gb" -ge 16 ] && ok "${mem_gb} GB RAM"     || warn "${mem_gb} GB RAM (16 GB minimum, 32 GB comfortable)"
[ "$disk_gb" -ge 100 ] && ok "${disk_gb} GB free on /" || warn "${disk_gb} GB free on / (100 GB+ recommended; see docs/host-setup.md to grow the disk)"
if [ "$ARCH" = aarch64 ]; then
  [ "$(getconf PAGESIZE)" = 4096 ] && ok "4K page size" || fail "page size $(getconf PAGESIZE): use the standard (4K) Ubuntu image, not 64k"
fi
[ -f /sys/fs/cgroup/cgroup.controllers ] && ok "cgroup v2" \
  || fail "cgroup v1 detected: remove systemd.unified_cgroup_hierarchy=0 from GRUB and reboot"

step "Docker"
if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
  ok "$(docker --version)"
else
  echo "  installing Docker CE from download.docker.com"
  run sudo apt-get update -q
  run sudo apt-get install -y -q ca-certificates curl git
  run sudo install -m 0755 -d /etc/apt/keyrings
  run sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  run sudo chmod a+r /etc/apt/keyrings/docker.asc
  if [ "$CHECK_ONLY" = 0 ]; then
    sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<SRC
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
SRC
  fi
  run sudo apt-get update -q
  run sudo apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
if id -nG "$USER" | grep -qw docker; then
  ok "$USER is in the docker group"
else
  run sudo usermod -aG docker "$USER"
  warn "added $USER to the docker group: log out and back in before building"
fi
if [ -x /usr/local/bin/docker-compose ]; then
  ok "docker-compose shim present"
elif [ "$CHECK_ONLY" = 0 ]; then
  printf '#!/bin/sh\nexec docker compose "$@"\n' | sudo tee /usr/local/bin/docker-compose >/dev/null
  sudo chmod +x /usr/local/bin/docker-compose
  ok "installed docker-compose shim"
else
  echo "  would install /usr/local/bin/docker-compose shim"
fi

step "Kernel settings"
# vm.max_map_count: Elasticsearch refuses to start below 262144.
# inotify: each of the 16 systemd containers needs several inotify instances.
#   Ubuntu's default of 128 per user runs out, and the containers that start
#   last fail with "Failed to create control group inotify object: Too many open files".
SYSCTL_FILE=/etc/sysctl.d/99-slurm-cluster-lab.conf
if [ "$CHECK_ONLY" = 0 ]; then
  sudo tee "$SYSCTL_FILE" >/dev/null <<SYS
vm.max_map_count=262144
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=524288
SYS
  sudo sysctl -q --system
fi
for k in vm.max_map_count fs.inotify.max_user_instances fs.inotify.max_user_watches; do
  ok "$k = $(sysctl -n $k)"
done

if [ "$ARCH" = aarch64 ]; then
  step "amd64 emulation (Kibana has no arm64 image)"
  if [ -e /proc/sys/fs/binfmt_misc/qemu-x86_64 ]; then
    ok "qemu-x86_64 binfmt handler registered"
  else
    # Ubuntu 26.04 renamed qemu-user-static; try the new name first.
    if apt-cache show qemu-user-binfmt >/dev/null 2>&1; then
      run sudo apt-get install -y -q qemu-user-binfmt
    else
      run sudo apt-get install -y -q qemu-user-static binfmt-support
    fi
    [ -e /proc/sys/fs/binfmt_misc/qemu-x86_64 ] && ok "qemu-x86_64 registered" \
      || warn "qemu-x86_64 not registered yet; check with: docker run --rm --platform linux/amd64 alpine uname -m"
  fi
fi

if [ "$GIT_MIRRORS" = 1 ]; then
  step "git mirrors for sourceware.org"
  # sourceware.org rate-limits large clones (HTTP 429). These GitHub mirrors
  # carry the commits the submodules are pinned to.
  run git config --global url."https://github.com/RTEMS/sourceware-mirror-binutils-gdb.git".insteadOf \
    "https://sourceware.org/git/binutils-gdb.git"
  run git config --global url."https://github.com/sailfishos-mirror/valgrind.git".insteadOf \
    "https://sourceware.org/git/valgrind.git"
  git config --global --get-regexp insteadof | sed 's/^/  /' || true
fi

step "Done"
echo "  Next: git clone --recurse-submodules --shallow-submodules <repo>; cd into it; make"
