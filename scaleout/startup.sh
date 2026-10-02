#!/bin/bash

# Add hosts in the not crazy slow manner
cat /etc/hosts.nodes >>/etc/hosts

#ensure the systemd cgroup directory exists for enroot
awk -F: '$2 ~ /systemd/ {printf "/sys/fs/cgroup/systemd/%s", $3}' /proc/self/cgroup |
	xargs mkdir -p

#systemd user@.service handles on normal nodes
for i in arnold bambam barney betty chip dino edna fred gazoo pebbles wilma; do
	uid=$(id -u $i)
	mkdir -p /run/user/${uid}/local
	mkdir -p /run/user/${uid}/enroot/{runtime,cache,data,tmp}
	chmod 0700 -R /run/user/${uid}/{local,enroot}
	chown -R $i:users /run/user/${uid}/enroot
	chown $i:users /run/user/$uid
done

ls /usr/lib/systemd/system/slurm*.service | while read s; do
	#We must set the cluster environment variable for all services since systemd drops it for the services
	mkdir -p ${s}.d
	echo -e "[Service]\nEnvironment=SLURM_FEDERATION_CLUSTER=${SLURM_FEDERATION_CLUSTER}\n" >${s}.d/cluster.conf
done

# Login node: allow normal SSH; pam_slurm_adopt is for compute nodes only
if [ "$(hostname)" = "login" ]; then
	sed -i '/pam_slurm_adopt/d' /etc/pam.d/sshd
fi

#start systemd
exec /lib/systemd/systemd --system --log-level=info --crash-reboot --log-target=console
