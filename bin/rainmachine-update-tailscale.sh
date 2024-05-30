#!/bin/bash
TAILSCALE_VERSION=${TAILSCALE_VERSION:-1.66.3}
SSH_HOST=${SSH_HOST:-rainmachine}

set -e

# Download Tailscale binary
wget -q https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_arm.tgz

# Copy binary to Rainmachine
echo "scp tailscale_${TAILSCALE_VERSION}_arm.tgz root@${SSH_HOST}:/tmp"
scp -O tailscale_${TAILSCALE_VERSION}_arm.tgz root@${SSH_HOST}:/tmp

# SSH to Rainmachine and perform setup
ssh root@${SSH_HOST} << EOF
set -e
mkdir -p /data/tailscale
cd /tmp
tar xzvf tailscale_${TAILSCALE_VERSION}_arm.tgz

pkill tailscaled || true

echo "Copying tailscale binary to /system/bin"
cp /tmp/tailscale_${TAILSCALE_VERSION}_arm/{tailscale,tailscaled} /system/bin

if [ ! -e /system/bin/getent ]; then
echo "Setting up /system/bin/getent"
cat >/system/bin/getent <<'GETENT'
#!/system/bin/sh
if [ "\$1" != "passwd" ]; then
    echo "\$1 unsupported by \$0"
fi
cat /etc/\$1 | awk -F: "\\\$3 == \$2 {print}"
GETENT
chmod 755 /system/bin/getent
fi

if [ ! -e /etc/passwd ]; then
echo "Setting up /etc/passwd"
cat >/etc/passwd <<'PASSWD'
root:x:0:0:root:/root:/system/xbin/sh
PASSWD
fi

touch /etc/group

# echo "Backing up rainmachin.sh"
# cp -p /system/bin/rainmachine.sh /system/bin/rainmachine.sh.\$(date +%Y%m%d-%H%M)
# sed -i '/echo "Running rainmachine"/i echo "Running tailscale"\n/system/bin/tailscaled --statedir /data/tailscale --socket /data/tailscale/tailscaled.sock --tun userspace-networking >/dev/null 2>&1 &' /system/bin/rainmachine.sh

# echo "Adding Tailscale boot script"
# sed -i '/echo "Running rainmachine"/i echo "Running tailscale"\n/system/bin/tailscaled --statedir /data/tailscale --socket /data/tailscale/tailscaled.sock --tun userspace-networking >/dev/null 2>&1 &\n' /system/bin/rainmachine.sh
EOF

echo "Add the following to /system/bin/rainmachine.sh:"
cat << 'BOOTSCRIPT'
echo "Running tailscale"
# logs go to /dev/null because they're a bit spammy
/system/bin/tailscaled \
  --statedir /data/tailscale \
  --socket /data/tailscale/tailscaled.sock \
  --tun userspace-networking >/dev/null 2>&1 &
BOOTSCRIPT

echo "Reboot the Rainmachine to start tailscaled"
echo "Then run the following command to start and authorize Tailscale:"
echo "ssh ${SSH_HOST} 'tailscale --socket /data/tailscale/tailscaled.sock up --ssh --hostname rainmachine'"

echo "Add the following to your .ssh/config file:"
cat <<'SSHCONFIG'
Host rainmachine
  KexAlgorithms +diffie-hellman-group1-sha1
  HostKeyAlgorithms +ssh-rsa
  PubKeyAcceptedKeyTypes +ssh-rsa
  PubKeyAcceptedAlgorithms +ssh-rsa
SSHCONFIG