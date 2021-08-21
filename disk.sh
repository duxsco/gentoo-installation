#!/bin/bash

set -euo pipefail

help() {
cat <<EOF
${0##*\/} -b BootPassword -m MasterPassword -d "/dev/sda /dev/sdb /dev/sdc" -s SwapSizeInGibibyte
OR
${0##*\/} -b BootPassword -m MasterPassword -d "/dev/nvme0n1 /dev/nvme1n1 /dev/nvme2n1" -s SwapSizeInGibibyte

"-d" specifies the disks you want to use for installation.
They should be of the same type and size. Don't mix HDDs with SSDs!
At least two disks must be given!
EOF
    return 1
}

getPartitions() {
    for i in "${DISKS[@]}"; do
        ls "${i}"[a-z0-9]*"$1"
    done | xargs
}

getMapperPartitions() {
    for i in "${DISKS[@]}"; do
        ls "${i/\/dev\//\/dev\/mapper\/}"[a-z0-9]*"$1"
    done | xargs
}

# shellcheck disable=SC2207
while getopts b:d:m:s:h opt
do
   case $opt in
       b) BOOT_PASSWORD="$OPTARG";;
       d) DISKS=( $(xargs <<<"$OPTARG" | tr ' ' '\n' | sort | xargs) );;
       m) MASTER_PASSWORD="$OPTARG";;
       s) SWAP_SIZE="$((OPTARG * 1024))";;
       h|?) help;;
   esac
done

# shellcheck disable=SC2068
if [ -z ${BOOT_PASSWORD+x} ] || [ -z ${DISKS+x} ] || [ -z ${MASTER_PASSWORD+x} ] || [ -z ${SWAP_SIZE+x} ] || ! ls ${DISKS[@]} >/dev/null 2>&1; then
    help
fi

if [ ${#DISKS[@]} -eq 2 ]; then
    BTRFS_RAID=raid1
elif [ ${#DISKS[@]} -eq 3 ]; then
    BTRFS_RAID=raid1c3
elif [ ${#DISKS[@]} -eq 4 ]; then
    BTRFS_RAID=raid1c4
else
    help
fi

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
        "mkpart 'efi system partition' 1 513" \
        mkpart boot 513 1537 \
        mkpart swap 1537 $((SWAP_SIZE + 1537)) \
        "mkpart root $((SWAP_SIZE + 1537)) ${ROOT_SIZE}" \
        set 1 esp on
done

# boot partition
# shellcheck disable=SC2046
mdadm --create /dev/md0 --level=1 --raid-devices=${#DISKS[@]} --metadata=default $(getPartitions 2)

# encrypting boot, swap and root partitions
unset NON_BOOT
# shellcheck disable=SC2046
find /dev/md0 $(getPartitions 3) $(getPartitions 4) | while read -r I; do
    # shellcheck disable=SC2086
    cryptsetup --batch-mode luksFormat ${NON_BOOT---type luks1} --hash sha512 --cipher aes-xts-plain64 --key-size 512 --key-file "${KEYFILE}" --use-random ${NON_BOOT+--pbkdf argon2id} "$I"
    echo -n "${MASTER_PASSWORD}" | cryptsetup luksAddKey --key-file "${KEYFILE}" ${NON_BOOT+--pbkdf argon2id} "$I" -
    echo -n "${BOOT_PASSWORD}"   | cryptsetup luksAddKey --key-file "${KEYFILE}" ${NON_BOOT+--pbkdf argon2id} "$I" -
    cryptsetup luksOpen --key-file "${KEYFILE}" "$I" "${I##*\/}"
    NON_BOOT=""
done

# EFI system partition
# shellcheck disable=SC2046
find $(getPartitions 1) | while read -r I; do
    mkfs.vfat -F 32 "$I"
done

# boot partition
mkfs.btrfs --checksum blake2 /dev/mapper/md0

# swap partition
# shellcheck disable=SC2046
mdadm --create /dev/md1 --level=1 --raid-devices=${#DISKS[@]} --metadata=default $(getMapperPartitions 3)
mkswap /dev/md1
swapon /dev/md1

# root partition
# shellcheck disable=SC2046
mkfs.btrfs --data "${BTRFS_RAID}" --metadata "${BTRFS_RAID}" --checksum blake2 $(getMapperPartitions 4)

mkdir /mnt/gentoo
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
ln -s "$(getMapperPartitions 4 | awk '{print $1}')" /mnt/gentoo/mapperRoot
tmpCount=0
# shellcheck disable=SC2046
find $(getPartitions 1) | while read -r I; do
    ln -s "$I" "/mnt/gentoo/devEfi${ALPHABET[tmpCount++]}"
done
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