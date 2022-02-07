#!/usr/bin/env bash

set -euo pipefail

help() {
cat <<EOF
${0##*\/} -b BootPassword -m MasterPassword -d "/dev/sda /dev/sdb /dev/sdc" -s SwapSizeInGibibyte
OR
${0##*\/} -b BootPassword -m MasterPassword -d "/dev/nvme0n1 /dev/nvme1n1 /dev/nvme2n1" -s SwapSizeInGibibyte

"-d" specifies the disks you want to use for installation.
They should be of the same type and size. Don't mix HDDs with SSDs!
Number of disks must be >=2 and <=4!

"-e" (optional) specifies EFI System Partition size in MiB (default and recommended minimum: 512 MiB).
"-f" (optional) specifies /boot partition size in MiB (default: 1024 MiB).
EOF
    return 1
}

getPartitions() {
    for i in "${DISKS[@]}"; do
        ls "${i}"*"$1"
    done | xargs
}

getMapperPartitions() {
    for i in "${DISKS[@]}"; do
        ls "${i/\/dev\//\/dev\/mapper\/}"*"$1"
    done | xargs
}

EFI_SYSTEM_PARTITION_SIZE="512"
BOOT_PARTITION_SIZE="1024"

# shellcheck disable=SC2207
while getopts b:d:e:f:m:s:h opt; do
    case $opt in
        b) BOOT_PASSWORD="$OPTARG";;
        d) DISKS=( $(xargs <<<"$OPTARG" | tr ' ' '\n' | sort | xargs) );;
        e) EFI_SYSTEM_PARTITION_SIZE="$OPTARG";;
        f) BOOT_PARTITION_SIZE="$OPTARG";;
        m) MASTER_PASSWORD="$OPTARG";;
        s) SWAP_SIZE="$((OPTARG * 1024))";;
        h|?) help;;
    esac
done

# shellcheck disable=SC2068
if [ -z ${BOOT_PASSWORD+x} ] || [ -z ${DISKS+x} ] || [ -z ${MASTER_PASSWORD+x} ] || [ -z ${SWAP_SIZE+x} ] || ! ls ${DISKS[@]} >/dev/null 2>&1; then
    help
fi

case ${#DISKS[@]} in
    1) BTRFS_RAID="single";;
    2) BTRFS_RAID="raid1";;
    3) BTRFS_RAID="raid1c3";;
    4) BTRFS_RAID="raid1c4";;
    *) help;;
esac

# create keyfile
KEYFILE="$(umask 0377 && mktemp)"
dd bs=512 count=16384 iflag=fullblock if=/dev/random of="${KEYFILE}"

# partition
for i in "${DISKS[@]}"; do

    if [ $((512*$(cat "/sys/class/block/${i##*\/}/size"))) -gt 536870912000 ]; then
        ROOT_SIZE="-5119"
    else
        ROOT_SIZE="99%"
    fi

    parted --align optimal --script "$i" \
        mklabel gpt \
        unit MiB \
        "mkpart 'efi system partition' 1 $((1 + EFI_SYSTEM_PARTITION_SIZE))" \
        mkpart boot $((1 + EFI_SYSTEM_PARTITION_SIZE)) $((1 + EFI_SYSTEM_PARTITION_SIZE + BOOT_PARTITION_SIZE)) \
        mkpart swap $((1 + EFI_SYSTEM_PARTITION_SIZE + BOOT_PARTITION_SIZE)) $((1 + EFI_SYSTEM_PARTITION_SIZE + BOOT_PARTITION_SIZE + SWAP_SIZE)) \
        "mkpart root $((1 + EFI_SYSTEM_PARTITION_SIZE + BOOT_PARTITION_SIZE + SWAP_SIZE)) ${ROOT_SIZE}" \
        set 1 esp on
done

# boot partition
# shellcheck disable=SC2046
if [ ${#DISKS[@]} -eq 1 ]; then
    BOOT_PARTITION="$(getPartitions 2)"
else
    BOOT_PARTITION="/dev/md0"
    mdadm --create "${BOOT_PARTITION}" --level=1 --raid-devices=${#DISKS[@]} --metadata=default $(getPartitions 2)
fi

# encrypting boot, swap and root partitions
unset NON_BOOT
# shellcheck disable=SC2046
find "${BOOT_PARTITION}" $(getPartitions 3) $(getPartitions 4) | while read -r I; do
    # shellcheck disable=SC2086
    cryptsetup --batch-mode luksFormat ${NON_BOOT---type luks1} --hash sha512 --cipher aes-xts-plain64 --key-size 512 --key-file "${KEYFILE}" --use-random ${NON_BOOT+--pbkdf argon2id} "$I"
    echo -n "${MASTER_PASSWORD}" | cryptsetup luksAddKey --key-file "${KEYFILE}" ${NON_BOOT+--pbkdf argon2id} "$I" -
    echo -n "${BOOT_PASSWORD}"   | cryptsetup luksAddKey --key-file "${KEYFILE}" ${NON_BOOT+--pbkdf argon2id} "$I" -
    cryptsetup luksOpen --key-file "${KEYFILE}" "$I" "${I##*\/}"
    NON_BOOT=""
done

# EFI system partition
# shellcheck disable=SC2046
ALPHABET=({A..Z})
tmpCount=0
find $(getPartitions 1) | while read -r I; do
    mkfs.vfat -n "EFI${ALPHABET[tmpCount++]}" -F 32 "$I"
done

# boot partition
mkfs.btrfs --checksum blake2 --label boot "/dev/mapper/${BOOT_PARTITION##*\/}"

# swap partition
# shellcheck disable=SC2046
if [ ${#DISKS[@]} -eq 1 ]; then
    SWAP_PARTITION="$(getMapperPartitions 3)"
else
    SWAP_PARTITION="/dev/md1"
    mdadm --create "${SWAP_PARTITION}" --level=1 --raid-devices=${#DISKS[@]} --metadata=default $(getMapperPartitions 3)
fi
mkswap --label swap "${SWAP_PARTITION}"
swapon "${SWAP_PARTITION}"

# root partition
# shellcheck disable=SC2046
mkfs.btrfs --data "${BTRFS_RAID}" --metadata "${BTRFS_RAID}" --checksum blake2 --label system $(getMapperPartitions 4)

if [ ! -d /mnt/gentoo ]; then
    mkdir /mnt/gentoo
fi

# shellcheck disable=SC2046
mount -o noatime $(getMapperPartitions 4 | awk '{print $1}') /mnt/gentoo
btrfs subvolume create /mnt/gentoo/@distfiles; sync
btrfs subvolume create /mnt/gentoo/@home; sync
btrfs subvolume create /mnt/gentoo/@portage; sync
btrfs subvolume create /mnt/gentoo/@root; sync
umount /mnt/gentoo
# shellcheck disable=SC2046
mount -o noatime,subvol=@root $(getMapperPartitions 4 | awk '{print $1}') /mnt/gentoo
mkdir -p /mnt/gentoo/key/mnt/key
rsync -a "${KEYFILE}" /mnt/gentoo/key/mnt/key/key
sync
cmp "${KEYFILE}" /mnt/gentoo/key/mnt/key/key
rm -f "${KEYFILE}"

useradd -m -s /bin/bash meh
chown meh: /mnt/gentoo /tmp/fetch_files.sh
chmod u+x /tmp/fetch_files.sh
su -l meh -c /tmp/fetch_files.sh
chown -R root: /mnt/gentoo

ALPHABET=({a..z})
ln -s "/dev/mapper/${BOOT_PARTITION##*\/}" /mnt/gentoo/mapperBoot
ln -s "${SWAP_PARTITION}" /mnt/gentoo/mapperSwap
ln -s "$(getMapperPartitions 4 | awk '{print $1}')" /mnt/gentoo/mapperRoot
tmpCount=0
# shellcheck disable=SC2046
find $(getPartitions 1) | while read -r I; do
    ln -s "$I" "/mnt/gentoo/devEfi${ALPHABET[tmpCount++]}"
done
ln -s "$(awk '{print $1}' <<<"${BOOT_PARTITION}")" "/mnt/gentoo/devBoot"
tmpCount=0
# shellcheck disable=SC2046
find $(getPartitions 3) | while read -r I; do
    ln -s "$I" "/mnt/gentoo/devSwap${ALPHABET[tmpCount++]}"
done
tmpCount=0
# shellcheck disable=SC2046
find $(getPartitions 4) | while read -r I; do
    ln -s "$I" "/mnt/gentoo/devRoot${ALPHABET[tmpCount++]}"
done

echo $?
