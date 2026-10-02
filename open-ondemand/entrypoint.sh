#!/bin/bash
#
# /home must be mounted so users are created with the same UIDs as the cluster
#
getent group bedrock >/dev/null || groupadd -g 1005 bedrock
touch /etc/httpd/.htpasswd

cd /home || exit 1
for i in *; do
	[ -d "/home/$i" ] || continue
	TUID=$(stat -c %u "/home/$i")
	[ "$TUID" -eq 0 ] && continue
	htpasswd -b /etc/httpd/.htpasswd "$i" password
	id "$i" >/dev/null 2>&1 || useradd -M -u "$TUID" -c "$i" -g users -G bedrock "$i"
done
chgrp apache /etc/httpd/.htpasswd
chmod 0640 /etc/httpd/.htpasswd

#
# Use the cluster's shared SSH config and host keys
#
for i in ssh_config ssh_host_ecdsa_key ssh_host_ecdsa_key.pub ssh_host_ed25519_key ssh_host_ed25519_key.pub ssh_host_rsa_key ssh_host_rsa_key.pub ssh_known_hosts sshd_config; do
	ln -nfs "/etc/shared-ssh/$i" "/etc/ssh/$i"
done

mkdir -p /run/httpd
exec /usr/sbin/httpd -DFOREGROUND
