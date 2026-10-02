#!/bin/bash

# Slurm node name is passed in as arg $1
NODE_PRIVATE_KEY=/etc/slurm/${1}_cert_key.pem

# Check if node private key file exists
if [ ! -f $NODE_PRIVATE_KEY ]; then
	echo "${BASH_SOURCE[@]}" ": Failed to resolve node private key path '$NODE_PRIVATE_KEY'"
	exit 1
fi

cat $NODE_PRIVATE_KEY

# Exit with exit code 0 to indicate success
exit 0
