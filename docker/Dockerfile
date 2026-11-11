ARG BASE_IMAGE=gg6-reznik-build:6.30.1
FROM ${BASE_IMAGE}
USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    openssh-server openssh-client iproute2 iputils-ping iperf3 python3 procps ca-certificates util-linux \
    && rm -rf /var/lib/apt/lists/*
# Use the official Greengage installation function, not the demo cluster.
RUN common=$(find / -path '*/concourse/scripts/common.bash' -print -quit 2>/dev/null); \
    test -n "$common"; \
    source "$common"; install_and_configure_gpdb; \
    test -f /usr/local/greengage-db-devel/greengage_path.sh
RUN id gpadmin >/dev/null 2>&1 || useradd -m -s /bin/bash gpadmin
RUN mkdir -p /run/sshd /data /home/gpadmin/.ssh && \
    chown -R gpadmin:gpadmin /data /home/gpadmin /usr/local/greengage-db-devel && \
    chmod 700 /home/gpadmin/.ssh && \
    printf '\nPasswordAuthentication no\nPermitRootLogin no\nUseDNS no\n' >> /etc/ssh/sshd_config && \
    printf 'source /usr/local/greengage-db-devel/greengage_path.sh\nexport MASTER_DATA_DIRECTORY=/data/master/gg-1\nexport PGPORT=5432\nexport PGDATABASE=adb\n' >> /home/gpadmin/.bashrc
COPY docker/entrypoint.sh /usr/local/bin/lab-entrypoint
COPY scripts /opt/lab/scripts
RUN chmod +x /usr/local/bin/lab-entrypoint /opt/lab/scripts/*.sh
ENTRYPOINT ["/usr/local/bin/lab-entrypoint"]
