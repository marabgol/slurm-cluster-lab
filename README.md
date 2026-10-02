# slurm-cluster-lab

A containerized multi-node Slurm cluster for learning and testing, running
**Slurm 26.05.3** on AlmaLinux 9 with cgroup v2, under Docker Compose.

Forked from [SchedMD/training/docker-scale-out](https://gitlab.com/SchedMD/training/docker-scale-out).
The original design is SchedMD's; this fork rebases it on AlmaLinux 9 so it
runs on cgroup v2 hosts, and carries assorted build fixes.

---

## What you get

A 23-container cluster that behaves like a real Slurm deployment:

| Component | Containers |
|-----------|-----------|
| Controllers | `mgmtnode` (primary), `mgmtnode2` (backup) |
| Accounting | `slurmdbd` + MySQL |
| Compute | `node00`–`node09` |
| Access | `login`, `rest` (slurmrestd), `proxy` (authenticating HTTP proxy) |
| Extras | Open OnDemand, Grafana, InfluxDB, Elasticsearch, Kibana, Keycloak |

```
$ sinfo
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
cloud        up   infinite   1025  idle~ cloud[0000-1024]
debug*       up   infinite     10   idle node[00-09]

$ sinfo --version
slurm 26.05.3
```

The `cloud` partition demonstrates Slurm's power-saving / cloud-bursting
feature — 1025 nodes defined but powered down (`idle~`), created on demand.

Real HA, real munge authentication, real cgroup job containment, a working
REST API, and a slurmdbd accounting chain. Good for learning Slurm
administration, testing configurations, or reproducing behaviour before
touching a production cluster.

---

## Requirements

- Runs on a VM, bare metal, or a cloud instance
- **Tested on x86_64.** arm64 is probably viable but untested — see
  [Architecture](#architecture) below
- **Docker CE** with the Compose v2 plugin
- **60 GB disk** minimum (the `scaleout` image alone is ~15 GB)
- **16 GB RAM** minimum; 32 GB comfortable
- **cgroup v2** — the default on Ubuntu 22.04 and most current distributions,
  so usually nothing to do

### cgroup v2

The containers run systemd internally. The AlmaLinux 9 base ships systemd 252,
compiled `default-hierarchy=unified`, so it starts cleanly under cgroup v2 and
Slurm's `CgroupPlugin=autodetect` picks `cgroup/v2` with no config change.

Verify the host:

```bash
ls /sys/fs/cgroup/ | head -3      # expect cgroup.controllers
docker info | grep -i "Cgroup Version"
```

If you previously forced cgroup v1 for an AlmaLinux 8 build, remove the flag:

```bash
sudo sed -i 's/ systemd.unified_cgroup_hierarchy=0//' /etc/default/grub
sudo update-grub && sudo reboot
```

### Elasticsearch

```bash
sudo sysctl -w vm.max_map_count=262144
```

### Architecture

Built and tested on x86_64. Every image the core cluster needs is multi-arch
(`almalinux`, `mysql`, `alpine`, `grafana`, `influxdb`, `elasticsearch`), so an
arm64 build should be possible — but two optional services have no arm64
image and would need disabling or substituting:

| Image | arm64 |
|-------|-------|
| `docker.elastic.co/kibana/kibana-oss:7.10.1` | no |
| `treydock/ood:latest` (Open OnDemand) | no |

Untested. Note also that multi-arch base images don't guarantee the ~28
source-built components compile cleanly on aarch64.

---

## Quick start

```bash
git clone <this repo>
cd docker-scale-out
git submodule update --init --recursive --depth 1
make build
```

The first build takes 45–90 minutes. It compiles Slurm, PMIx, Podman, OpenMPI,
gdb and roughly 25 other components from source.

Then:

```bash
sinfo                                    # via: docker compose exec login bash
docker compose exec login bash
su - fred
sbatch -N2 --wrap="hostname; sleep 30"
squeue
sacct
```

Cluster users are `arnold bambam barney betty chip dino edna fred gazoo
pebbles wilma`, all under the `bedrock` account.

### Web interfaces

| Service | Port |
|---------|------|
| Open OnDemand | 8081 |
| Grafana | 3000 |
| Slurm REST (via proxy) | 8080 |
| Kibana | 5601 |
| Keycloak | 8083 |

---

## Choosing a Slurm version

Set `SLURM_RELEASE` to any tag or branch from
[SchedMD/slurm](https://github.com/SchedMD/slurm):

```bash
make build SLURM_RELEASE=slurm-25-05-3-1
make build SLURM_RELEASE=master
```

The default is pinned to `slurm-26-05-3-1` in the Makefile. Changing versions
rebuilds only the Slurm layers, not the whole image.

---

## Day-to-day

```bash
docker compose stop / start      # pause and resume, fastest
docker compose down / up -d      # recreate containers
make clean && make               # full reset: wipes volumes and accounting DB
```

Allow 1–2 minutes after startup before `sinfo` responds. The node config is
generated at runtime by a script that waits for slurmdbd.

Use `timeout 15 sinfo` while testing — a hang means slurmctld isn't answering,
and the timeout saves a stuck terminal. When something looks wrong:

```bash
docker compose exec mgmtnode systemctl is-system-running
docker compose exec mgmtnode journalctl -u slurmctld -n 30 --no-pager
```

---

## AlmaLinux 9 and cgroup v2

This fork rebases the image on AlmaLinux 9. The point is cgroup v2: Slurm
26.05 supports it and logs a deprecation warning under v1, but upstream's
AlmaLinux 8 base can't get there. Its systemd 239 is compiled
`default-hierarchy=legacy` and looks for `/sys/fs/cgroup/systemd/`, which
doesn't exist under a unified hierarchy — the container freezes at PID 1 with
"Failed to create /init.scope: No such file or directory". AlmaLinux 9 ships
systemd 252 with `default-hierarchy=unified`.

```bash
docker run --rm scaleout:latest systemctl --version | grep default-hierarchy
```

With the host booted on v2, `CgroupPlugin=autodetect` picks the right plugin
with no Slurm config change — slurmd logs `cgroup/v2: init: Cgroup v2 plugin
loaded` instead of the v1 deprecation warning.

### Host setup

Ubuntu 22.04 defaults to cgroup v2, so no GRUB flag is needed. If you
previously added one for an AlmaLinux 8 build, remove it:

```bash
sudo sed -i 's/ systemd.unified_cgroup_hierarchy=0//' /etc/default/grub
sudo update-grub && sudo reboot
ls /sys/fs/cgroup/ | head -3      # cgroup.controllers = v2
docker info | grep -i "Cgroup Version"
```

### Build fixes for RHEL 9

Seven changes were needed beyond the base image swap:

| Problem | Fix |
|---------|-----|
| `powertools` repo renamed | `dnf config-manager --set-enabled powertools \|\| ... crb` |
| `xmvn` split into subpackages, no bare metapackage | `maven` instead (appstream) |
| `mailx` dropped | `s-nail` |
| `lua-json.noarch` gone | removed — luarocks installs `lunajson` anyway |
| `python3-virtualenv` gone | removed |
| `alternatives --set python3` — RHEL 9 doesn't register it | `ln -sf /usr/bin/python3.11 /usr/local/bin/python3` (and the same for `pip3`); `/usr/local/bin` precedes `/usr/bin` in PATH |
| system Python is 3.9, not 3.6 | `/usr/lib/python3.9/site-packages/` in the pexpect/ptyprocess symlinks |

One further build failure is a gettext version mismatch rather than a package
rename: msmtp ships a `po/Makefile.in.in` generated by gettext 0.19, RHEL 9
provides 0.21, and `autoreconf -i` regenerates the macros to match — leaving
the shipped file stale. `autopoint -f` can't fix it because msmtp's
`configure.ac` sets no `AM_GNU_GETTEXT_VERSION`, so the build uses
`./configure --disable-nls` and skips translations entirely.

### Config that becomes fatal under v2

Two `cgroup.conf` options are v1-only. Under v1 they were tolerated; under v2
slurmctld refuses to start:

```
error: The option "CgroupAutomount" is defunct, please remove it from cgroup.conf.
error: _parse_next_key: Parsing error at unrecognized key: ConstrainKmemSpace
fatal: Could not open/read/parse cgroup.conf file /etc/slurm/cgroup.conf
```

Both are removed here. `CgroupAutomount` mounted the cgroup
filesystem if it wasn't already mounted — under v2 systemd always provides the
single unified mount. `ConstrainKmemSpace` limited kernel memory separately;
v2 merged kernel and user memory into one `memory.max`.

### What the unified hierarchy looks like

Job cgroups are named by **SLUID**, not job ID — a `job_*` search finds
nothing:

```
/sys/fs/cgroup/system.slice/docker-<id>.scope/system.slice/node02_slurmstepd.scope/
  sFCXM21Z5FYT00/          <- the job
    step_0/slurm/
    step_extern/slurm/
```

`memory.max`, `cpu.max`, `cpuset.cpus` and `cgroup.procs` all sit in one
directory, where v1 spread them across `/sys/fs/cgroup/memory/`,
`/cpuset/` and `/cpu/` as parallel trees. v2 also adds `memory.events` (with
an `oom_kill` counter — the definitive record of a memory kill, which v1 only
exposed via dmesg), PSI metrics in `*.pressure`, and `cgroup.kill` for
atomic termination of a whole cgroup.

---

## Changes from upstream

Upstream builds on AlmaLinux 8, which can't run cgroup v2 — its systemd 239 is
compiled `default-hierarchy=legacy` and freezes at PID 1 under a unified
hierarchy. This fork rebases on AlmaLinux 9 (systemd 252) and works on cgroup
v2 without host GRUB changes.

Getting there needed ten fixes, detailed in
[AlmaLinux 9 and cgroup v2](#almalinux-9-and-cgroup-v2):

- RHEL 9 package renames — `powertools` → `crb`, `mailx` → `s-nail`, `xmvn` →
  `maven`, `lua-json` and `python3-virtualenv` dropped
- `python3.11` symlinks in `/usr/local/bin` — RHEL 9 doesn't register python3
  with `alternatives`
- `python3.9` site-packages paths, where upstream assumed 3.6
- msmtp built with `--disable-nls` to sidestep a gettext version mismatch
- munge's SysV init script removed — `systemd-sysv-install` isn't present, so
  `systemctl enable` fails trying to sync it
- Host `/sys/fs/cgroup` bind mounts removed entirely; Docker's systemd driver
  already gives each container a private cgroup namespace on v2
- cgroup v1-only options dropped from `cgroup.conf` (`CgroupAutomount`,
  `ConstrainKmemSpace`) — these are fatal under v2, not merely deprecated

Other changes carried over from the AlmaLinux 8 work:

- Capped build parallelism (`make -j4`) — unbounded `make -j` across 22 build
  steps exhausts memory on smaller machines
- Persistent MySQL volume, so the accounting database survives
  `docker compose down` and the cluster ID stays stable
- XDMoD disabled by default (its CentOS 7 base image no longer has working
  package mirrors)
- `pam_slurm_adopt` changed from `sufficient` to `required` in the SSH PAM
  stack — as `sufficient` it can never actually deny a login
- Grafana dashboard provisioning rewritten to the current schema — the shipped
  version crashes modern Grafana on startup
- Mirror redirects for retired upstream git URLs

---

## Known limitations

**arm64 untested** — see [Architecture](#architecture).

**Not a production deployment.** Passwords are hardcoded, containers run
privileged, and the whole cluster shares one host. It's a learning and testing
environment.
