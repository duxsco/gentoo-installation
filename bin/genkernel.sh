#!/usr/bin/env bash

# Prevent tainting variables via environment
# See: https://gist.github.com/duxsco/fad211d5828e09d0391f018834f955c9
unset arch boot_options clear_ccache continue_with_kernel_config continue_without_gkb2gs_created_kernel_config cryptomount default_boot_entry delete_obsolete_files efi_mountpoint efi_uuid file files_boot files_efi files_old grub_config grub_local_config grub_ssh_config kernel_config_new kernel_config_old kernel_version kernel_version_new kernel_version_obsolete kernel_version_old luks_boot_device luks_boot_device_uuid luks_unlock_via_ssh luksclose_boot mountpoint number_regex obsolete_files umount uuid_boot_filesystem

arch="$(arch)"
kernel_version_new="$(readlink /usr/src/linux | sed 's/linux-//')"
kernel_version_old="$(uname -r | sed "s/-${arch}$//")"
kernel_config_new="/etc/kernels/kernel-config-${kernel_version_new}-${arch}"
kernel_config_old="/etc/kernels/kernel-config-${kernel_version_old}-${arch}"
declare -a umount
files_boot="$(mktemp --directory --suffix="_files_boot")"
files_efi="$(mktemp --directory --suffix="_files_efi")"
files_old="$(mktemp --directory --suffix="_files_old")"

if [[ -f /etc/gentoo-installation/genkernel_sh.conf ]]; then
    # shellcheck source=conf/genkernel_sh.conf
    source /etc/gentoo-installation/genkernel_sh.conf
fi

#################################
# gkb2gs created kernel config? #
#################################

if [[ ! -f ${kernel_config_new} ]]; then

    if [[ -z ${continue_without_gkb2gs_created_kernel_config} ]]; then
        read -r -p "
You can persist your choice by setting \"n\" or \"y\" for
\"continue_without_gkb2gs_created_kernel_config\" in \"/etc/gentoo-installation/genkernel_sh.conf\"!

Beware that \"${kernel_config_new}\" doesn't exist!
Do you want to build the kernel without executing \"gkb2gs.sh\" beforehand? (y/N) " continue_without_gkb2gs_created_kernel_config
    fi

    if [[ ${continue_without_gkb2gs_created_kernel_config} =~ ^[nN]$ ]]; then
        echo -e "\nAs you wish! Aborting..."
        exit 0
    elif ! [[ ${continue_without_gkb2gs_created_kernel_config} =~ ^[yY]$ ]]; then
        echo -e "\nInvalid choice or configuration! Aborting..."
        exit 1
    fi
fi

##################
# remote unlock? #
##################

if [[ -z ${luks_unlock_via_ssh} ]]; then
    if [[ -n ${default_boot_entry} ]]; then
        cat <<EOF
"luks_unlock_via_ssh" must be set in "/etc/gentoo-installation/genkernel_sh.conf"
if "default_boot_entry" has been set in the config file!"
EOF
        exit 1
    fi

    read -r -p "
You can persist your choice by setting \"n\" or \"y\" for
\"luks_unlock_via_ssh\" in \"/etc/gentoo-installation/genkernel_sh.conf\"!

Do you want to be able to remote LUKS unlock via SSH (y/n)? " luks_unlock_via_ssh
fi

if ! [[ ${luks_unlock_via_ssh} =~ ^[nNyY]$ ]]; then
    echo -e "\nnInvalid choice or configuration! Aborting..."
    exit 1
fi

######################
# default boot entry #
######################

if [[ -z $default_boot_entry ]]; then
    if [[ ${luks_unlock_via_ssh} =~ ^[yY]$ ]]; then
        boot_options="  0) Remote LUKS unlock via initramfs+dropbear
  1) Local LUKS unlock via TTY/IPMI
  2) SystemRescueCD
  3) Enforce manual selection upon each boot

Please, select your option [0-3]: "
    else
        boot_options="  0) Gentoo Linux
  1) SystemRescueCD
  2) Enforce manual selection upon each boot

Please, select your option [0-2]: "
    fi

    read -r -p "
You can persist your choice by setting a numerical value for
\"default_boot_entry\" in \"/etc/gentoo-installation/genkernel_sh.conf\"!

Available boot options:
${boot_options}" default_boot_entry

    if [[ ${luks_unlock_via_ssh} =~ ^[yY]$ ]]; then
        number_regex='^[0-3]$'
    else
        number_regex='^[0-2]$'
    fi

    if ! [[ ${default_boot_entry} =~ ${number_regex} ]]; then
        echo -e "\nInvalid choice or configuration! Aborting..."
        exit 1
    fi
fi

##########
# ccache #
##########

read -r -p "
Do you want to clear ccache's cache (y/n)?
See \"Is it safe?\" at https://ccache.dev/. Your answer: " clear_ccache

if ! [[ ${clear_ccache} =~ ^[nNyY]$ ]]; then
    echo -e "\nInvalid choice! Aborting..."
    exit 1
fi

######################
# luksOpen and mount #
######################

if  [[ -b $(find /dev/md -maxdepth 1 -name "*:boot3141592653md") ]]; then
    luks_boot_device="$(find /dev/md -maxdepth 1 -name "*:boot3141592653md")"
elif [[ -b /dev/disk/by-partlabel/boot3141592653part ]]; then
    luks_boot_device="/dev/disk/by-partlabel/boot3141592653part"
else
    echo -e '\nFailed to find "/boot" LUKS device! Aborting...' >&2
    exit 1
fi

luks_boot_device_uuid="$(cryptsetup luksUUID "${luks_boot_device}" | tr -d '-')"

if [[ ! -b $(find /dev/disk/by-id -maxdepth 1 -name "dm-uuid-*${luks_boot_device_uuid}*") ]]; then
    cryptsetup luksOpen --key-file /etc/gentoo-installation/keyfile/mnt/key/key "${luks_boot_device}" boot3141592653temp

    if [[ ! -b $(find /dev/disk/by-id -maxdepth 1 -name "dm-uuid-*${luks_boot_device_uuid}*") ]]; then
        echo -e '\nFailed to luksOpen "/boot" LUKS device! Aborting...' >&2
        exit 1
    fi

    luksclose_boot="true"
fi

while read -r mountpoint; do
    if ! mountpoint --quiet "${mountpoint}"; then
        if ! mount "${mountpoint}"; then
            echo -e "\nFailed to mount \"${mountpoint}\"! Aborting..." >&2
            exit 1
        fi

        umount+=("${mountpoint}")
    fi

    rsync -Ha --delete "${mountpoint}" "${files_old}/"
done < <(
    echo "/boot"
    grep -Po "^UUID=[0-9A-F]{4}-[0-9A-F]{4}[[:space:]]+\K/efi[a-z](?=[[:space:]]+vfat[[:space:]]+)" /etc/fstab
)

###############################
# verify old gnupg signatures #
###############################

while read -r file; do
    if [[ ${file} =~ ^.*/bootx64\.efi$ ]]; then
        if ! sbverify --cert /etc/gentoo-installation/secureboot/db.crt "${file}" >/dev/null; then
            echo -e "\nEFI binary signature verification failed! Aborting..." >&2
            exit 1
        fi
    elif  [[ ! -f ${file}.sig ]] || \
        ! grep -q "^GOODSIG TRUST_ULTIMATE VALIDSIG$" < <(
            gpg --homedir /etc/gentoo-installation/gnupg --status-fd 1 --verify "${file}.sig" "${file}" 2>/dev/null | \
            grep -Po "^\[GNUPG:\][[:space:]]+\K(GOODSIG|VALIDSIG|TRUST_ULTIMATE)(?=[[:space:]])" | \
            sort | \
            paste -d " " -s -
        )
    then
        echo -e "\nGnuPG signature verification failed for \"${file}\"! Aborting..." >&2
        exit 1
    fi
done < <(find "${files_old}" -type f ! -name "*\.sig")

#########################
# delete obsolete files #
#########################

kernel_version_obsolete="$(find /boot /efi* -maxdepth 1 -mindepth 1 -type f -name "vmlinuz-*" | grep -Po "[0-9]+\.[0-9]+\.[0-9]+-gentoo.*-${arch}" | sed "s/-${arch}//" | sort -u | grep -v -e "${kernel_version_new}" -e "${kernel_version_old}" | xargs)"

if [[ -n ${kernel_version_obsolete} ]]; then
    obsolete_files="$(
        for kernel_version in ${kernel_version_obsolete}; do
            # shellcheck disable=SC2086
            find /{boot/{initramfs-${kernel_version}-${arch}.img,{System.map,vmlinuz}-${kernel_version}-${arch}},efi*/{initramfs-${kernel_version}-${arch}-ssh.img,{System.map,vmlinuz}-${kernel_version}-${arch}-ssh}}{,.old}{,.sig} 2>/dev/null
            echo -e "/lib/modules/${kernel_version}-${arch}\n/usr/src/linux-${kernel_version}"
        done | sort | xargs
    )"

    read -r -p "
Do you want to delete following old files and folders?
$(tr ' ' '\n' <<<"${obsolete_files}")

Your answer (y/n): " delete_obsolete_files

    if [[ ${delete_obsolete_files} =~ ^[yY]$ ]]; then
        # shellcheck disable=SC2086
        rm -rf ${obsolete_files}
    fi
fi

#############
# genkernel #
#############

if [[ ${clear_ccache} =~ ^[yY]$ ]]; then
    echo -e "\nClearing ccache's cache..."
    ccache --clear
fi

echo ""
genkernel --bootdir="${files_boot}" --initramfs-overlay="/etc/gentoo-installation/keyfile" --menuconfig all

if [ "${kernel_config_old}" != "${kernel_config_new}" ]; then
    read -r -p "
The new kernel config differs from the old one the following way:
$(diff -y --suppress-common-lines "${kernel_config_old}" "${kernel_config_new}")

Do you want to continue (y/n)? " continue_with_kernel_config

    if [[ ${continue_with_kernel_config} =~ ^[nN]$ ]]; then
        echo -e "\nAs you wish! Aborting..."
        exit 0
    elif ! [[ ${continue_with_kernel_config} =~ ^[yY]$ ]]; then
        echo -e "\nInvalid choice! Aborting..."
        exit 1
    fi
fi

if [[ ${luks_unlock_via_ssh} =~ ^[yY]$ ]]; then
    # "--menuconfig" is not used, because config
    # generated by first genkernel execution in /etc/kernels is reused.
    # "--initramfs-overlay" is not used, because generated "*-ssh*" files
    # must be stored on a non-encrypted partition.
    echo ""
    genkernel --bootdir="${files_efi}" --initramfs-filename="initramfs-%%KV%%-ssh.img" --kernel-filename="vmlinuz-%%KV%%-ssh" --systemmap-filename="System.map-%%KV%%-ssh" --ssh all
fi

###############
# create .old #
###############

for file in "/boot/System.map-${kernel_version_new}-${arch}" "/boot/initramfs-${kernel_version_new}-${arch}.img" "/boot/vmlinuz-${kernel_version_new}-${arch}"; do
    if [[ -f ${file} ]]; then
        mv "${file}" "${file}.old"
        mv "${file}.sig" "${file}.old.sig"
    fi
done

if [[ ${luks_unlock_via_ssh} =~ ^[yY]$ ]]; then
    while read -r mountpoint; do
        for file in "/${mountpoint}/System.map-${kernel_version_new}-${arch}-ssh" "/${mountpoint}/initramfs-${kernel_version_new}-${arch}-ssh.img" "/${mountpoint}/vmlinuz-${kernel_version_new}-${arch}-ssh"; do
            if [[ -f ${file} ]]; then
                mv "${file}" "${file}.old"
                mv "${file}.sig" "${file}.old.sig"
            fi
        done
    done < <(grep -Po "^UUID=[0-9A-F]{4}-[0-9A-F]{4}[[:space:]]+/\Kefi[a-z](?=[[:space:]]+vfat[[:space:]]+)" /etc/fstab)
fi

###############
# grub config #
###############

rsync -Ha "${files_boot}/" /boot/

if [[ ${luks_unlock_via_ssh} =~ ^[yY]$ ]]; then
    rsync -Ha "${files_efi}/" /boot/
fi

grub_config="$(
    grub-mkconfig 2>/dev/null | \
    sed -n '/^### BEGIN \/etc\/grub.d\/10_linux ###$/,/^### END \/etc\/grub.d\/10_linux ###$/p' | \
    sed -n '/^submenu/,/^}$/p' | \
    sed '1d;$d' | \
    sed 's/^\t//' | \
    sed -e "s/\$menuentry_id_option/--unrestricted --id/" | \
    grep -v -e "^[[:space:]]*if" -e "^[[:space:]]*fi" -e "^[[:space:]]*load_video" -e "^[[:space:]]*insmod"
)"

uuid_boot_filesystem="$(sed -n 's#^UUID=\([^[:space:]]*\)[[:space:]]*/boot[[:space:]]*.*#\1#p' /etc/fstab)"
cryptomount="\tcryptomount -u ${luks_boot_device_uuid}\\
\tset root='cryptouuid/${luks_boot_device_uuid}'\\
\tsearch --no-floppy --fs-uuid --set=root --hint='cryptouuid/${luks_boot_device_uuid}' ${uuid_boot_filesystem}"

grub_local_config="$(
    sed -n "/^menuentry.*${kernel_version_new}-${arch}'/,/^}$/p" <<<"${grub_config}" | \
    sed "s#^[[:space:]]*search[[:space:]]*.*#${cryptomount}#"
)"

while read -r efi_mountpoint; do

    if  { [[ ${luks_unlock_via_ssh} =~ ^[yY]$ ]] && [[ ${default_boot_entry} -ne 3 ]]; } || \
        { [[ ${luks_unlock_via_ssh} =~ ^[nN]$ ]] && [[ ${default_boot_entry} -ne 2 ]]; }
    then
        echo -e "set default=${default_boot_entry}\nset timeout=5\n" > "${files_efi}/grub_${efi_mountpoint}.cfg"
    elif [[ -f ${files_efi}/grub_${efi_mountpoint}.cfg ]]; then
        rm "${files_efi}/grub_${efi_mountpoint}.cfg"
    fi

    if [[ ${luks_unlock_via_ssh} =~ ^[yY]$ ]]; then
        efi_uuid="$(grep -Po "(?<=^UUID=)[0-9A-F]{4}-[0-9A-F]{4}(?=[[:space:]]+/${efi_mountpoint}[[:space:]]+vfat[[:space:]]+)" /etc/fstab)"
        grub_ssh_config="$(
            sed -n "/^menuentry.*${kernel_version_new}-${arch}-ssh'/,/^}$/p" <<<"${grub_config}" | \
            sed -e "s/^[[:space:]]*search[[:space:]]*\(.*\)/\tsearch --no-floppy --fs-uuid --set=root ${efi_uuid}/" \
                -e "s|^\([[:space:]]*\)linux[[:space:]]\(.*\)$|\1linux \2 $(</etc/gentoo-installation/dosshd.conf)|" \
                -e 's/root_key=key//'
        )"
        echo "${grub_ssh_config}" >> "${files_efi}/grub_${efi_mountpoint}.cfg"
        echo "" >> "${files_efi}/grub_${efi_mountpoint}.cfg"
    fi

    cat <<EOF >> "${files_efi}/grub_${efi_mountpoint}.cfg"
${grub_local_config}

$(grep -A999 "^menuentry" /etc/grub.d/40_custom)
EOF

    if [[ -f "/${efi_mountpoint}/boot.cfg" ]] && ! cmp "${files_efi}/grub_${efi_mountpoint}.cfg" <(sed "s/${kernel_version_old}/${kernel_version_new}/g" "/${efi_mountpoint}/boot.cfg"); then
        mv "/${efi_mountpoint}/boot.cfg" "/${efi_mountpoint}/boot.cfg.old"
        mv "/${efi_mountpoint}/boot.cfg.sig" "/${efi_mountpoint}/boot.cfg.old.sig"
    fi
done < <(grep -Po "^UUID=[0-9A-F]{4}-[0-9A-F]{4}[[:space:]]+/\Kefi[a-z](?=[[:space:]]+vfat[[:space:]]+)" /etc/fstab)

if [[ ${luks_unlock_via_ssh} =~ ^[yY]$ ]]; then
    rm /boot/{"System.map-${kernel_version_new}-${arch}-ssh","initramfs-${kernel_version_new}-${arch}-ssh.img","vmlinuz-${kernel_version_new}-${arch}-ssh"}
fi

###########################
# create gnupg signatures #
###########################

chcon -R -t user_tmp_t "${files_boot}" "${files_efi}"

find "${files_boot}" "${files_efi}" -maxdepth 1 -type f -exec gpg --homedir /etc/gentoo-installation/gnupg --detach-sign {} \;

########
# sync #
########

rsync -a "${files_boot}"/{"System.map-${kernel_version_new}-${arch}","initramfs-${kernel_version_new}-${arch}.img","vmlinuz-${kernel_version_new}-${arch}"}.sig "/boot/"

while read -r mountpoint; do
    if [[ ${luks_unlock_via_ssh} =~ ^[yY]$ ]]; then
        rsync -a "${files_efi}"/{"System.map-${kernel_version_new}-${arch}-ssh","initramfs-${kernel_version_new}-${arch}-ssh.img","vmlinuz-${kernel_version_new}-${arch}-ssh"}{,.sig} "/${mountpoint}/"
    else
        # shellcheck disable=SC2140
        rm "/${mountpoint}"/{"System.map-"*"-${arch}-ssh","initramfs-"*"-${arch}-ssh.img","vmlinuz-"*"-${arch}-ssh"}{,.sig} 2>/dev/null
    fi
    rsync -a "${files_efi}/grub_${mountpoint}.cfg" "/${mountpoint}/grub.cfg"
    rsync -a "${files_efi}/grub_${mountpoint}.cfg.sig" "/${mountpoint}/grub.cfg.sig"
done < <(grep -Po "^UUID=[0-9A-F]{4}-[0-9A-F]{4}[[:space:]]+/\Kefi[a-z](?=[[:space:]]+vfat[[:space:]]+)" /etc/fstab)

##########
# umount #
##########

for mountpoint in "${umount[@]}"; do
    umount "${mountpoint}"

    if mountpoint --quiet "${mountpoint}"; then
        echo -e "\nFailed to umount \"${mountpoint}\"! Aborting..." >&2
        exit 1
    fi
done

if [[ -n ${luksclose_boot} ]]; then
    cryptsetup luksClose boot3141592653temp

    if [[ -b $(find /dev/disk/by-id -maxdepth 1 -name "dm-uuid-*${luks_boot_device_uuid}*") ]]; then
        echo -e '\nFailed to luksClose "/boot" LUKS device! Aborting...' >&2
        exit 1
    fi
fi

rm -r "${files_boot}" "${files_efi}" "${files_old}"
