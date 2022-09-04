#!/usr/bin/env bash

# Prevent tainting variables via environment
# See: https://gist.github.com/duxsco/fad211d5828e09d0391f018834f955c9
unset alphabet btrfs_raid disk disks fallback_password index luks_device luks_password partition pbkdf raid rescue_partition rescue_password short_uuid swap_partition swap_size system_size token_id token_type

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
"-e": specifies EFI System Partition size in MiB (default: 512 MiB; recommended minimum: 260 MiB).
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

efi_system_partition_size="512"
rescue_partition_size="2048"

# shellcheck disable=SC2207
while getopts 56b:d:e:f:i:r:s:th opt; do
    case $opt in
        5) setRaid 5;;
        6) setRaid 6;;
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
        "mklabel gpt" \
        "unit MiB" \
        "mkpart esp31415part 1 $((1 + efi_system_partition_size))" \
        "mkpart rescue31415part $((1 + efi_system_partition_size)) $((1 + efi_system_partition_size + rescue_partition_size))" \
        "mkpart swap31415part $((1 + efi_system_partition_size + rescue_partition_size)) $((1 + efi_system_partition_size + rescue_partition_size + swap_size))" \
        "mkpart system31415part $((1 + efi_system_partition_size + rescue_partition_size + swap_size)) ${system_size}" \
        "set 1 esp on"
done

# rescue partition
if [[ ${#disks[@]} -eq 1 ]]; then
    rescue_partition="$(getPartitions 2)"
else
    rescue_partition="/dev/md0"
    # shellcheck disable=SC2046
    mdadm --create "${rescue_partition}" --name rescue31415md --level=1 --raid-devices=${#disks[@]} --metadata=default $(getPartitions 2)
fi

# encrypt rescue, swap and system partitions
index=0
# shellcheck disable=SC2046
while read -r partition; do
    if [[ ${index} -eq 0 ]]; then
        luks_password="${rescue_password}"
    else
        luks_password="${fallback_password}"
    fi

    # shellcheck disable=SC2086
    echo -n "${luks_password}" | cryptsetup --batch-mode luksFormat --hash sha512 --cipher aes-xts-plain64 --key-size 512 --use-random --pbkdf argon2id "${partition}"
    echo -n "${luks_password}" | cryptsetup luksOpen "${partition}" "${partition##*\/}"

    index=$((index+1))
done < <(find "${rescue_partition}" $(getPartitions 3) $(getPartitions 4))

# EFI system partition
alphabet=({A..Z})
tmpCount=0
# shellcheck disable=SC2046
while read -r partition; do
    mkfs.vfat -n "EFI${alphabet[tmpCount++]}" -F 32 "${partition}"
done < <(find $(getPartitions 1))

# rescue partition
mkfs.btrfs --quiet --csum xxhash --label rescue31415fs "/dev/mapper/${rescue_partition##*\/}"

# swap partition
# shellcheck disable=SC2046
if [ ${#disks[@]} -eq 1 ]; then
    swap_partition="$(getMapperPartitions 3)"
else
    swap_partition="/dev/md1"
    mdadm --create "${swap_partition}" --name swap31415md --level="${raid:-1}" --raid-devices=${#disks[@]} --metadata=default $(getMapperPartitions 3)
fi
mkswap --label swap31415fs "${swap_partition}"
swapon "${swap_partition}"

# system partition
# shellcheck disable=SC2046
mkfs.btrfs --quiet --csum xxhash --data "${btrfs_raid}" --metadata "${btrfs_raid}" --label system31415fs $(getMapperPartitions 4)

if [ ! -d /mnt/gentoo ]; then
    mkdir /mnt/gentoo
fi

# shellcheck disable=SC2046
mount -o noatime $(getMapperPartitions 4 | awk '{print $1}') /mnt/gentoo
btrfs subvolume create /mnt/gentoo/@binpkgs; sync
btrfs subvolume create /mnt/gentoo/@distfiles; sync
btrfs subvolume create /mnt/gentoo/@home; sync
btrfs subvolume create /mnt/gentoo/@ebuilds; sync
btrfs subvolume create /mnt/gentoo/@root; sync
btrfs subvolume create /mnt/gentoo/@var_tmp; sync
umount /mnt/gentoo
# shellcheck disable=SC2046
mount -o noatime,subvol=@root $(getMapperPartitions 4 | awk '{print $1}') /mnt/gentoo

useradd -m -s /bin/bash meh
chown meh: /mnt/gentoo /tmp/fetch_files.sh
chmod u+x /tmp/fetch_files.sh
su -l meh -c /tmp/fetch_files.sh
chown -R root: /mnt/gentoo

alphabet=({a..z})
ln -s "/dev/mapper/${rescue_partition##*\/}" /mnt/gentoo/mapperRescue
ln -s "${swap_partition}" /mnt/gentoo/mapperSwap
ln -s "$(getMapperPartitions 4 | awk '{print $1}')" /mnt/gentoo/mapperSystem
tmpCount=0
# shellcheck disable=SC2046
while read -r partition; do
    ln -s "${partition}" "/mnt/gentoo/devEfi${alphabet[tmpCount++]}"
done < <(find $(getPartitions 1))
ln -s "$(awk '{print $1}' <<<"${rescue_partition}")" "/mnt/gentoo/devRescue"
tmpCount=0
# shellcheck disable=SC2046
while read -r partition; do
    ln -s "${partition}" "/mnt/gentoo/devSwap${alphabet[tmpCount++]}"
done < <(find $(getPartitions 3))
tmpCount=0
# shellcheck disable=SC2046
while read -r partition; do
    ln -s "${partition}" "/mnt/gentoo/devSystem${alphabet[tmpCount++]}"
done < <(find $(getPartitions 4))

cat <<EOF > /tmp/chroot.sh
#!/usr/bin/env bash

function luksOpen() {
    short_uuid="\$(tr -d '-' <<<"\$1")"

    if [[ ! -e \$(find /dev/disk/by-id -maxdepth 1 -name "dm-uuid-*\${short_uuid}*") ]]; then
        declare -a token_type
        token_id=0

        while cryptsetup token export --token-id "\${token_id}" "/dev/disk/by-uuid/\$1" >/dev/null 2>&1; do
            token_type+=( "\$(cryptsetup token export --token-id "\${token_id}" "/dev/disk/by-uuid/\$1" | jq -r '.type')" )
            ((token_id++))
        done

        if [[ " \${token_type[*]} " =~ " systemd-tpm2 " ]]; then
            /usr/lib/systemd/systemd-cryptsetup attach "\$1" "/dev/disk/by-uuid/\$1" - tpm2-device=auto
        fi

        if  [[ ! -e \$(find /dev/disk/by-id -maxdepth 1 -name "dm-uuid-*\${short_uuid}*") ]] && \
            [[ " \${token_type[*]} " =~ " clevis " ]]; then
            clevis luks unlock -d "/dev/disk/by-uuid/\$1"
        fi

        if [[ ! -e \$(find /dev/disk/by-id -maxdepth 1 -name "dm-uuid-*\${short_uuid}*") ]]; then
            echo "Failed to open LUKS device! Aborting..."
            exit 1
        fi
    fi
}

$(
    while read -r luks_device; do
        echo "luksOpen \"$(blkid -s UUID -o value "${luks_device}")\""
    done < <(find /mnt/gentoo/devSystem* /mnt/gentoo/devSwap*)
)

if [[ ! -d /mnt/gentoo ]]; then
    mkdir /mnt/gentoo
    mount -o noatime,subvol=@root UUID="$(blkid -s UUID -o value /mnt/gentoo/mapperSystem)" /mnt/gentoo/

    if ! mountpoint --quiet /mnt/gentoo; then
        echo "Failed to mount /mnt/gentoo! Aborting..."
        exit 1
    fi
fi

grep -E "^(UUID|tmpfs)" /mnt/gentoo/etc/fstab | sed -e '/subvol=@root/d' -e 's|/|/mnt/gentoo/|' -e 's/,rootcontext=[^[:space:]]*//' | column -t > /etc/fstab
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

if ! mountpoint --quiet /mnt/gentoo/tmp; then
    mount -t tmpfs -o noatime,nodev,nosuid,mode=1777,uid=0,gid=0 tmpfs /mnt/gentoo/tmp
fi

if [[ ! -d /run/systemd/resolve ]]; then
    mkdir /run/systemd/resolve
    cp --dereference /etc/resolv.conf /run/systemd/resolve/resolv.conf
fi

chroot /mnt/gentoo /usr/bin/env chrooted=true bash
EOF
