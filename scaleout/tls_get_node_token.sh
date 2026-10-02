#!/bin/bash

# Slurm node name is passed in as arg $1
TOKEN_PATH=/etc/slurm/${1}_token.txt
TOKEN_PERMISSIONS=600

# Check if token file exists
if [ ! -f $TOKEN_PATH ]; then
	echo "${BASH_SOURCE[@]}" ": Failed to resolve token path '$TOKEN_PATH'"
	exit 1
fi

# Check node private key permissions
if [ "$(stat -c "%a" "$TOKEN_PATH")" -ne "$TOKEN_PERMISSIONS" ]; then
	echo "${BASH_SOURCE[@]}" ": Bad permissions for node token at '$TOKEN_PATH'. Permissions should be $TOKEN_PERMISSIONS"
	exit 1
fi

# Print token to stdout
cat $TOKEN_PATH

# Exit with exit code 0 to indicate success
exit 0
