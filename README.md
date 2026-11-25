# slurm-cluster-lab

A containerized multi-node Slurm cluster for learning and testing, running
**Slurm 26.05.3** on AlmaLinux 9 with cgroup v2, under Docker Compose.

Forked from [SchedMD/training/docker-scale-out](https://gitlab.com/SchedMD/training/docker-scale-out).
The original design is SchedMD's; this fork rebases it on AlmaLinux 9 so it
runs on cgroup v2 hosts, and carries assorted build fixes.

---

## What you get

A 26-container cluster that behaves like a real Slurm deployment:

| Component | Containers |
|-----------|-----------|
| Controllers | `mgmtnode` (primary), `mgmtnode2` (backup) |
| Accounting | `slurmdbd` + MySQL (`db`) |
| Compute | `node00`–`node09` |
| Access | `login`, `rest` (slurmrestd), `proxy` (authenticating HTTP proxy) |
| Web portal | Open OnDemand, Keycloak |
| Monitoring | Grafana, InfluxDB, Elasticsearch ×3, Kibana |
| Reporting | Open XDMoD |

```
$ sinfo
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
cloud        up   infinite   1025  idle~ cloud[0000-1024]
debug*       up   infinite     10   idle node[00-09]
```

The `cloud` partition demonstrates Slurm's power-saving / cloud-bursting
feature: 1025 nodes defined but powered down (`idle~`).

Real HA, real munge authentication, cgroup v2 job containment, a working REST
API, job profiling to InfluxDB, completion records in Elasticsearch, and an
accounting chain feeding XDMoD. Good for learning Slurm administration,
testing configurations, or reproducing behaviour before touching a production
cluster.

---

## Requirements

Runs on **x86_64 and arm64**, including Apple Silicon:

| Tested on | Architecture |
|-----------|--------------|
| Ubuntu 22.04, VirtualBox on an Intel iMac | x86_64 |
| Ubuntu 26.04.1 LTS, Parallels on an Apple M3 | arm64 |

- **8 CPUs, 16 GB RAM** minimum (32 GB comfortable)
- **100 GB free disk** minimum, 150–200 GB recommended
- **Docker CE** with Compose v2, cgroup v2, and a few kernel settings

The host needs preparing before the first build. **See
[docs/host-setup.md](docs/host-setup.md)**, or run the script that automates
it:

```bash
./setup-host.sh --check     # report only
./setup-host.sh             # install Docker, set sysctls, qemu on arm64
```

The two settings that most often catch people out:

- **inotify limits.** 16 containers run systemd, and Ubuntu's default of 128
  inotify instances runs out. Nodes then stay `unk*` or exit with "Too many
  open files".
- **`vm.max_map_count=262144`**, or Elasticsearch won't start.

On arm64 everything runs natively except Kibana, which has no arm64 image and
runs under qemu emulation.

---

## Quick start

```bash
git clone --recurse-submodules --shallow-submodules \
  https://github.com/marabgol/slurm-cluster-lab.git
cd slurm-cluster-lab
git submodule update --init --recursive --depth 1    # always: fills anything missing
make
```

`make` builds the images and starts the cluster. The first build compiles
Slurm, PMIx, OpenMPI, Podman, gdb, valgrind and roughly 20 other components
from source: about 20 minutes on an Apple M3, 45–90 minutes on an older Intel
machine.

Allow two or three minutes after startup, then:

```bash
docker compose exec login bash
sinfo
su - fred
sbatch -N2 --wrap="hostname; sleep 30"
squeue
sacct
```

Cluster users are `arnold bambam barney betty chip dino edna fred gazoo
pebbles wilma`, all under the `bedrock` account.

### Web interfaces

| Service | URL | Login |
|---------|-----|-------|
| Open OnDemand | `http://<host>:8081` | any cluster user / `password` |
| Open XDMoD | `https://<host>:8082` | `admin` / `admin` |
| Grafana | `http://<host>:3000` | `admin` / `admin` |
| Kibana | `http://<host>:5601` | none |
| Keycloak | `http://<host>:8083` | service account, see `keycloak/startup.sh` |
| Slurm REST (via proxy) | `http://<host>:8080` | |

XDMoD uses a self-signed certificate, so expect a browser warning.

**XDMoD** shows nothing until jobs have finished and been ingested. An hourly
cron job on `mgmtnode` exports finished jobs, and the xdmod container ingests
them. To populate it straight away:

```bash
docker compose exec mgmtnode /etc/cron.hourly/dump_xdmod.sh 2026-01-01
docker compose exec xdmod /usr/local/sbin/xdmod-ingest.sh
docker compose exec xdmod runuser -u xdmod -- acl-config
```

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
docker compose down / up -d      # recreate containers, keep volumes
make clean && make               # full reset: wipes volumes, images and accounting DB
```

Use `timeout 15 sinfo` while testing. A hang means slurmctld isn't answering.

### Troubleshooting

**`sinfo` hangs after a fresh start.** MySQL was still initialising its empty
volume when slurmdbd started. Restart in dependency order:

```bash
docker compose exec slurmdbd systemctl restart slurmdbd
sleep 10
docker compose exec mgmtnode systemctl restart slurmctld
```

**Some nodes stay `unk*`, or a node container has exited.** Check its log:

```bash
docker compose logs node01 | tail
```

"Too many open files" means the host's inotify limit is too low. See
[docs/host-setup.md](docs/host-setup.md).

**The build fails on a source directory**, with errors like `does not
appear to contain CMakeLists.txt`, `configure.ac is required`, or `not found`
on a `COPY src/...` line. Submodules are missing, typically after a plain
`git clone`:

```bash
git submodule status --recursive | grep -v "^ "     # lines starting "-" are missing
git submodule update --init --recursive --depth 1
```

**General health:**

```bash
docker compose ps -a --format "{{.Name}}\t{{.Status}}" | grep -v "Up "
docker compose exec mgmtnode journalctl -u slurmctld -n 30 --no-pager
```

**`make clean` doesn't remove everything.** It does nothing if
`docker-compose.yml` is missing, and it can't remove volumes still held by
containers started outside Compose. Check `docker ps -a` for strays.

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

Ubuntu 22.04 and later default to cgroup v2, so no GRUB flag is needed. See
[docs/host-setup.md](docs/host-setup.md) if the host was previously forced to
v1.

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

### arm64 support

The same repo builds on both architectures:

- `java-21-openjdk.$(uname -m)` instead of a hardcoded `x86_64`
- Kibana pinned to `platform: linux/amd64`, since `kibana-oss:7.10.1` has no
  arm64 image. Everything else is native.

### Fixes found while reproducing from a clean clone

- **Submodules pinned to tested commits.** Unpinned, each submodule followed
  its upstream HEAD, and newer libjwt (CMake-only) broke the autotools build.
- **Open OnDemand dashboard.** `/etc/shadow` is set to `0400` at container
  start. With RHEL 9's default `000`, the `pam_unix` helper couldn't read
  account data when Apache ran `sudo nginx_stage`, so every login ended in
  "PAM account management error".
- **XDMoD export.** The hourly `dump_xdmod.sh` now sets `PATH`; under cron it
  couldn't find `sacct` and exported nothing.

### Carried over from the AlmaLinux 8 work

- Capped build parallelism (`make -j4`). Unbounded `make -j` across 22 build
  steps exhausts memory on smaller machines.
- Persistent MySQL volume, so the accounting database survives
  `docker compose down` and the cluster ID stays stable.
- `pam_slurm_adopt` changed from `sufficient` to `required` in the SSH PAM
  stack. As `sufficient` it can never actually deny a login.
- Grafana dashboard provisioning rewritten to the current schema. The shipped
  version crashes modern Grafana on startup.

---

## Known limitations

**Not a production deployment.** Passwords are hardcoded, containers run
privileged, and the whole cluster shares one host. It's a learning and testing
environment.

**Kibana is the legacy OSS 7.10 build**, emulated on arm64. Replacing the
Elastic pair with OpenSearch and OpenSearch Dashboards would make it native
and maintained.

**Some base images float** (`almalinux:9`, `grafana/grafana:latest`,
`keycloak:latest`, `mysql:8`). A future upstream release can break the build
the way `grafana:latest` once broke dashboard provisioning.
