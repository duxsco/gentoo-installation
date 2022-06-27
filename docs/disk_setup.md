## 3.1. Wiping Disks

`disk.sh` expects the disks, where you want to install Gentoo Linux on, to be completely empty.

If you use SSD(s) I recommend a [Secure Erase](https://wiki.archlinux.org/title/Solid_state_drive/Memory_cell_clearing). Alternatively, you can do a fast wipe the following way given that no LUKS, MDADM, SWAP etc. device is open on the disk:

```bash
# Change disk name to the one you want to wipe
disk="/dev/sda"
lsblk -npo kname "${disk}" | grep "^${disk}" | sort -r | while read -r i; do wipefs -a "$i"; done
```

!!! tip
    If you have confidential data stored in a non-encrypted way and don't want to risk the data landing in foreign hands I recommend the use of something like `dd`, e.g. [https://wiki.archlinux.org/title/Securely_wipe_disk](https://wiki.archlinux.org/title/Securely_wipe_disk)!

## 3.2. Partitioning And Formating

Prepare the disks (copy&paste one after the other):

```bash
bash /tmp/disk.sh -h

# disable bash history
set +o history

# adjust to your liking
bash /tmp/disk.sh -f fallbackfallback -r rescuerescue -d "/dev/sda /dev/sdb etc." -s 12

# enable bash history
set -o history
```

`disk.sh` creates user "meh" which will be used later on to act as non-root.

### 3.2.1. Internal ESP(s)

Result of a single disk setup:

```bash
➤ tree -a /mnt/gentoo/
/mnt/gentoo/
├── devBoota -> /dev/sda2
├── devEfia -> /dev/sda1
├── devRescue -> /dev/sda3
├── devSwapa -> /dev/sda4
├── devSystema -> /dev/sda5
├── mapperBoot -> /dev/sda2
├── mapperRescue -> /dev/mapper/sda3
├── mapperSwap -> /dev/mapper/sda4
├── mapperSystem -> /dev/mapper/sda5
├── portage-latest.tar.xz
├── portage-latest.tar.xz.gpgsig
├── stage3-amd64-systemd-20220529T170531Z.tar.xz
└── stage3-amd64-systemd-20220529T170531Z.tar.xz.asc

0 directories, 13 files
```

Result of the four disk setup:

```bash
➤ tree -a /mnt/gentoo/
/mnt/gentoo/
├── devBoota -> /dev/sda2
├── devBootb -> /dev/sdb2
├── devBootc -> /dev/sdc2
├── devBootd -> /dev/sdd2
├── devEfia -> /dev/sda1
├── devEfib -> /dev/sdb1
├── devEfic -> /dev/sdc1
├── devEfid -> /dev/sdd1
├── devRescue -> /dev/md0
├── devSwapa -> /dev/sda4
├── devSwapb -> /dev/sdb4
├── devSwapc -> /dev/sdc4
├── devSwapd -> /dev/sdd4
├── devSystema -> /dev/sda5
├── devSystemb -> /dev/sdb5
├── devSystemc -> /dev/sdc5
├── devSystemd -> /dev/sdd5
├── mapperBoot -> /dev/sda2
├── mapperRescue -> /dev/mapper/md0
├── mapperSwap -> /dev/md1
├── mapperSystem -> /dev/mapper/sda5
├── portage-latest.tar.xz
├── portage-latest.tar.xz.gpgsig
├── stage3-amd64-systemd-20220529T170531Z.tar.xz
└── stage3-amd64-systemd-20220529T170531Z.tar.xz.asc

0 directories, 25 files
```

### 3.2.2. External ESP(s)

Result of a single disk setup (`/dev/sda`) with ESP on a single removable media (`/dev/sdb`):

```bash
➤ tree -a /mnt/gentoo/
/mnt/gentoo/
├── devBoota -> /dev/sda1
├── devEfia -> /dev/sdb1
├── devRescue -> /dev/sda2
├── devSwapa -> /dev/sda3
├── devSystema -> /dev/sda4
├── mapperBoot -> /dev/sda1
├── mapperRescue -> /dev/mapper/sda2
├── mapperSwap -> /dev/mapper/sda3
├── mapperSystem -> /dev/mapper/sda4
├── portage-latest.tar.xz
├── portage-latest.tar.xz.gpgsig
├── stage3-amd64-systemd-20220612T170541Z.tar.xz
└── stage3-amd64-systemd-20220612T170541Z.tar.xz.asc

0 directories, 13 files
```

Result of a four disk setup (`/dev/sda`, `/dev/sdb`, `/dev/sdc` and `/dev/sdd`) with ESP on two removable media (`/dev/sde` for daily use and `/dev/sdf` as fallback):

```bash
➤ tree -a /mnt/gentoo/
/mnt/gentoo/
├── devBoota -> /dev/sda1
├── devBootb -> /dev/sdb1
├── devBootc -> /dev/sdc1
├── devBootd -> /dev/sdd1
├── devEfia -> /dev/sde1
├── devEfib -> /dev/sdf1
├── devRescue -> /dev/md0
├── devSwapa -> /dev/sda3
├── devSwapb -> /dev/sdb3
├── devSwapc -> /dev/sdc3
├── devSwapd -> /dev/sdd3
├── devSystema -> /dev/sda4
├── devSystemb -> /dev/sdb4
├── devSystemc -> /dev/sdc4
├── devSystemd -> /dev/sdd4
├── mapperBoot -> /dev/sda1
├── mapperRescue -> /dev/mapper/md0
├── mapperSwap -> /dev/md1
├── mapperSystem -> /dev/mapper/sda4
├── portage-latest.tar.xz
├── portage-latest.tar.xz.gpgsig
├── stage3-amd64-systemd-20220612T170541Z.tar.xz
└── stage3-amd64-systemd-20220612T170541Z.tar.xz.asc

0 directories, 23 files
```

## 3.3. Tarball Extraction

!!! info 
    Current `stage3-amd64-systemd-*.tar.xz` is downloaded by default. Download and extract your stage3 flavour if it fits your needs more, but choose a systemd flavour of stage3, because this is required later on. Check the official handbook for the steps to be taken, especially in regards to verification.

Extract stage3 tarball and copy `firewall.nft`:

```bash
tar -C /mnt/gentoo/ -xpvf /mnt/gentoo/stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner && \
rsync -a --numeric-ids --chown=0:0 --chmod=u=rwx,go=r /tmp/firewall.nft /mnt/gentoo/usr/local/sbin/ && \
rsync -a /tmp/{bashrc,localrepo} /mnt/gentoo/root/ && \
mkdir -p /mnt/gentoo/etc/gentoo-installation; echo $?
```

Extract portage tarball:

```bash
mkdir /mnt/gentoo/var/db/repos/gentoo && \
touch /mnt/gentoo/var/db/repos/gentoo/.keep && \
mount -o noatime,subvol=@ebuilds /mnt/gentoo/mapperSystem /mnt/gentoo/var/db/repos/gentoo && \
tar --transform 's/^portage/gentoo/' -C /mnt/gentoo/var/db/repos/ -xvpJf /mnt/gentoo/portage-latest.tar.xz; echo $?
```

## 3.4. Mounting

```bash
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

mount -o noatime /mnt/gentoo/mapperBoot /mnt/gentoo/boot; echo $?
```
