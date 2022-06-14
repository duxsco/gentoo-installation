#!/usr/bin/env bash

# Prevent tainting variables via environment
# See: https://gist.github.com/duxsco/fad211d5828e09d0391f018834f955c9
unset alphabet boot_partition btrfs_raid disk disks fallback_password index luks_device luks_device_name luks_device_uuid luks_password partition raid rescue_partition rescue_password swap_partition swap_size system_size

function help() {
cat <<EOF
${0##*\/} -f FallbackPassword -r RescuePassword -d "/dev/sda /dev/sdb /dev/sdc" -s SwapSizeInGibibyte
OR
${0##*\/} -f FallbackPassword -r RescuePassword -d "/dev/nvme0n1 /dev/nvme1n1 /dev/nvme2n1" -s SwapSizeInGibibyte

"-d" specifies the disks you want to use for installation.
They should be of the same type and size. Don't mix HDDs with SSDs!

By default, RAID 1 is used for multi-disk setups.
This can be changed for "swap" partitions:
"-5": Create RAID 5 devices which require >=3 disks.
"-6": Create RAID 6 devices which require >=4 disks.
"-t": Create RAID 10 devices which require >=4+2*x disks with x being a non-negative integer.

Further optional flags:
"-e": specifies EFI System Partition size in MiB (default and recommended minimum: 260 MiB).
"-b": specifies /boot partition size in MiB (default: 512 MiB).
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
while getopts 56b:d:e:f:i:r:s:th opt; do
    case $opt in
        5) setRaid 5;;
        6) setRaid 6;;
        b) boot_partition_size="$OPTARG";;
        d) disks=( $(xargs <<<"$OPTARG" | tr ' ' '\n' | sort | xargs) );;
        e) efi_system_partition_size="$OPTARG";;
        f) fallback_password="$OPTARG";;
        i) rescue_partition_size="$OPTARG";;
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
   [[ -z ${fallback_password} ]] || [[ ${#disks[@]} -eq 0 ]] || \
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
boot_partition="$(getPartitions 2)"

# rescue partition
if [[ ${#disks[@]} -eq 1 ]]; then
    rescue_partition="$(getPartitions 3)"
else
    rescue_partition="/dev/md0"
    # shellcheck disable=SC2046
    mdadm --create "${rescue_partition}" --name rescue3141592653md --level=1 --raid-devices=${#disks[@]} --metadata=default $(getPartitions 3)
fi

# encrypting boot, swap and system partitions
index=0
# shellcheck disable=SC2046
while read -r partition; do
    if [[ ${index} -eq 0 ]]; then
        luks_password="${rescue_password}"
    else
        luks_password"${fallback_password}"
    fi

    # shellcheck disable=SC2086
    echo -n "${luks_password}" | cryptsetup --batch-mode luksFormat --hash sha512 --cipher aes-xts-plain64 --key-size 512 --use-random --pbkdf argon2id "${partition}"
    echo -n "${luks_password}" | cryptsetup luksOpen "${partition}" "${partition##*\/}"

    index=$((index+1))
done < <(find "${rescue_partition}" $(getPartitions 4) $(getPartitions 5))

# EFI system partition
alphabet=({A..Z})
tmpCount=0
# shellcheck disable=SC2046
while read -r partition; do
    mkfs.vfat -n "EFI${alphabet[tmpCount++]}" -F 32 "${partition}"
done < <(find $(getPartitions 1))

# boot partition
# shellcheck disable=SC2086
mkfs.btrfs --data "${btrfs_raid}" --metadata "${btrfs_raid}" --label boot3141592653fs ${boot_partition}

# rescue partition
mkfs.btrfs --label rescue3141592653fs "/dev/mapper/${rescue_partition##*\/}"

# swap partition
# shellcheck disable=SC2046
if [ ${#disks[@]} -eq 1 ]; then
    swap_partition="$(getMapperPartitions 4)"
else
    swap_partition="/dev/md1"
    mdadm --create "${swap_partition}" --name swap3141592653md --level="${raid:-1}" --raid-devices=${#disks[@]} --metadata=default $(getMapperPartitions 4)
fi
mkswap --label swap3141592653fs "${swap_partition}"
swapon "${swap_partition}"

# system partition
# shellcheck disable=SC2046
mkfs.btrfs --data "${btrfs_raid}" --metadata "${btrfs_raid}" --label system3141592653fs $(getMapperPartitions 5)

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

useradd -m -s /bin/bash meh
chown meh: /mnt/gentoo /tmp/fetch_files.sh
chmod u+x /tmp/fetch_files.sh
su -l meh -c /tmp/fetch_files.sh
chown -R root: /mnt/gentoo

alphabet=({a..z})
ln -s "$(getPartitions 2 | awk '{print $1}')" /mnt/gentoo/mapperBoot
ln -s "/dev/mapper/${rescue_partition##*\/}" /mnt/gentoo/mapperRescue
ln -s "${swap_partition}" /mnt/gentoo/mapperSwap
ln -s "$(getMapperPartitions 5 | awk '{print $1}')" /mnt/gentoo/mapperSystem
tmpCount=0
# shellcheck disable=SC2046
while read -r partition; do
    ln -s "${partition}" "/mnt/gentoo/devEfi${alphabet[tmpCount++]}"
done < <(find $(getPartitions 1))
tmpCount=0
# shellcheck disable=SC2046
while read -r partition; do
    ln -s "${partition}" "/mnt/gentoo/devBoot${alphabet[tmpCount++]}"
done < <(find $(getPartitions 2))
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

cat <<EOF > /tmp/chroot.sh
#!/usr/bin/env bash

function luksOpen() {
    luks_device_name="\$1"
    luks_device_uuid="\$2"

    if [[ ! -b /dev/mapper/\${luks_device_name} ]]; then

        if [[ -f /mnt/gentoo/etc/gentoo-installation/keyfile/mnt/key/key ]]; then
            cryptsetup luksOpen --key-file /mnt/gentoo/etc/gentoo-installation/keyfile/mnt/key/key UUID="\${luks_device_uuid}" "\${luks_device_name}"
        else
            cryptsetup luksOpen UUID="\${luks_device_uuid}" "\${luks_device_name}"
        fi

        if [[ ! -b /dev/mapper/\${luks_device_name} ]]; then
            echo "Failed to luksOpen device! Aborting..."
            exit 1
        fi
    fi
}

$(
    while read -r luks_device; do
        luks_device_uuid="$(blkid -s UUID -o value "${luks_device}")"

        # shellcheck disable=SC2001
        luks_device_name="$(sed 's|/mnt/gentoo/dev||' <<<"${luks_device}" | tr '[:upper:]' '[:lower:]')"

        if [[ ${luks_device_name} =~ ^(swap|swapa)$ ]]; then
            echo "
if [[ ! -d /mnt/gentoo ]]; then
    mkdir /mnt/gentoo
fi

if ! mountpoint --quiet /mnt/gentoo; then
    mount -o noatime,subvol=@root UUID=\"$(blkid -s UUID -o value /mnt/gentoo/mapperSystem)\" /mnt/gentoo/

    if ! mountpoint --quiet /mnt/gentoo; then
        echo \"Failed to mount /mnt/gentoo! Aborting...\"
        exit 1
    fi
fi
"
        fi

        echo "luksOpen \"${luks_device_name}\" \"${luks_device_uuid}\""
    done < <(find /mnt/gentoo/devSystem* /mnt/gentoo/devSwap*)
)

grep -E "^(UUID|tmpfs)" /mnt/gentoo/etc/fstab | sed -e '/subvol=@root/d' -e 's|/|/mnt/gentoo/|' -e 's/,noauto//' -e 's/,rootcontext=[^[:space:]]*//' -e 's/=root/=0/g' -e 's/=portage/=250/g' | column -t > /etc/fstab
systemctl daemon-reload
mount -a
swapon -a

if ! mountpoint --quiet /mnt/gentoo/proc; then
    mount --types proc /proc /mnt/gentoo/proc
fi

if ! mountpoint --quiet /mnt/gentoo/sys; then
    mount --rbind /sys /mnt/gentoo/sys
    mount --make-rslave /mnt/gentoo/sys
fi

if ! mountpoint --quiet /mnt/gentoo/dev; then
    mount --rbind /dev /mnt/gentoo/dev
    mount --make-rslave /mnt/gentoo/dev
fi

if ! mountpoint --quiet /mnt/gentoo/run; then
    mount --bind /run /mnt/gentoo/run
    mount --make-slave /mnt/gentoo/run
fi

if [[ ! -d /run/systemd/resolve ]]; then
    mkdir /run/systemd/resolve
fi

cp --dereference /etc/resolv.conf /run/systemd/resolve/resolv.conf

chroot /mnt/gentoo /usr/bin/env chrooted=true bash
EOF
