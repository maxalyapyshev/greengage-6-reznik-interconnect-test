#!/usr/bin/env bash
set -euo pipefail
mkdir -p /run/sshd /data /home/gpadmin/.ssh
install -o gpadmin -g gpadmin -m 600 /run/lab-keys/id_ed25519 /home/gpadmin/.ssh/id_ed25519
install -o gpadmin -g gpadmin -m 644 /run/lab-keys/id_ed25519.pub /home/gpadmin/.ssh/authorized_keys
cat > /home/gpadmin/.ssh/config <<'EOF'
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
    BatchMode yes
    ConnectTimeout 5
EOF
chown -R gpadmin:gpadmin /home/gpadmin/.ssh /data
chmod 600 /home/gpadmin/.ssh/config
ssh-keygen -A
# All four containers have NET_ADMIN. Limit each egress interface; no speed promise.
tc qdisc replace dev eth0 root tbf rate "${IC_RATE:-200gbit}" burst 16mb latency 50ms
tc -s qdisc show dev eth0
exec /usr/sbin/sshd -D -e
