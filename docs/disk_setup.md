## 3.1. Wiping Disks

`disk.sh` expects the disks, where you want to install Gentoo Linux on, to be completely empty.

If you use SSD(s) I recommend a [Secure Erase](https://wiki.archlinux.org/title/Solid_state_drive/Memory_cell_clearing). Alternatively, you can do a fast wipe the following way given that no LUKS, MDADM, SWAP etc. device is open on the disk:

```shell
# Change disk name to the one you want to wipe
disk="/dev/sda"
lsblk -npo kname "${disk}" | grep "^${disk}" | sort -r | while read -r i; do wipefs -a "$i"; done
```

!!! tip
    If you have confidential data stored in a non-encrypted way and don't want to risk the data landing in foreign hands I recommend the use of something like `dd`, e.g. [https://wiki.archlinux.org/title/Securely_wipe_disk](https://wiki.archlinux.org/title/Securely_wipe_disk)!

## 3.2. Partitioning And Formating

Prepare the disks (copy&paste one after the other):

```shell
bash /tmp/disk.sh -h

# disable bash history
set +o history

# adjust to your liking
bash /tmp/disk.sh -f fallbackfallback -r rescuerescue -d "/dev/sda /dev/sdb etc." -s 12

# enable bash history
set -o history
```

`disk.sh` creates user "meh" which will be used later on to act as non-root.

## 3.3. /mnt/gentoo Content

Result of a single disk setup:

```shell
❯ tree -a /mnt/gentoo/
/mnt/gentoo/
├── devEfia -> /dev/sda1
├── devRescue -> /dev/sda2
├── devSwapa -> /dev/sda3
├── devSystema -> /dev/sda4
├── mapperRescue -> /dev/mapper/sda2
├── mapperSwap -> /dev/mapper/sda3
├── mapperSystem -> /dev/mapper/sda4
├── portage-latest.tar.xz
├── portage-latest.tar.xz.gpgsig
├── stage3-amd64-systemd-20220529T170531Z.tar.xz
└── stage3-amd64-systemd-20220529T170531Z.tar.xz.asc

0 directories, 13 files
```

Result of the four disk setup:

```shell
❯ tree -a /mnt/gentoo/
/mnt/gentoo/
├── devEfia -> /dev/sda1
├── devEfib -> /dev/sdb1
├── devEfic -> /dev/sdc1
├── devEfid -> /dev/sdd1
├── devRescue -> /dev/md0
├── devSwapa -> /dev/sda3
├── devSwapb -> /dev/sdb3
├── devSwapc -> /dev/sdc3
├── devSwapd -> /dev/sdd3
├── devSystema -> /dev/sda4
├── devSystemb -> /dev/sdb4
├── devSystemc -> /dev/sdc4
├── devSystemd -> /dev/sdd4
├── mapperRescue -> /dev/mapper/md0
├── mapperSwap -> /dev/md1
├── mapperSystem -> /dev/mapper/sda4
├── portage-latest.tar.xz
├── portage-latest.tar.xz.gpgsig
├── stage3-amd64-systemd-20220529T170531Z.tar.xz
└── stage3-amd64-systemd-20220529T170531Z.tar.xz.asc

0 directories, 25 files
```

## 3.4. Tarball Extraction

!!! info 
    Current `stage3-amd64-systemd-*.tar.xz` is downloaded by default. Download and extract your stage3 flavour if it fits your needs more, but choose a systemd flavour of stage3, because this is required later on. Check the official handbook for the steps to be taken, especially in regards to verification.

Extract stage3 tarball and copy `firewall.nft`:

```shell
tar -C /mnt/gentoo/ -xpvf /mnt/gentoo/stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner && \
rsync -a --numeric-ids --chown=0:0 --chmod=u=rwx,go=r /tmp/firewall.nft /mnt/gentoo/usr/local/sbin/ && \
rsync -a /tmp/{portage_hook_kernel,localrepo} /mnt/gentoo/root/ && \
mkdir -p /mnt/gentoo/etc/gentoo-installation; echo $?
```

Extract portage tarball:

```shell
mkdir /mnt/gentoo/var/db/repos/gentoo && \
touch /mnt/gentoo/var/db/repos/gentoo/.keep && \
mount -o noatime,subvol=@ebuilds /mnt/gentoo/mapperSystem /mnt/gentoo/var/db/repos/gentoo && \
tar --transform 's/^portage/gentoo/' -C /mnt/gentoo/var/db/repos/ -xvpJf /mnt/gentoo/portage-latest.tar.xz; echo $?
```

## 3.5. Mounting

```shell
mount -t tmpfs -o noatime,nodev,nosuid,mode=1777,uid=root,gid=root tmpfs /mnt/gentoo/tmp && \
mount --types proc /proc /mnt/gentoo/proc && \
mount --rbind /sys /mnt/gentoo/sys && \
mount --make-rslave /mnt/gentoo/sys && \
mount --rbind /dev /mnt/gentoo/dev && \
mount --make-rslave /mnt/gentoo/dev && \
mount --bind /run /mnt/gentoo/run && \
mount --make-slave /mnt/gentoo/run && \

mount -o noatime,subvol=@home /mnt/gentoo/mapperSystem /mnt/gentoo/home && \

touch /mnt/gentoo/var/cache/binpkgs/.keep && \
mount -o noatime,subvol=@binpkgs /mnt/gentoo/mapperSystem /mnt/gentoo/var/cache/binpkgs && \

touch /mnt/gentoo/var/cache/distfiles/.keep && \
mount -o noatime,subvol=@distfiles /mnt/gentoo/mapperSystem /mnt/gentoo/var/cache/distfiles && \

touch /mnt/gentoo/var/tmp/.keep && \
mount -o noatime,subvol=@var_tmp /mnt/gentoo/mapperSystem /mnt/gentoo/var/tmp && \
chmod 1777 /mnt/gentoo/var/tmp; echo $?
```
