#!/bin/bash

MAX_TRY=150

# Wait for slurmctld to startup fully
for ((try = 0; try < MAX_TRY; try++)); do
	status="$(scontrol ping --json | jq -r '.pings[0].responding')"
	rc=$?

	if ([ $rc -eq 0 ] && [ "${status}" = "true" ]); then
		break
	elif [ $try -ge $MAX_TRY ]; then
		echo "FAILED"
		exit 1
	fi

	sleep "$(echo "scale=5; 0.1 * $try" | bc)" | xargs sleep
done

exec srun -N10 uptime
