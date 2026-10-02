#!/bin/bash
([ -z "$1" ] || [ -z "$2" ]) && echo "USAGE:\n$0 {user_name} {user_password}" && exit 1

curl -s \
	-d "client_id=test" \
	-d "client_secret=secret" \
	-d "username=$1" \
	-d "password=$2" \
	-d "grant_type=password" \
	-d "scope=openid" \
	"http://{SUBNET}.1.23:8080/realms/master/protocol/openid-connect/token" |
	jq -r '.id_token'
