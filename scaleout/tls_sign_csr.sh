#!/bin/bash

# Certificate signing request is passed in as arg $1
CSR=$1
CA_CERT=/etc/slurm/ca_cert.pem
CA_KEY=/etc/slurm/ca_cert_key.pem
KEY_PERMISSIONS=600

# Check if CA certificate file exists
if [ ! -f $CA_CERT ]; then
	echo "${BASH_SOURCE[@]}" ": Failed to resolve CA certificate path '$CA_CERT'"
	exit 1
fi

# Check if CA private key file exists
if [ ! -f $CA_KEY ]; then
	echo "${BASH_SOURCE[@]}" ": Failed to resolve CA private key path '$CA_KEY'"
	exit 1
fi

# Check CA private key permissions
if [ "$(stat -c "%a" "$CA_KEY")" -ne "$KEY_PERMISSIONS" ]; then
	echo "${BASH_SOURCE[@]}" ": Bad permissions for CA private key at '$CA_KEY'. Permissions should be $KEY_PERMISSIONS"
	exit 1
fi

# Sign CSR using CA certificate and CA private key and print signed cert to stdout
openssl x509 -req -in $CSR -CA $CA_CERT -CAkey $CA_KEY -CAserial /etc/slurm/ca_cert.srl 2>/dev/null

# Check exit code from openssl
if [ $? -ne 0 ]; then
	echo "${BASH_SOURCE[@]}" ": Failed to generate signed certificate"
	exit 1
fi

# Exit with exit code 0 to indicate success
exit 0
