# Host setup

How to prepare a machine to build and run slurm-cluster-lab. Everything here
lives outside the repo, which is why a fresh clone on an unprepared VM fails
in confusing ways.

Most of it is automated by [`setup-host.sh`](../setup-host.sh). This page
explains what the script does and covers the parts it can't, like sizing the
VM.

---

## Tested hosts

| Host | Guest OS | Architecture | Full build |
|------|----------|--------------|-----------|
| Intel iMac, VirtualBox | Ubuntu 22.04 | x86_64 | 45–90 min |
| Apple M3, Parallels | Ubuntu 26.04.1 LTS | arm64 | ~20 min |

Other hypervisors, cloud instances and bare metal should work the same way.
The requirements are Ubuntu (or similar), Docker CE, cgroup v2, and the kernel
settings below.

---

## 1. Size the VM

| Resource | Minimum | Recommended | Why |
|----------|---------|-------------|-----|
| CPUs | 4 | 8 | ~28 components compile from source |
| RAM | 16 GB | 32 GB | 26 containers, three of them JVMs |
| Disk | 100 GB | 150–200 GB | images ~40 GB plus build cache |
| Swap | 4 GB | 8 GB | absorbs compile peaks |

Disk is the one people underestimate. A single build peaks around 90 GB with
cache, and a rebuild alongside the old images can pass 120 GB.

### Apple Silicon (Parallels)

- Use **Ubuntu Server ARM64**, the **standard** image, not the "64k page
  size" variant. Apple Silicon doesn't support 64 KB pages, and qemu
  emulation (needed for Kibana) assumes 4 KB. Check with `getconf PAGESIZE`,
  which should print `4096`.
- Prefer the LTS release (26.04.x) over interim releases.

### Intel (VirtualBox, VMware, etc.)

- Use **Ubuntu Server** amd64, 22.04 or later.
- VirtualBox's default disk is small. Set the size when creating the VM, or
  grow it later (below).

### Growing the disk afterwards

Enlarge the virtual disk in the hypervisor, then inside the VM:

```bash
lsblk                 # find the root partition, e.g. sda2
df -T /               # filesystem type
sudo apt install -y cloud-guest-utils
sudo growpart /dev/sda 2
sudo resize2fs /dev/sda2          # ext4
# sudo xfs_growfs /               # xfs instead
# LVM: sudo lvextend -r -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv
df -h /
```

`growpart` only works when the root partition is the last one on the disk.

---

## 2. Run the setup script

```bash
git clone https://github.com/marabgol/slurm-cluster-lab.git
cd slurm-cluster-lab
./setup-host.sh --check      # report what's missing, change nothing
./setup-host.sh              # install and configure
```

Log out and back in afterwards if it added you to the `docker` group.

What it does, and why each step matters:

### Docker CE

Installed from Docker's own repository, not Ubuntu's `docker.io` package, so
you get current versions with the Compose v2 and buildx plugins. It also adds
a `docker-compose` shim for scripts that still call the hyphenated name.

Check:

```bash
docker info | grep -E "Architecture|Cgroup"
```

You want `Cgroup Driver: systemd` and `Cgroup Version: 2`.

### cgroup v2

The containers run systemd 252 as PID 1, built for the unified hierarchy.
Ubuntu 22.04 and later use cgroup v2 by default, so normally there's nothing
to do. If the host was forced to v1, for example for an older AlmaLinux 8
build, undo it:

```bash
sudo sed -i 's/ systemd.unified_cgroup_hierarchy=0//' /etc/default/grub
sudo update-grub && sudo reboot
```

### Kernel settings

Written to `/etc/sysctl.d/99-slurm-cluster-lab.conf`, so they survive reboots:

| Setting | Value | Without it |
|---------|-------|-----------|
| `vm.max_map_count` | 262144 | Elasticsearch refuses to start |
| `fs.inotify.max_user_instances` | 8192 | some nodes stay `unk*` or exit |
| `fs.inotify.max_user_watches` | 524288 | same |

The inotify limit is the one that's easy to miss. Each of the 16 containers
running systemd needs several inotify instances, and Ubuntu's default allows
128 per user. The containers that start last fail with:

```
Failed to create control group inotify object: Too many open files
Failed to allocate manager object: Too many open files
```

Despite the wording, it has nothing to do with file descriptors.

### amd64 emulation (arm64 only)

`kibana-oss:7.10.1` was never published for arm64. The OSS edition ended at
7.10, before Elastic added arm64 builds. The compose file pins it to
`linux/amd64`, which needs a qemu handler on the host:

| Ubuntu | Package |
|--------|---------|
| 26.04 | `qemu-user-binfmt` |
| 22.04 / 24.04 | `qemu-user-static binfmt-support` |

Check:

```bash
docker run --rm --platform linux/amd64 alpine uname -m     # x86_64
```

Everything else in the stack runs natively on arm64.

### git mirrors (optional)

Two submodules, valgrind and binutils-gdb, come from sourceware.org, which
rate-limits large clones with HTTP 429. If the clone stalls on those, run:

```bash
./setup-host.sh --git-mirrors
```

This adds `insteadOf` rules pointing at GitHub mirrors that carry the same
pinned commits.

---

## 3. Clone and build

```bash
git clone --recurse-submodules --shallow-submodules \
  https://github.com/marabgol/slurm-cluster-lab.git
cd slurm-cluster-lab
git submodule status | grep -v "^ "      # any output: a submodule didn't populate
make
```

If the status check prints anything, a submodule clone failed partway, usually
a network reset on a large one. Fill it in:

```bash
git submodule update --init --recursive
```

`--shallow-submodules` fetches only the pinned commits rather than full
histories, which turns gigabytes of download into a few hundred megabytes.

---

## 4. Verify

```bash
docker compose ps -a --format "{{.Name}}\t{{.Status}}" | grep -v "Up "   # expect nothing
docker compose exec login timeout 15 sinfo                              # 10 nodes idle
docker compose exec login su - fred -c "srun -N10 uname -m | sort | uniq -c"
docker compose exec node00 journalctl -u slurmd --no-pager | grep "cgroup/v"
```

Expected: no stopped containers, `debug` partition with 10 `idle` nodes, ten
lines of your architecture, and `cgroup/v2: init: Cgroup v2 plugin loaded`.

If `sinfo` hangs on first start, MySQL was still initialising its fresh volume
when slurmdbd came up. Restart in dependency order:

```bash
docker compose exec slurmdbd systemctl restart slurmdbd
sleep 10
docker compose exec mgmtnode systemctl restart slurmctld
```
