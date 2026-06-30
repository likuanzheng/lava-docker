#!/bin/bash
set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <uInitrd>"
    exit 1
fi

UINITRD=$(realpath "$1")

if [ ! -f "$UINITRD" ]; then
    echo "Error: file not found: $UINITRD"
    exit 1
fi

WORK=$(mktemp -d)
trap "rm -rf $WORK /tmp/initramfs-new.cpio.gz" EXIT

echo "Unpacking $UINITRD ..."
dd if="$UINITRD" bs=64 skip=1 2>/dev/null | gunzip | (cd "$WORK" && cpio -idm --no-absolute-filenames 2>/dev/null)

# 支持两种情况：直接解包到 WORK，或带有临时目录前缀
if [ -f "$WORK/etc/shadow" ]; then
    ROOTFS="$WORK"
else
    INNER=$(ls "$WORK/tmp/" 2>/dev/null | head -1)
    ROOTFS="$WORK/tmp/$INNER"
fi
echo "Rootfs at: $ROOTFS"

echo "Injecting SSH key ..."
mkdir -p "$ROOTFS/root/.ssh"
cp ~/.ssh/id_ed25519 "$ROOTFS/root/.ssh/id_ed25519"
chmod 700 "$ROOTFS/root/.ssh"
chmod 600 "$ROOTFS/root/.ssh/id_ed25519"

cat > "$ROOTFS/root/.ssh/config" <<'EOF'
Host 192.168.32.9
    IdentityFile /root/.ssh/id_ed25519
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
chmod 600 "$ROOTFS/root/.ssh/config"

echo "Setting root password ..."
DAYS=$(python3 -c "import time; print(int(time.time() // 86400))")
# 清空密码哈希，允许无密码登录
sed -i "s|^root:[^:]*:[^:]*:|root::${DAYS}:|" "$ROOTFS/etc/shadow"

echo "Repacking ..."
(cd "$ROOTFS" && fakeroot sh -c 'find . | cpio -o -H newc 2>/dev/null') | gzip > /tmp/initramfs-new.cpio.gz

mkimage -A arm64 -T ramdisk -C gzip -n "initramfs" \
    -d /tmp/initramfs-new.cpio.gz "$UINITRD"

echo "Done: $UINITRD"
