#!/usr/bin/env bash

set -euo pipefail

GPG_TTY="$(tty)"
export GPG_TTY

UNMOUNT="false"

grep -E "^UUID=[0-9A-F]{4}-[0-9A-F]{4}[[:space:]]*/efi[a-z][[:space:]]*vfat[[:space:]]*" /etc/fstab | awk '{print $2}' | while read -r I; do
    if ! mountpoint "$I"; then
        mount "$I"
        UNMOUNT="true"
    fi

    ( grub-mkconfig | sed -n '/^### BEGIN \/etc\/grub.d\/10_linux ###$/,/^### END \/etc\/grub.d\/10_linux ###$/p'; grub-mkconfig | sed -n '/^### BEGIN \/etc\/grub.d\/40_custom ###$/,/^### END \/etc\/grub.d\/40_custom ###$/p' ) | sed -e "s/\$menuentry_id_option/--unrestricted --id/" | sed '/^[[:space:]]*else/,/^[[:space:]]*fi/d' | grep -v -e "^[[:space:]]*if" -e "^[[:space:]]*fi" -e "^[[:space:]]*load_video" -e "^[[:space:]]*insmod" > "${I}/grub.cfg"

    gpg --detach-sign "${I}/grub.cfg"

    if [ "${UNMOUNT}" == "true" ]; then
        umount "$I"
        UNMOUNT="false"
    fi
done

gpgconf --kill all
