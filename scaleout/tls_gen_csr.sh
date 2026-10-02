#!/bin/bash

# Slurm node name is passed in as arg $1
NODE_PRIVATE_KEY=/etc/slurm/${1}_cert_key.pem

openssl ecparam -out $NODE_PRIVATE_KEY -name prime256v1 -genkey

# Check exit code from openssl
if [ $? -ne 0 ]; then
	echo "${BASH_SOURCE[@]}" ": Failed to generate private key"
	exit 1
fi

chmod 0600 $NODE_PRIVATE_KEY

# Generate CSR using node private key and print CSR to stdout
openssl req -new -key $NODE_PRIVATE_KEY \
	-subj "/C=XX/ST=StateName/L=CityName/O=CompanyName/OU=CompanySectionName/CN=${1}"

# Check exit code from openssl
if [ $? -ne 0 ]; then
	echo "${BASH_SOURCE[@]}" ": Failed to generate CSR"
	exit 1
fi

# Exit with exit code 0 to indicate success
exit 0
