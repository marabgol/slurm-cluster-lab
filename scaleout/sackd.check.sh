#!/bin/bash
exec 1> >(logger -s -t "$(basename $0)") 2>&1

grep -e 'AuthType=auth/slurm' -e 'AuthType=slurm' -- /etc/slurm/slurm.conf ||
	exit 1

#Invert checks in slurmd.check.sh

# never load on a cloud node
[ "$CLOUD" ] && exit 1

awk -vhost="$(hostname -s)" '
	BEGIN {rc = 1}
	$1 == host {rc=0}
	END {exit rc}
' /etc/nodelist
test $? -eq 0 && exit 1 || exit 0
