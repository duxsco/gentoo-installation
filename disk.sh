#!/usr/bin/env bash

set -euo pipefail

help() {
cat <<EOF
${0##*\/} -b BootPassword -m MasterPassword -r RescuePassword -d "/dev/sda /dev/sdb /dev/sdc" -s SwapSizeInGibibyte
OR
${0##*\/} -b BootPassword -m MasterPassword -r RescuePassword -d "/dev/nvme0n1 /dev/nvme1n1 /dev/nvme2n1" -s SwapSizeInGibibyte

"-d" specifies the disks you want to use for installation.
They should be of the same type and size. Don't mix HDDs with SSDs!

By default, RAID 1 is used for multi-disk setups.
This can be changed for "swap" and "system" partitions.
In case of the "system" partition (contains @home, @root etc.),
this is only applied to the data group blocks,
while raid1, raid1c3 or raid1c4 is used for metadata group blocks, due to:
https://btrfs.wiki.kernel.org/index.php/RAID56

Optional RAID flags:
"-5": Create RAID 5 devices which require >=3 disks.
"-6": Create RAID 6 devices which require >=4 disks.
"-t": Create RAID 10 devices which require >=4+2*x disks with x being a non-negative integer.

Further optional flags:
"-e": specifies EFI System Partition size in MiB (default and recommended minimum: 512 MiB).
"-f": specifies /boot partition size in MiB (default: 512 MiB).
"-i": specifies SystemRescueCD partition size in MiB (default: 5120 MiB; recommended minimum: 1024 MiB)
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
BOOT_PARTITION_SIZE="512"
RESCUE_PARTITION_SIZE="5120"
RAID=""
RAID5="false"
RAID6="false"
RAID10="false"

# shellcheck disable=SC2207
while getopts 56b:d:e:f:i:m:r:s:th opt; do
    case $opt in
        5) RAID5="true"; RAID="5";;
        6) RAID6="true"; RAID="6";;
        b) BOOT_PASSWORD="$OPTARG";;
        d) DISKS=( $(xargs <<<"$OPTARG" | tr ' ' '\n' | sort | xargs) );;
        e) EFI_SYSTEM_PARTITION_SIZE="$OPTARG";;
        f) BOOT_PARTITION_SIZE="$OPTARG";;
        i) RESCUE_PARTITION_SIZE="$OPTARG";;
        m) MASTER_PASSWORD="$OPTARG";;
        r) RESCUE_PASSWORD="$OPTARG";;
        s) SWAP_SIZE="$((OPTARG * 1024))";;
        t) RAID10="true"; RAID="10";;
        h|?) help;;
    esac
done

# shellcheck disable=SC2068
if { [ "${RAID5}" == "true" ] && [ "${RAID6}" == "true" ]; } || \
   { [ "${RAID6}" == "true" ] && [ "${RAID10}" == "true" ]; } || \
   { [ "${RAID10}" == "true" ] && [ "${RAID5}" == "true" ]; } || \
   { [[ ${#DISKS[@]} -lt 3 ]] && [[ ${RAID} -eq 5 ]]; } || \
   { [[ ${#DISKS[@]} -lt 4 ]] && [[ ${RAID} -eq 6 ]]; } || \
   { [[ ${#DISKS[@]} -lt 4 ]] && [[ ${RAID} -eq 10 ]]; } || \
   { [[ $((${#DISKS[@]}%2)) -ne 0 ]] && [[ ${RAID} -eq 10 ]]; } || \
   [ -z ${BOOT_PASSWORD+x} ] || [ -z ${DISKS+x} ] || [ -z ${MASTER_PASSWORD+x} ] || \
   [ -z ${RESCUE_PASSWORD+x} ] || [ -z ${SWAP_SIZE+x} ] || ! ls ${DISKS[@]} >/dev/null 2>&1; then
    help
fi

case ${#DISKS[@]} in
    1) BTRFS_RAID_DATA="single"; BTRFS_RAID_METADATA="single";;
    2) BTRFS_RAID_DATA="raid1"; BTRFS_RAID_METADATA="raid1";;
    3) BTRFS_RAID_DATA="raid${RAID:-1c3}"; BTRFS_RAID_METADATA="raid1c3";;
    *) BTRFS_RAID_DATA="raid${RAID:-1c4}"; BTRFS_RAID_METADATA="raid1c4";;
esac

# create keyfile
KEYFILE="$(umask 0377 && mktemp)"
dd bs=512 count=16384 iflag=fullblock if=/dev/random of="${KEYFILE}"

# partition
for i in "${DISKS[@]}"; do

    if [ $((512*$(cat "/sys/class/block/${i##*\/}/size"))) -gt 536870912000 ]; then
        SYSTEM_SIZE="-5119"
    else
        SYSTEM_SIZE="99%"
    fi

    parted --align optimal --script "$i" \
        mklabel gpt \
        unit MiB \
        "mkpart 'efi system partition' 1 $((1 + EFI_SYSTEM_PARTITION_SIZE))" \
        mkpart boot $((1 + EFI_SYSTEM_PARTITION_SIZE)) $((1 + EFI_SYSTEM_PARTITION_SIZE + BOOT_PARTITION_SIZE)) \
        mkpart rescue $((1 + EFI_SYSTEM_PARTITION_SIZE + BOOT_PARTITION_SIZE)) $((1 + EFI_SYSTEM_PARTITION_SIZE + BOOT_PARTITION_SIZE + RESCUE_PARTITION_SIZE)) \
        mkpart swap $((1 + EFI_SYSTEM_PARTITION_SIZE + BOOT_PARTITION_SIZE + RESCUE_PARTITION_SIZE)) $((1 + EFI_SYSTEM_PARTITION_SIZE + BOOT_PARTITION_SIZE + RESCUE_PARTITION_SIZE + SWAP_SIZE)) \
        "mkpart system $((1 + EFI_SYSTEM_PARTITION_SIZE + BOOT_PARTITION_SIZE + RESCUE_PARTITION_SIZE + SWAP_SIZE)) ${SYSTEM_SIZE}" \
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

# rescue partition
# shellcheck disable=SC2046
if [ ${#DISKS[@]} -eq 1 ]; then
    RESCUE_PARTITION="$(getPartitions 3)"
else
    RESCUE_PARTITION="/dev/md1"
    mdadm --create "${RESCUE_PARTITION}" --level=1 --raid-devices=${#DISKS[@]} --metadata=default $(getPartitions 3)
fi

# encrypting boot, swap and system partitions
unset NON_BOOT
INDEX=0
# shellcheck disable=SC2046
find "${BOOT_PARTITION}" "${RESCUE_PARTITION}" $(getPartitions 4) $(getPartitions 5) | while read -r I; do
    if [[ ${INDEX} -ge 2 ]]; then
        NON_BOOT=""
    fi
    # shellcheck disable=SC2086
    cryptsetup --batch-mode luksFormat ${NON_BOOT---type luks1} --hash sha512 --cipher aes-xts-plain64 --key-size 512 --key-file "${KEYFILE}" --use-random ${NON_BOOT+--pbkdf argon2id} "$I"
    if [[ ${INDEX} -eq 1 ]]; then
        echo -n "${RESCUE_PASSWORD}" | cryptsetup luksAddKey --key-file "${KEYFILE}" ${NON_BOOT+--pbkdf argon2id} "$I" -
    else
        echo -n "${MASTER_PASSWORD}" | cryptsetup luksAddKey --key-file "${KEYFILE}" ${NON_BOOT+--pbkdf argon2id} "$I" -
        echo -n "${BOOT_PASSWORD}"   | cryptsetup luksAddKey --key-file "${KEYFILE}" ${NON_BOOT+--pbkdf argon2id} "$I" -
    fi
    cryptsetup luksOpen --key-file "${KEYFILE}" "$I" "${I##*\/}"
    INDEX=$((INDEX+1))
done

# EFI system partition
ALPHABET=({A..Z})
tmpCount=0
# shellcheck disable=SC2046
find $(getPartitions 1) | while read -r I; do
    mkfs.vfat -n "EFI${ALPHABET[tmpCount++]}" -F 32 "$I"
done

# boot partition
mkfs.btrfs --checksum blake2 --label boot "/dev/mapper/${BOOT_PARTITION##*\/}"

# rescue partition
mkfs.btrfs --checksum blake2 --label rescue "/dev/mapper/${RESCUE_PARTITION##*\/}"

# swap partition
# shellcheck disable=SC2046
if [ ${#DISKS[@]} -eq 1 ]; then
    SWAP_PARTITION="$(getMapperPartitions 4)"
else
    SWAP_PARTITION="/dev/md2"
    mdadm --create "${SWAP_PARTITION}" --level="${RAID:-1}" --raid-devices=${#DISKS[@]} --metadata=default $(getMapperPartitions 4)
fi
mkswap --label swap "${SWAP_PARTITION}"
swapon "${SWAP_PARTITION}"

# system partition
# shellcheck disable=SC2046
mkfs.btrfs --data "${BTRFS_RAID_DATA}" --metadata "${BTRFS_RAID_METADATA}" --checksum blake2 --label system $(getMapperPartitions 5)

if [ ! -d /mnt/gentoo ]; then
    mkdir /mnt/gentoo
fi

# shellcheck disable=SC2046
mount -o noatime $(getMapperPartitions 5 | awk '{print $1}') /mnt/gentoo
btrfs subvolume create /mnt/gentoo/@distfiles; sync
btrfs subvolume create /mnt/gentoo/@home; sync
btrfs subvolume create /mnt/gentoo/@portage; sync
btrfs subvolume create /mnt/gentoo/@root; sync
umount /mnt/gentoo
# shellcheck disable=SC2046
mount -o noatime,subvol=@root $(getMapperPartitions 5 | awk '{print $1}') /mnt/gentoo
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
ln -s "/dev/mapper/${RESCUE_PARTITION##*\/}" /mnt/gentoo/mapperRescue
ln -s "${SWAP_PARTITION}" /mnt/gentoo/mapperSwap
ln -s "$(getMapperPartitions 5 | awk '{print $1}')" /mnt/gentoo/mapperSystem
tmpCount=0
# shellcheck disable=SC2046
find $(getPartitions 1) | while read -r I; do
    ln -s "$I" "/mnt/gentoo/devEfi${ALPHABET[tmpCount++]}"
done
ln -s "$(awk '{print $1}' <<<"${BOOT_PARTITION}")" "/mnt/gentoo/devBoot"
ln -s "$(awk '{print $1}' <<<"${RESCUE_PARTITION}")" "/mnt/gentoo/devRescue"
tmpCount=0
# shellcheck disable=SC2046
find $(getPartitions 4) | while read -r I; do
    ln -s "$I" "/mnt/gentoo/devSwap${ALPHABET[tmpCount++]}"
done
tmpCount=0
# shellcheck disable=SC2046
find $(getPartitions 5) | while read -r I; do
    ln -s "$I" "/mnt/gentoo/devSystem${ALPHABET[tmpCount++]}"
done

echo $?
