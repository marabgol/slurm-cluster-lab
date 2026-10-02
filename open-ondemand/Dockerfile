# Open OnDemand 4.2 on AlmaLinux 9 (same OS as the scaleout cluster nodes)
FROM almalinux:9

RUN dnf install -y dnf-plugins-core epel-release && \
    dnf config-manager --set-enabled crb && \
    dnf module enable -y ruby:3.3 nodejs:22 && \
    dnf install -y https://yum.osc.edu/ondemand/4.2/ondemand-release-web-4.2-1.el9.noarch.rpm && \
    dnf install -y ondemand mod_ssl openssl httpd-tools openssh-clients file lsof util-linux procps-ng && \
    dnf clean all

# Self-signed certificate. OnDemand 4's apps mark their session cookies Secure,
# so the portal must be served over HTTPS or form posts (e.g. Job Composer
# Submit) fail CSRF verification.
RUN openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
      -subj "/CN=open-ondemand" \
      -keyout /etc/pki/tls/private/ood.key \
      -out /etc/pki/tls/certs/ood.crt && \
    chmod 0600 /etc/pki/tls/private/ood.key

# Portal (Apache) config, cluster definition, shell app defaults
COPY ood_portal.yml /etc/ood/config/ood_portal.yml
COPY scaleout.yaml /etc/ood/config/clusters.d/scaleout.yml
COPY shell.env /etc/ood/config/apps/shell/env
RUN rm -f /etc/httpd/conf.d/welcome.conf /etc/httpd/conf.d/ssl.conf && \
    /opt/ood/ood-portal-generator/sbin/update_ood_portal

# Slurm client wrappers: run the real commands on the login node over SSH
COPY sbatch scancel scontrol squeue /usr/local/bin/
RUN chmod 0755 /usr/local/bin/sbatch /usr/local/bin/scancel /usr/local/bin/scontrol /usr/local/bin/squeue

COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

CMD ["/entrypoint.sh"]
