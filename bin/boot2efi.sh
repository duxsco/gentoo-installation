#!/usr/bin/env bash

# Prevent tainting variables via environment
# See: https://gist.github.com/duxsco/fad211d5828e09d0391f018834f955c9
unset BOOT_EFI_FILE KERNEL_VERSION MOUNTPOINT UMOUNT

function secure_mount() {
    if ! mountpoint --quiet "$1"; then
        if ! mount "$1" || ! mountpoint --quiet "$1"; then
            echo "Failed to mount \"$1\"! Aborting..." >&2
            exit 1
        fi

        UMOUNT+=("$1")
    fi
}

KERNEL_VERSION="$(readlink /usr/src/linux | sed 's/linux-//')"
declare -a UMOUNT

secure_mount "/boot"

grep -Po "^UUID=[0-9A-F]{4}-[0-9A-F]{4}[[:space:]]+/\Kefi[a-z](?=[[:space:]]+vfat[[:space:]]+)" /etc/fstab | while read -r MOUNTPOINT; do
    secure_mount "/${MOUNTPOINT}"
done

find /boot /efi* -type f ! -name "*\.sig" ! -name "bootx64\.efi" | while read -r BOOT_EFI_FILE; do
    if  [[ ! -f ${BOOT_EFI_FILE}.sig ]] || \
        ! grep -q "^GOODSIG TRUST_ULTIMATE VALIDSIG$" < <(
            gpg --status-fd 1 --verify "${BOOT_EFI_FILE}.sig" "${BOOT_EFI_FILE}" 2>/dev/null | \
            grep -Po "^\[GNUPG:\][[:space:]]+\K(GOODSIG|VALIDSIG|TRUST_ULTIMATE)(?=[[:space:]])" | \
            sort | \
            paste -d " " -s -
        )
    then
        echo "GnuPG signature verification failed! Aborting..." >&2
        exit 1
    fi
done

grep -Po "^UUID=[0-9A-F]{4}-[0-9A-F]{4}[[:space:]]+/\Kefi[a-z](?=[[:space:]]+vfat[[:space:]]+)" /etc/fstab | while read -r MOUNTPOINT; do
    rsync -a /boot/{"System.map-${KERNEL_VERSION}-x86_64-ssh","initramfs-${KERNEL_VERSION}-x86_64-ssh.img","vmlinuz-${KERNEL_VERSION}-x86_64-ssh"}{,.sig} "/${MOUNTPOINT}/"
    rsync -a "/boot/grub_${MOUNTPOINT}.cfg" "/${MOUNTPOINT}/grub.cfg"
    rsync -a "/boot/grub_${MOUNTPOINT}.cfg.sig" "/${MOUNTPOINT}/grub.cfg.sig"
    rm "/boot/grub_${MOUNTPOINT}.cfg" "/boot/grub_${MOUNTPOINT}.cfg.sig"
    sync
    umount "/${MOUNTPOINT}"
done

rm -f /boot/{"System.map-${KERNEL_VERSION}-x86_64-ssh","initramfs-${KERNEL_VERSION}-x86_64-ssh.img","vmlinuz-${KERNEL_VERSION}-x86_64-ssh"}{,.sig}

for MOUNTPOINT in "${UMOUNT[@]}"; do
    umount "${MOUNTPOINT}"
done
