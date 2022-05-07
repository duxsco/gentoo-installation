#!/usr/bin/env bash

# Prevent tainting variables via environment
# See: https://gist.github.com/duxsco/fad211d5828e09d0391f018834f955c9
unset alphabet boot_partition boot_password btrfs_raid disk disks index keyfile master_password partition pbkdf raid rescue_partition rescue_password swap_partition swap_size system_size

function help() {
cat <<EOF
${0##*\/} -b BootPassword -m MasterPassword -r RescuePassword -d "/dev/sda /dev/sdb /dev/sdc" -s SwapSizeInGibibyte
OR
${0##*\/} -b BootPassword -m MasterPassword -r RescuePassword -d "/dev/nvme0n1 /dev/nvme1n1 /dev/nvme2n1" -s SwapSizeInGibibyte

"-d" specifies the disks you want to use for installation.
They should be of the same type and size. Don't mix HDDs with SSDs!

By default, RAID 1 is used for multi-disk setups.
This can be changed for "swap" partitions:
"-5": Create RAID 5 devices which require >=3 disks.
"-6": Create RAID 6 devices which require >=4 disks.
"-t": Create RAID 10 devices which require >=4+2*x disks with x being a non-negative integer.

Further optional flags:
"-e": specifies EFI System Partition size in MiB (default and recommended minimum: 260 MiB).
"-f": specifies /boot partition size in MiB (default: 512 MiB).
"-i": specifies SystemRescueCD partition size in MiB (default: 2048 MiB; recommended minimum: 1024 MiB)
EOF
}

function getPartitions() {
    for disk in "${disks[@]}"; do
        ls "${disk}"*"$1"
    done | xargs
}

function getMapperPartitions() {
    for disk in "${disks[@]}"; do
        ls "${disk/\/dev\//\/dev\/mapper\/}"*"$1"
    done | xargs
}

function setRaid() {
    if [[ -z ${raid} ]]; then
        raid="$1"
    else
        help
        exit 1
    fi
}

efi_system_partition_size="260"
boot_partition_size="512"
rescue_partition_size="2048"

# shellcheck disable=SC2207
while getopts 56b:d:e:f:i:m:r:s:th opt; do
    case $opt in
        5) setRaid 5;;
        6) setRaid 6;;
        b) boot_password="$OPTARG";;
        d) disks=( $(xargs <<<"$OPTARG" | tr ' ' '\n' | sort | xargs) );;
        e) efi_system_partition_size="$OPTARG";;
        f) boot_partition_size="$OPTARG";;
        i) rescue_partition_size="$OPTARG";;
        m) master_password="$OPTARG";;
        r) rescue_password="$OPTARG";;
        s) swap_size="$((OPTARG * 1024))";;
        t) setRaid 10;;
        h) help; exit 0;;
        ?) help; exit 1;;
    esac
done

# shellcheck disable=SC2068
if { [[ -n ${raid} ]] && [[ ${raid} -eq 5  ]] && [[ ${#disks[@]} -lt 3 ]]; } || \
   { [[ -n ${raid} ]] && [[ ${raid} -eq 6  ]] && [[ ${#disks[@]} -lt 4 ]]; } || \
   { [[ -n ${raid} ]] && [[ ${raid} -eq 10 ]] && [[ ${#disks[@]} -lt 4 ]]; } || \
   { [[ -n ${raid} ]] && [[ ${raid} -eq 10 ]] && [[ $((${#disks[@]}%2)) -ne 0 ]]; } || \
   [[ -z ${boot_password} ]] || [[ ${#disks[@]} -eq 0 ]] || [[ -z ${master_password} ]] || \
   [[ -z ${rescue_password} ]] || [[ -z ${swap_size} ]] || ! ls ${disks[@]} >/dev/null 2>&1; then
    help
    exit 1
fi

case ${#disks[@]} in
    1) btrfs_raid="single";;
    2) btrfs_raid="raid1";;
    3) btrfs_raid="raid1c3";;
    *) btrfs_raid="raid1c4";;
esac

# create keyfile
keyfile="$(umask 0377 && mktemp)"
dd bs=512 count=16384 iflag=fullblock if=/dev/random of="${keyfile}"

# partition
for disk in "${disks[@]}"; do

    if [ $((512*$(<"/sys/class/block/${disk##*\/}/size"))) -gt 536870912000 ]; then
        system_size="-5119"
    else
        system_size="99%"
    fi

    parted --align optimal --script "${disk}" \
        mklabel gpt \
        unit MiB \
        "mkpart 'esp3141592653part' 1 $((1 + efi_system_partition_size))" \
        mkpart boot3141592653part $((1 + efi_system_partition_size)) $((1 + efi_system_partition_size + boot_partition_size)) \
        mkpart rescue3141592653part $((1 + efi_system_partition_size + boot_partition_size)) $((1 + efi_system_partition_size + boot_partition_size + rescue_partition_size)) \
        mkpart swap3141592653part $((1 + efi_system_partition_size + boot_partition_size + rescue_partition_size)) $((1 + efi_system_partition_size + boot_partition_size + rescue_partition_size + swap_size)) \
        "mkpart system3141592653part $((1 + efi_system_partition_size + boot_partition_size + rescue_partition_size + swap_size)) ${system_size}" \
        set 1 esp on
done

# boot partition
if [[ ${#disks[@]} -eq 1 ]]; then
    boot_partition="$(getPartitions 2)"
else
    boot_partition="/dev/md0"
    # shellcheck disable=SC2046
    mdadm --create "${boot_partition}" --name boot3141592653md --level=1 --raid-devices=${#disks[@]} --metadata=default $(getPartitions 2)
fi

# rescue partition
if [[ ${#disks[@]} -eq 1 ]]; then
    rescue_partition="$(getPartitions 3)"
else
    rescue_partition="/dev/md1"
    # shellcheck disable=SC2046
    mdadm --create "${rescue_partition}" --name rescue3141592653md --level=1 --raid-devices=${#disks[@]} --metadata=default $(getPartitions 3)
fi

# encrypting boot, swap and system partitions
pbkdf="--pbkdf pbkdf2"
index=0
# shellcheck disable=SC2046
while read -r partition; do
    if [[ ${index} -eq 2 ]]; then
        unset pbkdf
    fi
    # shellcheck disable=SC2086
    cryptsetup --batch-mode luksFormat --hash sha512 --cipher aes-xts-plain64 --key-size 512 --key-file "${keyfile}" --use-random ${pbkdf:---pbkdf argon2id} "${partition}"
    if [[ ${index} -eq 1 ]]; then
        # shellcheck disable=SC2086
        echo -n "${rescue_password}" | cryptsetup luksAddKey --hash sha512 --key-file "${keyfile}" ${pbkdf:---pbkdf argon2id} "${partition}" -
    else
        # shellcheck disable=SC2086
        echo -n "${master_password}" | cryptsetup luksAddKey --hash sha512 --key-file "${keyfile}" ${pbkdf:---pbkdf argon2id} "${partition}" -
        # shellcheck disable=SC2086
        echo -n "${boot_password}"   | cryptsetup luksAddKey --hash sha512 --key-file "${keyfile}" ${pbkdf:---pbkdf argon2id} "${partition}" -
    fi
    cryptsetup luksOpen --key-file "${keyfile}" "${partition}" "${partition##*\/}"
    index=$((index+1))
done < <(find "${boot_partition}" "${rescue_partition}" $(getPartitions 4) $(getPartitions 5))

# EFI system partition
alphabet=({A..Z})
tmpCount=0
# shellcheck disable=SC2046
while read -r partition; do
    mkfs.vfat -n "EFI${alphabet[tmpCount++]}" -F 32 "${partition}"
done < <(find $(getPartitions 1))

# boot partition
mkfs.btrfs --checksum blake2 --label boot3141592653fs "/dev/mapper/${boot_partition##*\/}"

# rescue partition
mkfs.btrfs --checksum blake2 --label rescue3141592653fs "/dev/mapper/${rescue_partition##*\/}"

# swap partition
# shellcheck disable=SC2046
if [ ${#disks[@]} -eq 1 ]; then
    swap_partition="$(getMapperPartitions 4)"
else
    swap_partition="/dev/md2"
    mdadm --create "${swap_partition}" --name swap3141592653md --level="${raid:-1}" --raid-devices=${#disks[@]} --metadata=default $(getMapperPartitions 4)
fi
mkswap --label swap3141592653fs "${swap_partition}"
swapon "${swap_partition}"

# system partition
# shellcheck disable=SC2046
mkfs.btrfs --data "${btrfs_raid}" --metadata "${btrfs_raid}" --checksum blake2 --label system3141592653fs $(getMapperPartitions 5)

if [ ! -d /mnt/gentoo ]; then
    mkdir /mnt/gentoo
fi

# shellcheck disable=SC2046
mount -o noatime $(getMapperPartitions 5 | awk '{print $1}') /mnt/gentoo
btrfs subvolume create /mnt/gentoo/@binpkgs; sync
btrfs subvolume create /mnt/gentoo/@distfiles; sync
btrfs subvolume create /mnt/gentoo/@home; sync
btrfs subvolume create /mnt/gentoo/@ebuilds; sync
btrfs subvolume create /mnt/gentoo/@root; sync
umount /mnt/gentoo
# shellcheck disable=SC2046
mount -o noatime,subvol=@root $(getMapperPartitions 5 | awk '{print $1}') /mnt/gentoo
mkdir -p /mnt/gentoo/etc/gentoo-installation/keyfile/mnt/key
rsync -a "${keyfile}" /mnt/gentoo/etc/gentoo-installation/keyfile/mnt/key/key
sync
cmp "${keyfile}" /mnt/gentoo/etc/gentoo-installation/keyfile/mnt/key/key
rm -f "${keyfile}"

useradd -m -s /bin/bash meh
chown meh: /mnt/gentoo /tmp/fetch_files.sh
chmod u+x /tmp/fetch_files.sh
su -l meh -c /tmp/fetch_files.sh
chown -R root: /mnt/gentoo

alphabet=({a..z})
ln -s "/dev/mapper/${boot_partition##*\/}" /mnt/gentoo/mapperBoot
ln -s "/dev/mapper/${rescue_partition##*\/}" /mnt/gentoo/mapperRescue
ln -s "${swap_partition}" /mnt/gentoo/mapperSwap
ln -s "$(getMapperPartitions 5 | awk '{print $1}')" /mnt/gentoo/mapperSystem
tmpCount=0
# shellcheck disable=SC2046
while read -r partition; do
    ln -s "${partition}" "/mnt/gentoo/devEfi${alphabet[tmpCount++]}"
done < <(find $(getPartitions 1))
ln -s "$(awk '{print $1}' <<<"${boot_partition}")" "/mnt/gentoo/devBoot"
ln -s "$(awk '{print $1}' <<<"${rescue_partition}")" "/mnt/gentoo/devRescue"
tmpCount=0
# shellcheck disable=SC2046
while read -r partition; do
    ln -s "${partition}" "/mnt/gentoo/devSwap${alphabet[tmpCount++]}"
done < <(find $(getPartitions 4))
tmpCount=0
# shellcheck disable=SC2046
while read -r partition; do
    ln -s "${partition}" "/mnt/gentoo/devSystem${alphabet[tmpCount++]}"
done < <(find $(getPartitions 5))

echo $?
