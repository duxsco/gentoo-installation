#!/usr/bin/env bash

set -euo pipefail

UNMOUNT_BOOT="false"
KERNEL_VERSION="$(readlink /usr/src/linux | sed 's/linux-//')"

if ! mountpoint /boot >/dev/null 2>&1; then
    mount /boot
    UNMOUNT_BOOT="true"
fi

grep -Po "^UUID=[0-9A-F]{4}-[0-9A-F]{4}[[:space:]]+/\Kefi[a-z](?=[[:space:]]+vfat[[:space:]]+)" /etc/fstab | while read -r I; do
    if ! mountpoint "/${I}" >/dev/null 2>&1; then
        mount "/${I}"
    fi
done

find /boot /efi* -type f ! -name "*\.sig" ! -name "bootx64\.efi" | while read -r I; do
    if [ ! -f "${I}.sig" ] || ! grep -q "^GOODSIG TRUST_ULTIMATE VALIDSIG$" < <(gpg --status-fd 1 --verify "${I}.sig" "${I}" 2>/dev/null | grep -Po "^\[GNUPG:\][[:space:]]+\K(GOODSIG|VALIDSIG|TRUST_ULTIMATE)*(?=[[:space:]])" | sort | paste -d ' ' -s -); then
        echo "GnuPG signature verification failed! Aborting..."
        exit 1
    fi
done

grep -Po "^UUID=[0-9A-F]{4}-[0-9A-F]{4}[[:space:]]+/\Kefi[a-z](?=[[:space:]]+vfat[[:space:]]+)" /etc/fstab | while read -r I; do
    rsync -a /boot/{"System.map-${KERNEL_VERSION}-x86_64-ssh","initramfs-${KERNEL_VERSION}-x86_64-ssh.img","vmlinuz-${KERNEL_VERSION}-x86_64-ssh"}{,.sig} "/${I}/"
    cp -a "/boot/grub_${I}.cfg" "/${I}/grub.cfg"
    cp -a "/boot/grub_${I}.cfg.sig" "/${I}/grub.cfg.sig"
    sync
    cmp "/boot/grub_${I}.cfg" "/${I}/grub.cfg"
    cmp "/boot/grub_${I}.cfg.sig" "/${I}/grub.cfg.sig"
    rm -f "/boot/grub_${I}.cfg" "/boot/grub_${I}.cfg.sig"
    umount "/${I}"
done

rm -f /boot/{"System.map-${KERNEL_VERSION}-x86_64-ssh","initramfs-${KERNEL_VERSION}-x86_64-ssh.img","vmlinuz-${KERNEL_VERSION}-x86_64-ssh"}{,.sig}

if [ "${UNMOUNT_BOOT}" == "true" ]; then
    umount /boot
fi
