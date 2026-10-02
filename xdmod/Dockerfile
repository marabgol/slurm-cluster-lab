# Open XDMoD on AlmaLinux 9 (same OS as the scaleout cluster nodes).
#
# XDMoD 11.0 needs PHP 7.4 and does not support PHP 8. AlmaLinux 9 only ships
# PHP 8.x, so PHP 7.4 comes from the Remi repository (php:remi-7.4 module).
# Upstream develops and tests on Rocky 8 only; this combination is unsupported
# but fine for a lab.
FROM almalinux:9

ARG XDMOD_VERSION=11.0.4-2
# Address you type in the browser; XDMoD builds links from it
ARG XDMOD_SITE_ADDRESS=https://192.168.1.248:8082/

ENV container=docker

RUN dnf install -y dnf-plugins-core epel-release && \
    dnf config-manager --set-enabled crb && \
    dnf install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm && \
    dnf module reset -y php && \
    dnf module enable -y php:remi-7.4 nodejs:20 && \
    dnf install -y systemd cronie crontabs logrotate postfix expect openssl jq \
        httpd mod_ssl \
        php php-fpm php-cli php-gd php-json php-mbstring php-mysqlnd php-pdo \
        php-pecl-apcu php-posix php-xml php-zip \
        mariadb-server mariadb nodejs \
        chromium-headless libreoffice-writer librsvg2-tools perl-Image-ExifTool && \
    dnf install -y https://github.com/ubccr/xdmod/releases/download/v${XDMOD_VERSION}/xdmod-${XDMOD_VERSION}.el8.noarch.rpm && \
    dnf clean all

# PHP timezone must match the data (sacct output is UTC); MariaDB must run
# in permissive SQL mode (XDMoD software requirements).
RUN echo 'date.timezone = UTC' > /etc/php.d/99-xdmod.ini && \
    printf '[server]\nsql_mode=\n' > /etc/my.cnf.d/99-xdmod.cnf

# HTTPS only (XDMoD refuses plain HTTP). Self-signed certificate; our own
# vhost replaces ssl.conf's default one so XDMoD is what answers on 443.
RUN openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -subj "/CN=xdmod" \
      -keyout /etc/pki/tls/private/xdmod.key -out /etc/pki/tls/certs/xdmod.crt && \
    chmod 0600 /etc/pki/tls/private/xdmod.key && \
    rm -f /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/welcome.conf
COPY xdmod.conf /etc/httpd/conf.d/xdmod.conf

# First-boot setup (scripted xdmod-setup) and periodic import of Slurm data
RUN echo "XDMOD_SITE_ADDRESS=${XDMOD_SITE_ADDRESS}" > /etc/sysconfig/xdmod-lab
COPY setup/ /usr/local/share/xdmod-lab/
COPY xdmod-firstboot.sh xdmod-ingest.sh /usr/local/sbin/
COPY xdmod-firstboot.service /etc/systemd/system/
COPY xdmod-lab.cron /etc/cron.d/xdmod-lab
RUN chmod 0755 /usr/local/sbin/xdmod-firstboot.sh /usr/local/sbin/xdmod-ingest.sh && \
    chmod 0644 /etc/cron.d/xdmod-lab && \
    systemctl enable mariadb httpd php-fpm crond postfix xdmod-firstboot

STOPSIGNAL SIGRTMIN+3
VOLUME ["/tmp", "/run", "/run/lock"]
COPY startup.sh /sbin/
RUN chmod 0755 /sbin/startup.sh
CMD [ "/sbin/startup.sh" ]
EXPOSE 443/tcp
