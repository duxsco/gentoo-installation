#!/usr/bin/env bash

# Prevent tainting variables via environment
# See: https://gist.github.com/duxsco/fad211d5828e09d0391f018834f955c9
unset ARCH CLEAR_CCACHE CONTINUE_WITHOUT_KERNEL_CONFIG CRYPTOMOUNT DEFAULT_BOOT_ENTRY EFI_MOUNTPOINT EFI_UUID FILE FILES_BOOT FILES_EFI FILES_OLD GRUB_CONFIG GRUB_LOCAL_CONFIG GRUB_SSH_CONFIG KERNEL_CONFIG KERNEL_VERSION_NEW KERNEL_VERSION_OLD LUKSCLOSE_BOOT LUKS_BOOT_DEVICE MOUNTPOINT NUMBER_REGEX UMOUNT UUID_BOOT_FILESYSTEM UUID_LUKS_BOOT_DEVICE

ARCH="$(arch)"
KERNEL_VERSION_NEW="$(readlink /usr/src/linux | sed 's/linux-//')"
KERNEL_VERSION_OLD="$(uname -r | sed "s/-${ARCH}$//")"
KERNEL_CONFIG="/etc/kernels/kernel-config-${KERNEL_VERSION_NEW}-${ARCH}"
declare -a UMOUNT
FILES_BOOT="$(mktemp --directory --suffix="_files_boot")"
FILES_EFI="$(mktemp --directory --suffix="_files_efi")"
FILES_OLD="$(mktemp --directory --suffix="_files_old")"

##################
# some questions #
##################

if [[ ! -f ${KERNEL_CONFIG} ]]; then

    if [[ -f /etc/gentoo-installation/continue_without_precreated_kernel_config.conf ]]; then
        CONTINUE_WITHOUT_KERNEL_CONFIG="$(</etc/gentoo-installation/continue_without_precreated_kernel_config.conf)"
    else
        read -r -p "You can persist your choice with:
\"echo n > /etc/gentoo-installation/continue_without_precreated_kernel_config.conf\" or
\"echo y > /etc/gentoo-installation/continue_without_precreated_kernel_config.conf\"

Beware that \"${KERNEL_CONFIG}\" doesn't exist!
Do you want to build the kernel without executing \"gkb2gs.sh\" beforehand? (y/N) " CONTINUE_WITHOUT_KERNEL_CONFIG
    fi

    if [[ ${CONTINUE_WITHOUT_KERNEL_CONFIG} =~ ^[nN]$ ]]; then
        echo "Aborting due to missing kernel config!"
        exit 0
    elif ! [[ ${CONTINUE_WITHOUT_KERNEL_CONFIG} =~ ^[yY]$ ]]; then
        if [[ -f /etc/gentoo-installation/continue_without_precreated_kernel_config.conf ]]; then
            echo "\"/etc/gentoo-installation/continue_without_precreated_kernel_config.conf\" misconfigured! Aborting..."
        else
            echo "Invalid choice! Aborting..."
        fi
        exit 1
    fi
fi

if [[ -f /etc/gentoo-installation/grub_default_boot_option.conf ]]; then
    DEFAULT_BOOT_ENTRY="$(</etc/gentoo-installation/grub_default_boot_option.conf)"
else
    read -r -p "You can persist your choice with. e.g.:
echo 0 > /etc/gentoo-installation/grub_default_boot_option.conf

Available boot options:
  0) Remote LUKS unlock via initramfs+dropbear
  1) Local LUKS unlock via TTY/IPMI
  2) SystemRescueCD
  3) Enforce manual selection upon each boot

Please, select your option [0-3]: " DEFAULT_BOOT_ENTRY
    echo ""
fi

NUMBER_REGEX='^[0-3]$'
if ! [[ ${DEFAULT_BOOT_ENTRY} =~ ${NUMBER_REGEX} ]]; then
    if [[ -f /etc/gentoo-installation/grub_default_boot_option.conf ]]; then
        echo "\"/etc/gentoo-installation/grub_default_boot_option.conf\" misconfigured! Aborting..."
    else
        echo "Invalid choice! Aborting..."
    fi
    exit 1
fi

echo ""
read -r -p "Do you want to clear ccache's cache (y/n)?
See \"Is it safe?\" at https://ccache.dev/. Your answer: " CLEAR_CCACHE
echo ""

if ! [[ ${CLEAR_CCACHE} =~ ^[nNyY]$ ]]; then
    echo "No valid response given! Aborting..."
    exit 1
fi

######################
# luksOpen and mount #
######################

if  [[ -b $(find /dev/md -maxdepth 1 -name "*:boot3141592653md") ]]; then
    LUKS_BOOT_DEVICE="$(find /dev/md -maxdepth 1 -name "*:boot3141592653md")"
elif [[ -b /dev/disk/by-partlabel/boot3141592653part ]]; then
    LUKS_BOOT_DEVICE="/dev/disk/by-partlabel/boot3141592653part"
else
    echo 'Failed to find "/boot" LUKS device! Aborting...' >&2
    exit 1
fi

UUID_LUKS_BOOT_DEVICE="$(cryptsetup luksUUID "${LUKS_BOOT_DEVICE}" | tr -d '-')"

if [[ ! -b $(find /dev/disk/by-id -maxdepth 1 -name "dm-uuid-*${UUID_LUKS_BOOT_DEVICE}*") ]]; then
    cryptsetup luksOpen --key-file /etc/gentoo-installation/keyfile/mnt/key/key "${LUKS_BOOT_DEVICE}" boot3141592653temp

    if [[ ! -b $(find /dev/disk/by-id -maxdepth 1 -name "dm-uuid-*${UUID_LUKS_BOOT_DEVICE}*") ]]; then
        echo 'Failed to luksOpen "/boot" LUKS device! Aborting...' >&2
        exit 1
    fi

    LUKSCLOSE_BOOT="true"
fi

while read -r MOUNTPOINT; do
    if ! mountpoint --quiet "${MOUNTPOINT}"; then
        if ! mount "${MOUNTPOINT}"; then
            echo "Failed to mount \"${MOUNTPOINT}\"! Aborting..." >&2
            exit 1
        fi

        UMOUNT+=("${MOUNTPOINT}")
    fi

    rsync -Ha --delete "${MOUNTPOINT}" "${FILES_OLD}/"
done < <(
    echo "/boot"
    grep -Po "^UUID=[0-9A-F]{4}-[0-9A-F]{4}[[:space:]]+\K/efi[a-z](?=[[:space:]]+vfat[[:space:]]+)" /etc/fstab
)

###############################
# verify old gnupg signatures #
###############################

while read -r FILE; do
    if [[ ${FILE} =~ ^.*/bootx64\.efi$ ]]; then
        if ! sbverify --cert /etc/gentoo-installation/secureboot/db.crt "${FILE}" >/dev/null; then
            echo "EFI binary signature verification failed! Aborting..." >&2
            exit 1
        fi
    elif  [[ ! -f ${FILE}.sig ]] || \
        ! grep -q "^GOODSIG TRUST_ULTIMATE VALIDSIG$" < <(
            gpg --homedir /etc/gentoo-installation/gnupg --status-fd 1 --verify "${FILE}.sig" "${FILE}" 2>/dev/null | \
            grep -Po "^\[GNUPG:\][[:space:]]+\K(GOODSIG|VALIDSIG|TRUST_ULTIMATE)(?=[[:space:]])" | \
            sort | \
            paste -d " " -s -
        )
    then
        echo "GnuPG signature verification failed for \"${FILE}\"! Aborting..." >&2
        exit 1
    fi
done < <(find "${FILES_OLD}" -type f ! -name "*\.sig")

#############
# genkernel #
#############

if [[ ${CLEAR_CCACHE} =~ ^[yY]$ ]]; then
    echo "Clearing ccache's cache..."
    ccache --clear
    echo ""
fi

genkernel --bootdir="${FILES_BOOT}" --initramfs-overlay="/etc/gentoo-installation/keyfile" --menuconfig all

# "--menuconfig" is not used, because config
# generated by first genkernel execution in /etc/kernels is reused.
# "--initramfs-overlay" is not used, because generated "*-ssh*" files
# must be stored on a non-encrypted partition.
genkernel --bootdir="${FILES_EFI}" --initramfs-filename="initramfs-%%KV%%-ssh.img" --kernel-filename="vmlinuz-%%KV%%-ssh" --systemmap-filename="System.map-%%KV%%-ssh" --ssh all

###############
# create .old #
###############

for FILE in "/boot/System.map-${KERNEL_VERSION_NEW}-${ARCH}" "/boot/initramfs-${KERNEL_VERSION_NEW}-${ARCH}.img" "/boot/vmlinuz-${KERNEL_VERSION_NEW}-${ARCH}"; do
    if [[ -f ${FILE} ]]; then
        mv "${FILE}" "${FILE}.old"
        mv "${FILE}.sig" "${FILE}.old.sig"
    fi
done

while read -r MOUNTPOINT; do
    for FILE in "/${MOUNTPOINT}/System.map-${KERNEL_VERSION_NEW}-${ARCH}-ssh" "/${MOUNTPOINT}/initramfs-${KERNEL_VERSION_NEW}-${ARCH}-ssh.img" "/${MOUNTPOINT}/vmlinuz-${KERNEL_VERSION_NEW}-${ARCH}-ssh"; do
        if [[ -f ${FILE} ]]; then
            mv "${FILE}" "${FILE}.old"
            mv "${FILE}.sig" "${FILE}.old.sig"
        fi
    done
done < <(grep -Po "^UUID=[0-9A-F]{4}-[0-9A-F]{4}[[:space:]]+/\Kefi[a-z](?=[[:space:]]+vfat[[:space:]]+)" /etc/fstab)

###############
# grub config #
###############

rsync -Ha "${FILES_BOOT}/" /boot/
rsync -Ha "${FILES_EFI}/" /boot/

GRUB_CONFIG="$(
    grub-mkconfig 2>/dev/null | \
    sed -n '/^### BEGIN \/etc\/grub.d\/10_linux ###$/,/^### END \/etc\/grub.d\/10_linux ###$/p' | \
    sed -n '/^submenu/,/^}$/p' | \
    sed '1d;$d' | \
    sed 's/^\t//' | \
    sed -e "s/\$menuentry_id_option/--unrestricted --id/" | \
    grep -v -e "^[[:space:]]*if" -e "^[[:space:]]*fi" -e "^[[:space:]]*load_video" -e "^[[:space:]]*insmod"
)"

UUID_BOOT_FILESYSTEM="$(sed -n 's#^UUID=\([^[:space:]]*\)[[:space:]]*/boot[[:space:]]*.*#\1#p' /etc/fstab)"
CRYPTOMOUNT="\tcryptomount -u ${UUID_LUKS_BOOT_DEVICE}\\
\tset root='cryptouuid/${UUID_LUKS_BOOT_DEVICE}'\\
\tsearch --no-floppy --fs-uuid --set=root --hint='cryptouuid/${UUID_LUKS_BOOT_DEVICE}' ${UUID_BOOT_FILESYSTEM}"

GRUB_LOCAL_CONFIG="$(
    sed -n "/^menuentry.*${KERNEL_VERSION_NEW}-${ARCH}'/,/^}$/p" <<<"${GRUB_CONFIG}" | \
    sed "s#^[[:space:]]*search[[:space:]]*.*#${CRYPTOMOUNT}#"
)"

while read -r EFI_MOUNTPOINT; do
    EFI_UUID="$(grep -Po "(?<=^UUID=)[0-9A-F]{4}-[0-9A-F]{4}(?=[[:space:]]+/${EFI_MOUNTPOINT}[[:space:]]+vfat[[:space:]]+)" /etc/fstab)"
    GRUB_SSH_CONFIG="$(
        sed -n "/^menuentry.*${KERNEL_VERSION_NEW}-${ARCH}-ssh'/,/^}$/p" <<<"${GRUB_CONFIG}" | \
        sed -e "s/^[[:space:]]*search[[:space:]]*\(.*\)/\tsearch --no-floppy --fs-uuid --set=root ${EFI_UUID}/" \
            -e "s|^\([[:space:]]*\)linux[[:space:]]\(.*\)$|\1linux \2 $(</etc/gentoo-installation/dosshd.conf)|" \
            -e 's/root_key=key//'
    )"

    if [[ ${DEFAULT_BOOT_ENTRY} -ne 3 ]]; then
        echo -e "set default=${DEFAULT_BOOT_ENTRY}\nset timeout=5\n" > "${FILES_EFI}/grub_${EFI_MOUNTPOINT}.cfg"
    elif [[ -f ${FILES_EFI}/grub_${EFI_MOUNTPOINT}.cfg ]]; then
        rm "${FILES_EFI}/grub_${EFI_MOUNTPOINT}.cfg"
    fi

    cat <<EOF >> "${FILES_EFI}/grub_${EFI_MOUNTPOINT}.cfg"
${GRUB_SSH_CONFIG}

${GRUB_LOCAL_CONFIG}

$(grep -A999 "^menuentry" /etc/grub.d/40_custom)
EOF

    if [[ -f "/${EFI_MOUNTPOINT}/boot.cfg" ]] && ! cmp "${FILES_EFI}/grub_${EFI_MOUNTPOINT}.cfg" <(sed "s/${KERNEL_VERSION_OLD}/${KERNEL_VERSION_NEW}/g" "/${EFI_MOUNTPOINT}/boot.cfg"); then
        mv "/${EFI_MOUNTPOINT}/boot.cfg" "/${EFI_MOUNTPOINT}/boot.cfg.old"
        mv "/${EFI_MOUNTPOINT}/boot.cfg.sig" "/${EFI_MOUNTPOINT}/boot.cfg.old.sig"
    fi
done < <(grep -Po "^UUID=[0-9A-F]{4}-[0-9A-F]{4}[[:space:]]+/\Kefi[a-z](?=[[:space:]]+vfat[[:space:]]+)" /etc/fstab)

rm /boot/{"System.map-${KERNEL_VERSION_NEW}-${ARCH}-ssh","initramfs-${KERNEL_VERSION_NEW}-${ARCH}-ssh.img","vmlinuz-${KERNEL_VERSION_NEW}-${ARCH}-ssh"}

###########################
# create gnupg signatures #
###########################

chcon -R -t user_tmp_t "${FILES_BOOT}" "${FILES_EFI}" "${FILES_OLD}"

find "${FILES_BOOT}" "${FILES_EFI}" -maxdepth 1 -type f -exec gpg --homedir /etc/gentoo-installation/gnupg --detach-sign {} \;

########
# sync #
########

rsync -a "${FILES_BOOT}"/{"System.map-${KERNEL_VERSION_NEW}-${ARCH}","initramfs-${KERNEL_VERSION_NEW}-${ARCH}.img","vmlinuz-${KERNEL_VERSION_NEW}-${ARCH}"}.sig "/boot/"

while read -r MOUNTPOINT; do
    rsync -a "${FILES_EFI}"/{"System.map-${KERNEL_VERSION_NEW}-${ARCH}-ssh","initramfs-${KERNEL_VERSION_NEW}-${ARCH}-ssh.img","vmlinuz-${KERNEL_VERSION_NEW}-${ARCH}-ssh"}{,.sig} "/${MOUNTPOINT}/"
    rsync -a "${FILES_EFI}/grub_${MOUNTPOINT}.cfg" "/${MOUNTPOINT}/grub.cfg"
    rsync -a "${FILES_EFI}/grub_${MOUNTPOINT}.cfg.sig" "/${MOUNTPOINT}/grub.cfg.sig"
done < <(grep -Po "^UUID=[0-9A-F]{4}-[0-9A-F]{4}[[:space:]]+/\Kefi[a-z](?=[[:space:]]+vfat[[:space:]]+)" /etc/fstab)

##########
# umount #
##########

for MOUNTPOINT in "${UMOUNT[@]}"; do
    umount "${MOUNTPOINT}"

    if mountpoint --quiet "${MOUNTPOINT}"; then
        echo "Failed to umount \"${MOUNTPOINT}\"! Aborting..." >&2
        exit 1
    fi
done

if [[ -n ${LUKSCLOSE_BOOT} ]]; then
    cryptsetup luksClose boot3141592653temp

    if [[ -b $(find /dev/disk/by-id -maxdepth 1 -name "dm-uuid-*${UUID_LUKS_BOOT_DEVICE}*") ]]; then
        echo 'Failed to luksClose "/boot" LUKS device! Aborting...' >&2
        exit 1
    fi
fi

rm -r "${FILES_BOOT}" "${FILES_EFI}" "${FILES_OLD}"
