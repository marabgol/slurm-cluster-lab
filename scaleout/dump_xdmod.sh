#!/bin/bash
# Export finished Slurm jobs for Open XDMoD (imported by the xdmod container).
# Format for XDMoD 11.0 (adds qos after partition), per
# https://open.xdmod.org/11.0/resource-manager-slurm.html
#
# Runs hourly from cron. Backfill older jobs with a start time, e.g.:
#   /etc/cron.hourly/dump_xdmod.sh 2026-01-01
[ -d /xdmod ] || exit 0
export TZ=UTC
START="${1:-now-1hour}"

sacct --allusers --parsable2 --noheader --allocations --duplicates \
	--format jobid,jobidraw,cluster,partition,qos,account,group,gid,user,uid,submit,eligible,start,end,elapsed,exitcode,state,nnodes,ncpus,reqcpus,reqmem,reqtres,alloctres,timelimit,nodelist,jobname \
	--state CANCELLED,COMPLETED,FAILED,NODE_FAIL,PREEMPTED,TIMEOUT \
	--starttime "$START" --endtime now >>/xdmod/data.csv
