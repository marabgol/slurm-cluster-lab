#!/bin/bash

NODE_NAME=$1
NODE_TOKEN=$2
NODE_TOKEN_LIST_FILE=/etc/slurm/node_token_list.txt

# Check if node token list file exists
if [ ! -f $NODE_TOKEN_LIST_FILE ]; then
	echo "${BASH_SOURCE[@]}" ": Failed to resolve node token list path '$NODE_TOKEN_LIST_FILE'"
	exit 1
fi

# Check if unique node token is in token list file
grep "${NODE_NAME}: ${NODE_TOKEN}" $NODE_TOKEN_LIST_FILE

# Check exit code from grep to see if token was found
if [ $? -ne 0 ]; then
	echo "${BASH_SOURCE[@]}" ": Failed to validate token '$NODE_TOKEN'"
	exit 1
fi

# Exit with exit code 0 to indicate success (node token is valid)
exit 0
