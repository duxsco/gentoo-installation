# Gentoo Linux installation

> ⚠ The installation guide builds heavily on `Secure Boot`. Make sure that the system is in `Setup Mode` in order to be able to add your custom keys. ⚠

The following installation guide results in a **fully encrypted, Secure Boot signed** (EFI binary/binaries) **and GnuPG signed** (kernel, initramfs, microcode etc.) **system** with heavy use of **RAID** (mdadm and BTRFS based) and support for **LUKS unlock**:
- **Locally:** One-time password entry and automatic decryption of LUKS partitions (multiple root and swap partitions) in further boot process via LUKS keyfile stored in initramfs which itself is stored on LUKS encrypted partition(s)
- **Remote:** SSH login into initramfs+dropbear system, manual decryption of LUKS partitions and resumption of Gentoo Linux boot
- After boot into **rescue system** based upon a **customised SystemRescueCD**

After completion of this installation guide, SSH connections will be possible via SSH public key authentication to the:

- Gentoo Linux system: `ssh -p 50022 david@<IP address>`
- Initramfs system to LUKS unlock remotely (further info at the bottom of this page): `ssh -p 50023 david@<IP address`
- Customised SystemRescueCD system: `ssh -p 50024 david@<IP address`

All three boot options are available in GRUB's boot menu.

## Disk layout

The installation steps make use of LUKS encryption wherever possible. Only the EFI System Partitions are not encrypted, but the EFI binaries are Secure Boot signed. Other files, required for booting (e.g. kernel, initramfs), are GnuPG signed. The signature is verified upon boot, and bootup aborts if verification fails.

The number of disks, where Gentoo Linux will be installed, must be less than 5. Depending on the number of disks, BTRFS "single", "raid1", "raid1c3" or "raid1c4" is used for the `system` partition where the Btrfs subvolumes are located (`@root`, `@home` etc.). Furthermore, MDADM RAID 1 may be used for `boot`, `rescue` and `swap` partitions. And, EFI System Partitions each with their own EFI entry are created one for each disk.

- Single disk:

```
PC∕Laptop
└── ∕dev∕sda
    ├── 1. EFI System Partition
    ├── 2. LUKS
    │   └── Btrfs (single)
    │       └── boot
    ├── 3. LUKS
    │   └── Btrfs (single)
    │       └── rescue
    ├── 4. LUKS
    │   └── SWAP
    └── 5. LUKS ("system" partition)
        └── Btrfs (single)
            └── subvolumes
                ├── @distfiles
                ├── @home
                ├── @portage
                └── @root
```

- Two disks:

```
PC∕Laptop──────────────────────────┐
└── ∕dev∕sda                       └── ∕dev∕sdb
    ├── 1. EFI System Partition        ├── 1. EFI System Partition
    ├── 2. MDADM RAID 1                ├── 2. MDADM RAID 1
    │   └── LUKS                       │   └── LUKS
    │       └── Btrfs                  │       └── Btrfs
    │           └── boot               │           └── boot
    ├── 3. MDADM RAID 1                ├── 3. MDADM RAID 1
    │   └── LUKS                       │   └── LUKS
    │       └── Btrfs                  │       └── Btrfs
    │           └── rescue             │           └── rescue
    ├── 4. LUKS                        ├── 4. LUKS
    │   └── MDADM RAID 1               │   └── MDADM RAID 1
    │       └── SWAP                   │       └── SWAP
    └── 5. LUKS ("system" partition)   └── 5. LUKS ("system" partition)
        └── BTRFS (raid1)                  └── BTRFS (raid1)
            └── subvolume                      └── subvolume
                ├── @distfiles                     ├── @distfiles
                ├── @home                          ├── @home
                ├── @portage                       ├── @portage
                └── @root                          └── @root
```

- Three disks:

```
PC∕Laptop──────────────────────────┬──────────────────────────────────┐
└── ∕dev∕sda                       └── ∕dev∕sdb                       └── ∕dev∕sdc
    ├── 1. EFI System Partition        ├── 1. EFI System Partition        ├── 1. EFI System Partition
    ├── 2. MDADM RAID 1                ├── 2. MDADM RAID 1                ├── 2. MDADM RAID 1
    │   └── LUKS                       │   └── LUKS                       │   └── LUKS
    │       └── Btrfs                  │       └── Btrfs                  │       └── Btrfs
    │           └── boot               │           └── boot               │           └── boot
    ├── 3. MDADM RAID 1                ├── 3. MDADM RAID 1                ├── 3. MDADM RAID 1
    │   └── LUKS                       │   └── LUKS                       │   └── LUKS
    │       └── Btrfs                  │       └── Btrfs                  │       └── Btrfs
    │           └── rescue             │           └── rescue             │           └── rescue
    ├── 4. LUKS                        ├── 4. LUKS                        ├── 4. LUKS
    │   └── MDADM RAID 1               │   └── MDADM RAID 1               │   └── MDADM RAID 1
    │       └── SWAP                   │       └── SWAP                   │       └── SWAP
    └── 5. LUKS ("system" partition)   └── 5. LUKS ("system" partition)   └── 5. LUKS ("system" partition)
        └── BTRFS (raid1c3)                └── BTRFS (raid1c3)                └── BTRFS (raid1c3)
            └── subvolume                      └── subvolume                      └── subvolume
                ├── @distfiles                     ├── @distfiles                     ├── @distfiles
                ├── @home                          ├── @home                          ├── @home
                ├── @portage                       ├── @portage                       ├── @portage
                └── @root                          └── @root                          └── @root
```

- Four disks:

```
PC∕Laptop──────────────────────────┬──────────────────────────────────┬──────────────────────────────────┐
└── ∕dev∕sda                       └── ∕dev∕sdb                       └── ∕dev∕sdc                       └── ∕dev∕sdd
    ├── 1. EFI System Partition        ├── 1. EFI System Partition        ├── 1. EFI System Partition        ├── 1. EFI System Partition
    ├── 2. MDADM RAID 1                ├── 2. MDADM RAID 1                ├── 2. MDADM RAID 1                ├── 2. MDADM RAID 1
    │   └── LUKS                       │   └── LUKS                       │   └── LUKS                       │   └── LUKS
    │       └── Btrfs                  │       └── Btrfs                  │       └── Btrfs                  │       └── Btrfs
    │           └── boot               │           └── boot               │           └── boot               │           └── boot
    ├── 3. MDADM RAID 1                ├── 3. MDADM RAID 1                ├── 3. MDADM RAID 1                ├── 3. MDADM RAID 1
    │   └── LUKS                       │   └── LUKS                       │   └── LUKS                       │   └── LUKS
    │       └── Btrfs                  │       └── Btrfs                  │       └── Btrfs                  │       └── Btrfs
    │           └── rescue             │           └── rescue             │           └── rescue             │           └── rescue
    ├── 4. LUKS                        ├── 4. LUKS                        ├── 4. LUKS                        ├── 4. LUKS
    │   └── MDADM RAID 1               │   └── MDADM RAID 1               │   └── MDADM RAID 1               │   └── MDADM RAID 1
    │       └── SWAP                   │       └── SWAP                   │       └── SWAP                   │       └── SWAP
    └── 5. LUKS ("system" partition)   └── 5. LUKS ("system" partition)   └── 5. LUKS ("system" partition)   └── 5. LUKS ("system" partition)
        └── BTRFS (raid1c4)                └── BTRFS (raid1c4)                └── BTRFS (raid1c4)                └── BTRFS (raid1c4)
            └── subvolume                      └── subvolume                      └── subvolume                      └── subvolume
                ├── @distfiles                     ├── @distfiles                     ├── @distfiles                     ├── @distfiles
                ├── @home                          ├── @home                          ├── @home                          ├── @home
                ├── @portage                       ├── @portage                       ├── @portage                       ├── @portage
                └── @root                          └── @root                          └── @root                          └── @root
```

On LUKS encrypted disks except for the `rescue` partition where the SystemRescueCD files are located, LUKS passphrase slots are set as follows:
  - 0: Keyfile (stored in initramfs to unlock `system` and `swap` partitions without interaction)
  - 1: Master password (fallback password for emergency)
  - 2: Boot password
    - shorter than "master", but still secure
    - keyboard layout independent (QWERTY vs QWERTZ)
    - used during boot to unlock `boot` partition via GRUB's password prompt

On the `rescue` partition, LUKS passphrase slots are set as follows:
  - 0: Keyfile
  - 1: Rescue password

The following steps are basically those in [the official Gentoo Linux installation handbook](https://wiki.gentoo.org/wiki/Handbook:AMD64/Full/Installation) with some customisations added.

## Preparing Live-CD environment

In the following, I am using the [SystemRescueCD](https://www.system-rescue.org/), **not** the official Gentoo Linux installation CD. If not otherwise stated, commands are executed on the remote machine where Gentoo Linux needs to be installed, in the beginning via TTY, later on over SSH. Most of the time, you can copy&paste the whole code block, but understand the commands first and make adjustments (e.g. IP address, disk names) if required.

Boot into SystemRescueCD and set the correct keyboard layout:

```bash
loadkeys de-latin1-nodeadkeys
```

Disable `sysrq` for [security sake](https://wiki.gentoo.org/wiki/Vlock#Disable_SysRq_key):

```bash
sysctl -w kernel.sysrq=0
```

Make sure you have booted with EFI:

```bash
[ -d /sys/firmware/efi ] && echo UEFI || echo BIOS
```

Do initial setup (copy&paste one after the other):

```bash
screen -S install

# If no network setup via DHCP done, use nmtui (recommended if DHCP not working) or...
ip a add ...
ip r add default ...
echo nameserver ... > /etc/resolv.conf

# Make sure you have enough entropy for cryptsetup's "--use-random"
pacman -Sy rng-tools
systemctl start rngd

# Insert iptables rules at correct place for SystemRescueCD to accept SSH clients.
# Verify with "iptables -L -v -n"
iptables -I INPUT 4 -p tcp --dport 22 -j ACCEPT -m conntrack --ctstate NEW

# Alternatively, setup /root/.ssh/authorized_keys
passwd root
```

Print out fingerprints to double check upon initial SSH connection to the SystemRescueCD system:

```bash
find /etc/ssh/ -type f -name "ssh_host*\.pub" -exec ssh-keygen -lf {} \;
```

Execute following SCP/SSH commands **on your local machine** (copy&paste one after the other):

```bash
# Copy installation files to remote machine. Adjust port and IP.
rsync -cav {disk.sh,fetch_files.sh,genkernel.sh,boot2efi.sh,firewall_base.sh} root@XXX:/tmp/

# From local machine, login into the remote machine
ssh root@...
```

Resume `screen`:

```bash
screen -d -r install
```

(Optional) Lock the screen on the remote machine by typing the following command on its keyboard (**not over SSH**):

```bash
# Execute "vlock" without any flags first.
# If relogin doesn't work you can switch tty to fix (e.g. set password again).
# If relogin succeeds execute vlock with flag "-a" to lock all tty.
vlock -a
```

Set date if system time is not correct:

```bash
! grep -q "[[:space:]]hypervisor[[:space:]]" <(grep "^flags[[:space:]]*:[[:space:]]*" /proc/cpuinfo) && \
# replace "MMDDhhmmYYYY" with UTC time
date MMDDhhmmYYYY
```

Update hardware clock:

```bash
! grep -q "[[:space:]]hypervisor[[:space:]]" <(grep "^flags[[:space:]]*:[[:space:]]*" /proc/cpuinfo) && \
hwclock --systohc --utc
```

## Disk setup and stage3/portage tarball installation

### Wiping disks

`disk.sh` expects the disks, where you want to install Gentoo Linux on, to be completely empty.

If you use SSD(s) I recommend a [Secure Erase](https://wiki.archlinux.org/title/Solid_state_drive/Memory_cell_clearing). Alternatively, you can do a fast wipe the following way given that no LUKS, MDADM, SWAP etc. device is open on the disk:

```bash
# Change disk name to the one you want to wipe
DISK="/dev/sda"
lsblk -npo kname "${DISK}" | sort -r | while read -r I; do wipefs -a "$I"; done
```

> ⚠ If you have confidential data stored in a non-encrypted way and don't want to risk the data landing in foreign hands I recommend the use of something like `dd`, e.g. https://wiki.archlinux.org/title/Securely_wipe_disk ⚠

### Disk setup

Prepare the disks (copy&paste one after the other):

```bash
bash /tmp/disk.sh -h

# disable bash history
set +o history

# adjust to your liking
bash /tmp/disk.sh -b bootbootboot -m mastermaster -r rescuerescue -d "/dev/sda /dev/sdb etc." -s 12

# enable bash history
set -o history
```

`disk.sh` creates user "meh" which will be used later on to act as non-root.

### /mnt/gentoo content

Result of a single disk setup:

```bash
# tree -a /mnt/gentoo/
/mnt/gentoo/
├── devBoot -> /dev/sda2
├── devEfia -> /dev/sda1
├── devRescue -> /dev/sda3
├── devSwapa -> /dev/sda4
├── devSystema -> /dev/sda5
├── key
│   └── mnt
│       └── key
│           └── key
├── mapperBoot -> /dev/mapper/sda2
├── mapperRescue -> /dev/mapper/sda3
├── mapperSwap -> /dev/mapper/sda4
├── mapperSystem -> /dev/mapper/sda5
├── portage-latest.tar.xz
├── portage-latest.tar.xz.gpgsig
├── stage3-amd64-hardened-nomultilib-selinux-openrc-20220217T125149Z.tar.xz
└── stage3-amd64-hardened-nomultilib-selinux-openrc-20220217T125149Z.tar.xz.asc

3 directories, 14 files
```

... and dual disk setup:

```bash
# tree -a /mnt/gentoo/
/mnt/gentoo/
├── devBoot -> /dev/md0
├── devEfia -> /dev/sda1
├── devEfib -> /dev/sdb1
├── devRescue -> /dev/md1
├── devSwapa -> /dev/sda4
├── devSwapb -> /dev/sdb4
├── devSystema -> /dev/sda5
├── devSystemb -> /dev/sdb5
├── key
│   └── mnt
│       └── key
│           └── key
├── mapperBoot -> /dev/mapper/md0
├── mapperRescue -> /dev/mapper/md1
├── mapperSwap -> /dev/md2
├── mapperSystem -> /dev/mapper/sda5
├── portage-latest.tar.xz
├── portage-latest.tar.xz.gpgsig
├── stage3-amd64-hardened-nomultilib-selinux-openrc-20220217T125149Z.tar.xz
└── stage3-amd64-hardened-nomultilib-selinux-openrc-20220217T125149Z.tar.xz.asc

3 directories, 17 files
```

### Extracting tarballs

> ⚠ Current `stage3-amd64-hardened-nomultilib-selinux-openrc-*.tar.xz` is downloaded by default. Download and extract your stage3 flavour if it fits your needs more! Check the official handbook for the steps to be taken, especially in regards to verification. ⚠

Extract stage3 tarball and copy `firewall_base.sh`, `genkernel.sh` as well as `boot2efi.sh`:

```bash
tar -C /mnt/gentoo/ -xpvf /mnt/gentoo/stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner && \
rsync -av /tmp/firewall_base.sh /mnt/gentoo/root/ && \
rsync -av /tmp/{genkernel.sh,boot2efi.sh} /mnt/gentoo/usr/local/sbin/ && \
chown root:root /mnt/gentoo/usr/local/sbin/{genkernel.sh,boot2efi.sh} && \
chmod u=rwx,og=r /mnt/gentoo/usr/local/sbin/{genkernel.sh,boot2efi.sh}; echo $?
```

Extract portage tarball:

```bash
mkdir /mnt/gentoo/var/db/repos/gentoo && \
touch /mnt/gentoo/var/db/repos/gentoo/.keep && \
mount -o noatime,subvol=@portage /mnt/gentoo/mapperSystem /mnt/gentoo/var/db/repos/gentoo && \
tar --strip-components=1 -C /mnt/gentoo/var/db/repos/gentoo/ -xvpJf /mnt/gentoo/portage-latest.tar.xz; echo $?
```

## GnuPG homedir

Setup GnuPG homedir (copy&paste one after the other):

```bash
# Switch to non-root user. All following commands are executed by non-root.
su - meh

# Create GnuPG homedir
( umask 0077 && mkdir /tmp/gpgHomeDir )

# Fetch the public key; ADJUST THE MAIL ADDRESS!
gpg --homedir /tmp/gpgHomeDir --auto-key-locate clear,dane,wkd,hkps://keys.duxsco.de --locate-external-key d at "my github username" dot de

# Update ownertrust
echo "3AAE5FC903BB199165D4C02711BE5F68440E0758:6:" | gpg --homedir /tmp/gpgHomeDir --import-ownertrust

# Stop the gpg-agent
gpgconf --homedir /tmp/gpgHomeDir --kill all

exit
```

## genkernel patches

Download [genkernel user patches](https://github.com/duxsco/gentoo-genkernel-patches):

```bash
mkdir -p /mnt/gentoo/etc/portage/patches/sys-kernel/genkernel && \
GIT_TAG="$(grep -o "[^[:space:]]*.ebuild" /mnt/gentoo/var/db/repos/gentoo/sys-kernel/genkernel/Manifest | sed -e 's/\.ebuild$//' -e 's#^#/mnt/gentoo/var/db/repos/gentoo/metadata/md5-cache/sys-kernel/#' | xargs --no-run-if-empty grep --files-with-matches "^KEYWORDS=.*[^\~]amd64[[:space:]$]" | sed 's#.*/##' | sort --version-sort | tail -n 1)" && (
su -l meh -c "curl -fsSL --proto '=https' --tlsv1.3 \"https://raw.githubusercontent.com/duxsco/gentoo-genkernel-patches/${GIT_TAG}/00_defaults_linuxrc.patch\"" > /mnt/gentoo/etc/portage/patches/sys-kernel/genkernel/00_defaults_linuxrc.patch
) && (
su -l meh -c "curl -fsSL --proto '=https' --tlsv1.3 \"https://raw.githubusercontent.com/duxsco/gentoo-genkernel-patches/${GIT_TAG}/01_defaults_initrd.scripts.patch\"" > /mnt/gentoo/etc/portage/patches/sys-kernel/genkernel/01_defaults_initrd.scripts.patch
) && (
su -l meh -c "curl -fsSL --proto '=https' --tlsv1.3 \"https://raw.githubusercontent.com/duxsco/gentoo-genkernel-patches/${GIT_TAG}/02_defaults_initrd.scripts_dosshd.patch\"" > /mnt/gentoo/etc/portage/patches/sys-kernel/genkernel/02_defaults_initrd.scripts_dosshd.patch
) && (
su -l meh -c "curl -fsSL --proto '=https' --tlsv1.3 \"https://raw.githubusercontent.com/duxsco/gentoo-genkernel-patches/${GIT_TAG}/sha512.txt\"" > /tmp/genkernel_sha512.txt
) && (
su -l meh -c "curl -fsSL --proto '=https' --tlsv1.3 \"https://raw.githubusercontent.com/duxsco/gentoo-genkernel-patches/${GIT_TAG}/sha512.txt.asc\"" > /tmp/genkernel_sha512.txt.asc
); echo $?
```

Verify the patches (copy&paste one after the other):

```bash
# Switch to non-root user. All following commands are executed by non-root.
su - meh

# Verify GPG signature. Btw, the GPG key is the same one I use to sign my commits:
# https://github.com/duxsco/gentoo-genkernel-patches/commits/main
gpg --homedir /tmp/gpgHomeDir --verify /tmp/genkernel_sha512.txt.asc /tmp/genkernel_sha512.txt
gpg: Signature made Tue 01 Feb 2022 12:22:06 AM UTC
gpg:                using ECDSA key 7A16FF0E6B3B642B5C927620BFC38358839C0712
gpg:                issuer "d@XXXXXX.de"
gpg: Good signature from "David Sardari <d@XXXXXX.de>" [ultimate]
gpg: Preferred keyserver: hkps://keys.duxsco.de

# Add paths to sha512.txt and verify
sed 's|  |  /mnt/gentoo/etc/portage/patches/sys-kernel/genkernel/|' /tmp/genkernel_sha512.txt | sha512sum -c -
/mnt/gentoo/etc/portage/patches/sys-kernel/genkernel/00_defaults_linuxrc.patch: OK
/mnt/gentoo/etc/portage/patches/sys-kernel/genkernel/01_defaults_initrd.scripts.patch: OK
/mnt/gentoo/etc/portage/patches/sys-kernel/genkernel/02_defaults_initrd.scripts_dosshd.patch: OK

# Stop the gpg-agent
gpgconf --homedir /tmp/gpgHomeDir --kill all

# Switch back to root
exit
```

## gkb2gs - gentoo-kernel-bin config to gentoo-sources

Download [gkb2gs](https://github.com/duxsco/gentoo-gkb2gs):

```bash
(
su -l meh -c "curl -fsSL --proto '=https' --tlsv1.3 https://raw.githubusercontent.com/duxsco/gentoo-gkb2gs/main/gkb2gs.sh" > /mnt/gentoo/usr/local/sbin/gkb2gs.sh
) && (
su -l meh -c "curl -fsSL --proto '=https' --tlsv1.3 https://raw.githubusercontent.com/duxsco/gentoo-gkb2gs/main/gkb2gs.sh.sha512" > /tmp/gkb2gs.sh.sha512
) && (
su -l meh -c "curl -fsSL --proto '=https' --tlsv1.3 https://raw.githubusercontent.com/duxsco/gentoo-gkb2gs/main/gkb2gs.sh.sha512.asc" > /tmp/gkb2gs.sh.sha512.asc
); echo $?
```

Verify gkb2gs (copy&paste one after the other):

```bash
# Switch to non-root
su - meh

# And, verify as already done above for genkernel user patches
gpg --homedir /tmp/gpgHomeDir --verify /tmp/gkb2gs.sh.sha512.asc /tmp/gkb2gs.sh.sha512
gpg: Signature made Sat 01 Jan 2022 01:58:07 PM UTC
gpg:                using ECDSA key 7A16FF0E6B3B642B5C927620BFC38358839C0712
gpg:                issuer "d@XXXXXX.de"
gpg: Good signature from "David Sardari <d@XXXXXX.de>" [ultimate]
gpg: Preferred keyserver: hkps://keys.duxsco.de

# Add paths to sha512.txt and verify
sed 's|  |  /mnt/gentoo/usr/local/sbin/|' /tmp/gkb2gs.sh.sha512 | sha512sum -c -
/mnt/gentoo/usr/local/sbin/gkb2gs.sh: OK

# Stop the gpg-agent
gpgconf --homedir /tmp/gpgHomeDir --kill all

# Switch back to root
exit
```

Create kernel config directory and make script executable:

```bash
mkdir /mnt/gentoo/etc/kernels && \
chmod u+x /mnt/gentoo/usr/local/sbin/gkb2gs.sh
```

## Customise SystemRescueCD ISO

Before mounting and chrooting, download and customise the SystemRescueCD .iso file, while we are still on SystemRescueCD.

Import Gnupg public key:

```bash
(
su -l meh -c "curl -fsSL --proto '=https' --tlsv1.3 https://www.system-rescue.org/security/signing-keys/gnupg-pubkey-fdupoux-20210704-v001.pem | gpg --homedir /tmp/gpgHomeDir --import"
) && (
su -l meh -c "echo \"62989046EB5C7E985ECDF5DD3B0FEA9BE13CA3C9:6:\" | gpg --homedir /tmp/gpgHomeDir --import-ownertrust"
) && \
gpgconf --homedir /tmp/gpgHomeDir --kill all; echo $?
```

Prepare working directory:

```bash
mkdir -p /mnt/gentoo/etc/gentoo-installation/systemrescuecd && \
chown meh: /mnt/gentoo/etc/gentoo-installation/systemrescuecd
```

Download .iso and .asc file:

```bash
RESCUE_SYSTEM_VERSION="$(su -l meh -c "curl -fsSL --proto '=https' --tlsv1.3 https://gitlab.com/systemrescue/systemrescue-sources/-/raw/main/VERSION")" && (
su -l meh -c "curl --continue-at - -fsSL --proto '=https' --tlsv1.2 --ciphers \"ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384\" --output /mnt/gentoo/etc/gentoo-installation/systemrescuecd/systemrescue.iso \"https://sourceforge.net/projects/systemrescuecd/files/sysresccd-x86/${RESCUE_SYSTEM_VERSION}/systemrescue-${RESCUE_SYSTEM_VERSION}-amd64.iso/download\""
) && (
su -l meh -c "curl -fsSL --proto '=https' --tlsv1.3 --output /mnt/gentoo/etc/gentoo-installation/systemrescuecd/systemrescue.iso.asc \"https://www.system-rescue.org/releases/${RESCUE_SYSTEM_VERSION}/systemrescue-${RESCUE_SYSTEM_VERSION}-amd64.iso.asc\""
); echo $?
```

Verify the .iso file:

```bash
(
su -l meh -c "gpg --homedir /tmp/gpgHomeDir --verify /mnt/gentoo/etc/gentoo-installation/systemrescuecd/systemrescue.iso.asc /mnt/gentoo/etc/gentoo-installation/systemrescuecd/systemrescue.iso"
) && (
su -l meh -c "gpgconf --homedir /tmp/gpgHomeDir --kill all"
) && \
chown -R root: /mnt/gentoo/etc/gentoo-installation/systemrescuecd; echo $?
```

Create folder structure and `authorized_keys` file (copy&paste one after the other):

```bash
mkdir -p /mnt/gentoo/etc/gentoo-installation/systemrescuecd/{recipe/{iso_delete,iso_add/{autorun,sysrescue.d},iso_patch_and_script,build_into_srm/{etc/{ssh,sysctl.d},root/.ssh}},work}

# add your ssh public keys to
# /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/root/.ssh/authorized_keys

# set correct modes
chmod u=rwx,g=rx,o= /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/root
chmod -R go= /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/root/.ssh
```

Configure OpenSSH:

```bash
# do some ssh server hardening
sed \
-e 's/^#Port 22$/Port 50024/' \
-e 's/^#PasswordAuthentication yes/PasswordAuthentication no/' \
-e 's/^#X11Forwarding no$/X11Forwarding no/' /etc/ssh/sshd_config > /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/etc/ssh/sshd_config && \

grep -q "^KbdInteractiveAuthentication no$" /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/etc/ssh/sshd_config  && \
(
cat <<EOF >> /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/etc/ssh/sshd_config

AuthenticationMethods publickey

KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
HostKeyAlgorithms ssh-ed25519
Ciphers chacha20-poly1305@openssh.com,aes128-gcm@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256,hmac-sha2-512
EOF
) && \
# create ssh_host_* files in build_into_srm/etc/ssh/
ssh-keygen -A -f /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm; echo $?
```

Disable magic SysRq key for [security sake](https://wiki.gentoo.org/wiki/Vlock#Disable_SysRq_key):

```bash
echo "kernel.sysrq = 0" > /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/etc/sysctl.d/99sysrq.conf
```

Create settings YAML (copy&paste one after the other):

```bash
# disable bash history
set +o history
# replace "MyPassWord123" with the password you want to use to login via TTY on SystemRescueCD
CRYPT_PASS="$(python3 -c 'import crypt; print(crypt.crypt("MyPassWord123", crypt.mksalt(crypt.METHOD_SHA512)))')"
# enable bash history
set -o history

# set default settings
cat <<EOF > /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/iso_add/sysrescue.d/500-settings.yaml
---
global:
    copytoram: true
    checksum: true
    nofirewall: true
    loadsrm: true
    setkmap: de-latin1-nodeadkeys
    dostartx: false
    dovnc: false
    rootshell: /bin/bash
    rootcryptpass: '${CRYPT_PASS}'

autorun:
    ar_disable: false
    ar_nowait: true
    ar_nodel: false
    ar_ignorefail: false
EOF

# Delete variable
unset CRYPT_PASS
```

Create firewall rules:

```bash
# set firewall rules upon bootup.
rsync -av /tmp/firewall_base.sh /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/iso_add/autorun/autorun && \
cat <<EOF >> /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/iso_add/autorun/autorun; echo $?

iptables -A INPUT -p tcp --dport 50024 -m conntrack --ctstate NEW -j ACCEPT
ip6tables -A INPUT -p tcp --dport 50024 -m conntrack --ctstate NEW -j ACCEPT
EOF
```

Write down fingerprints to double check upon initial SSH connection to the SystemRescueCD system:

```bash
find /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/etc/ssh/ -type f -name "ssh_host*\.pub" -exec ssh-keygen -lf {} \;
```

Result:

```bash
# tree -a /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe
/mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe
├── build_into_srm
│   ├── etc
│   │   ├── ssh
│   │   │   ├── sshd_config
│   │   │   ├── ssh_host_dsa_key
│   │   │   ├── ssh_host_dsa_key.pub
│   │   │   ├── ssh_host_ecdsa_key
│   │   │   ├── ssh_host_ecdsa_key.pub
│   │   │   ├── ssh_host_ed25519_key
│   │   │   ├── ssh_host_ed25519_key.pub
│   │   │   ├── ssh_host_rsa_key
│   │   │   └── ssh_host_rsa_key.pub
│   │   └── sysctl.d
│   │       └── 99sysrq.conf
│   └── root
│       └── .ssh
│           └── authorized_keys
├── iso_add
│   ├── autorun
│   │   └── autorun
│   └── sysrescue.d
│       └── 500-settings.yaml
├── iso_delete
└── iso_patch_and_script

11 directories, 13 files
```

Create customised ISO:

```bash
sysrescue-customize --auto --overwrite -s /mnt/gentoo/etc/gentoo-installation/systemrescuecd/systemrescue.iso -d /mnt/gentoo/etc/gentoo-installation/systemrescuecd/systemrescue_ssh.iso -r /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe -w /mnt/gentoo/etc/gentoo-installation/systemrescuecd/work
```

Copy system rescue files to the `rescue` partition:

```bash
mkdir /mnt/iso /mnt/gentoo/mnt/rescue && \
mount -o loop,ro /mnt/gentoo/etc/gentoo-installation/systemrescuecd/systemrescue_ssh.iso /mnt/iso && \
mount -o noatime /mnt/gentoo/mapperRescue /mnt/gentoo/mnt/rescue && \
rsync -HAXSacv --delete /mnt/iso/{autorun,sysresccd,sysrescue.d} /mnt/gentoo/mnt/rescue/ && \
umount /mnt/iso; echo $?
```

## Mounting

```bash
mount --types proc /proc /mnt/gentoo/proc && \
mount --rbind /sys /mnt/gentoo/sys && \
mount --make-rslave /mnt/gentoo/sys && \
mount --rbind /dev /mnt/gentoo/dev && \
mount --make-rslave /mnt/gentoo/dev && \
mount --bind /run /mnt/gentoo/run && \
mount --make-slave /mnt/gentoo/run && \

mount -o noatime,subvol=@home /mnt/gentoo/mapperSystem /mnt/gentoo/home && \

touch /mnt/gentoo/var/cache/distfiles/.keep && \
mount -o noatime,subvol=@distfiles /mnt/gentoo/mapperSystem /mnt/gentoo/var/cache/distfiles && \

mount -o noatime /mnt/gentoo/mapperBoot /mnt/gentoo/boot; echo $?
```

(Optional, but recommended) Use `TMPFS` to compile and for `/tmp`. This is recommended for SSDs and to speed up things, but requires sufficient amount of RAM.

```bash
# Change TMPFS_SIZE based on available RAM
TMPFS_SIZE=4G && \
mount -t tmpfs -o noatime,nodev,nosuid,mode=1777,size=${TMPFS_SIZE},uid=root,gid=root tmpfs /mnt/gentoo/tmp && \
mount -t tmpfs -o noatime,nodev,nosuid,mode=1777,size=${TMPFS_SIZE},uid=root,gid=root tmpfs /mnt/gentoo/var/tmp; echo $?
```

## Pre-chroot configuration

Set resolv.conf:

```bash
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
```

Set aliases:

```bash
rsync -av /mnt/gentoo/etc/skel/.bash* /mnt/gentoo/root/ && \
rsync -av /mnt/gentoo/etc/skel/.ssh /mnt/gentoo/root/ && \
cat <<EOF  >> /mnt/gentoo/root/.bashrc; echo $?
alias cp="cp -i"
alias mv="mv -i"
alias rm="rm -i"
EOF
```

Set locale:

```bash
(
cat <<EOF > /mnt/gentoo/etc/locale.gen
C.UTF-8 UTF-8
de_DE.UTF-8 UTF-8
en_US.UTF-8 UTF-8
EOF
) && (
cat <<EOF > /mnt/gentoo/etc/env.d/02locale
LANG="de_DE.UTF-8"
LC_COLLATE="C.UTF-8"
LC_MESSAGES="en_US.UTF-8"
EOF
) && \
chroot /mnt/gentoo /bin/bash -c "source /etc/profile && locale-gen"; echo $?
```

Set timezone:

```bash
echo "Europe/Berlin" > /mnt/gentoo/etc/timezone && \
rm -fv /mnt/gentoo/etc/localtime && \
chroot /mnt/gentoo /bin/bash -c "source /etc/profile && emerge --config sys-libs/timezone-data"; echo $?
```

Set `MAKEOPTS`:

```bash
RAM_SIZE="$(dmidecode -t memory | grep -Pio "^[[:space:]]Size:[[:space:]]+\K[0-9]*(?=[[:space:]]*GB$)" | paste -d '+' -s - | bc)" && \
NUMBER_CORES="$(nproc --all)" && \
[[ $((NUMBER_CORES*2)) -le ${RAM_SIZE} ]] && JOBS="${NUMBER_CORES}" || JOBS="$(bc <<<"${RAM_SIZE} / 2")" && \
cat <<EOF >> /mnt/gentoo/etc/portage/make.conf; echo $?

MAKEOPTS="-j${JOBS}"
EOF
```

## Chrooting

Chroot (copy&paste one after the other):

```bash
chroot /mnt/gentoo /bin/bash
source /etc/profile
su -
env-update && source /etc/profile && export PS1="(chroot) $PS1"
```

## Portage configuration

Enable webrsync. Thereafter, portage uses https only with below changes to make.conf.

```bash
mkdir /etc/portage/repos.conf && \
sed 's/^sync-type = rsync/sync-type = webrsync/' /usr/share/portage/config/repos.conf > /etc/portage/repos.conf/gentoo.conf && \
grep -q "^sync-webrsync-verify-signature = yes" /etc/portage/repos.conf/gentoo.conf; echo $?
```

Configure make.conf (copy&paste one after the other):

```bash
# If you use distcc, beware of:
# https://wiki.gentoo.org/wiki/Distcc#-march.3Dnative
sed -i 's/COMMON_FLAGS="-O2 -pipe"/COMMON_FLAGS="-march=native -O2 -pipe"/' /etc/portage/make.conf

# The following cipher list contains only AEAD and PFS supporting ciphers with decreasing priority from top to bottom:
#
# TLSv1.2:
#   ECDHE-ECDSA-AES256-GCM-SHA384
#   ECDHE-RSA-AES256-GCM-SHA384
#   DHE-RSA-AES256-GCM-SHA384
#   ECDHE-ECDSA-CHACHA20-POLY1305
#   ECDHE-RSA-CHACHA20-POLY1305
#   DHE-RSA-CHACHA20-POLY1305
#   ECDHE-ECDSA-AES128-GCM-SHA256
#   ECDHE-RSA-AES128-GCM-SHA256
#   DHE-RSA-AES128-GCM-SHA256
#
TLSv12_CIPHERS="ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES128-GCM-SHA256"

cat <<EOF >> /etc/portage/make.conf

L10N="de"
LINGUAS="\${L10N}"

GENTOO_MIRRORS="https://mirror.leaseweb.com/gentoo/ https://ftp-stud.hs-esslingen.de/pub/Mirrors/gentoo/ https://ftp.fau.de/gentoo/ https://ftp.tu-ilmenau.de/mirror/gentoo/"
FETCHCOMMAND="curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --ciphers '${TLSv12_CIPHERS}' --retry 2 --connect-timeout 60 -o \"\\\${DISTDIR}/\\\${FILE}\" \"\\\${URI}\""
RESUMECOMMAND="curl --continue-at - --fail --silent --show-error --location --proto '=https' --tlsv1.2 --ciphers '${TLSv12_CIPHERS}' --retry 2 --connect-timeout 60 -o \"\\\${DISTDIR}/\\\${FILE}\" \"\\\${URI}\""

EOF
```

Set USE flags in `/etc/portage/make.conf`:

```bash
ACCEPT_KEYWORDS=~amd64 emerge -1 app-portage/cpuid2cpuflags && \
cpuid2cpuflags | sed -e 's/: /="/' -e 's/$/"/' >> /etc/portage/make.conf && \
cat <<EOF >> /etc/portage/make.conf; echo $?
USE_HARDENED="pie -sslv3 -suid"
USE="\${CPU_FLAGS_X86} \${USE_HARDENED} fish-completion"

EOF
```

(Optional) Change `GENTOO_MIRRORS` in `/etc/portage/make.conf`:

```bash
ACCEPT_KEYWORDS=~amd64 emerge -1 app-misc/yq && \

# Create mirror list and sort according to your liking.
# I use following list of German mirrors:
#   https://ftp.fau.de/gentoo/
#   https://ftp-stud.hs-esslingen.de/pub/Mirrors/gentoo/
#   https://ftp.tu-ilmenau.de/mirror/gentoo/
#   https://mirror.leaseweb.com/gentoo/
curl -fsSL --proto '=https' --tlsv1.3 https://api.gentoo.org/mirrors/distfiles.xml | xq | jq -r '.mirrors.mirrorgroup[] | select(."@country" == "DE") | .mirror[].uri[] | select(."@protocol" == "http" and ."@ipv4" == "y" and ."@ipv6" == "y") | select(."#text" | startswith("https://")) | ."#text"' | while read -r I; do
  if curl -fsL --proto '=https' --tlsv1.3 -I "$I" >/dev/null; then
    echo "$I"
  fi
done
```

I prefer English manpages and ignore above `L10N` setting for `sys-apps/man-pages`. Makes using Stackoverflow easier 😉.

```bash
echo "sys-apps/man-pages -l10n_de" >> /etc/portage/package.use/main
```

## System update

Update portage and check news:

```bash
emerge app-portage/eix && \
eix-sync && \
eselect news list
# eselect news read 1
# eselect news read 2
# etc.
```

Update system:

```bash
emerge -avuDN --with-bdeps=y --noconfmem --complete-graph=y @world
```

Make `dispatch-conf` show diffs in color:

```bash
sed -i "s/diff=\"diff -Nu '%s' '%s'\"/diff=\"diff --color=always -Nu '%s' '%s'\"/" /etc/dispatch-conf.conf
```

Update configuration files:

```bash
dispatch-conf
```

Make sure that `app-editors/nano` won't be removed and remove extraneous packages (should be only `app-misc/yq` and `app-portage/cpuid2cpuflags`):

```bash
emerge --select --noreplace app-editors/nano && \
emerge --depclean -a
```

## Non-root user setup

Create user:

```bash
useradd -m -G wheel -s /bin/bash david && \
chmod og= /home/david && (
cat <<EOF >> /home/david/.bashrc
alias cp="cp -i"
alias mv="mv -i"
alias rm="rm -i"
EOF
) && \
passwd david
```

Setup sudo:

```bash
echo "app-admin/sudo -sendmail" >> /etc/portage/package.use/main && \
emerge app-admin/sudo && \
echo "%wheel ALL=(ALL) ALL" | EDITOR="tee" visudo -f /etc/sudoers.d/wheel; echo $?
```

Setup vim:

```bash
emerge app-editors/vim && \
echo "filetype plugin on
filetype indent on
set number
set paste
syntax on" | tee -a /root/.vimrc >> /home/david/.vimrc  && \
chown david: /home/david/.vimrc && \
eselect editor set vi && \
eselect vi set vim && \
env-update && source /etc/profile && export PS1="(chroot) $PS1"; echo $?
```

## Secure Boot preparation

Credits:
- https://ruderich.org/simon/notes/secure-boot-with-grub-and-signed-linux-and-initrd
- https://www.funtoo.org/Secure_Boot
- https://www.rodsbooks.com/efi-bootloaders/secureboot.html
- https://fit-pc.com/wiki/index.php?title=Linux:_Secure_Boot&mobileaction=toggle_view_mobile
- https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot

In order to add your custom keys `Setup Mode` must have been enabled in your `UEFI Firmware Settings` before booting into SystemRescueCD. But, you can install Secure Boot files later on if you missed enabling `Setup Mode`. In the following, however, you have to generate Secure Boot files either way.

Install `app-crypt/efitools` and `app-crypt/sbsigntool` on your system:

```bash
emerge -av app-crypt/efitools app-crypt/sbsigntools
```

Create Secure Boot keys and certificates:

```bash
mkdir --mode=0700 /etc/gentoo-installation/secureboot && \
pushd /etc/gentoo-installation/secureboot && \

# Create the keys
openssl req -new -x509 -newkey rsa:2048 -subj "/CN=PK/"  -keyout PK.key  -out PK.crt  -days 7300 -nodes -sha256 && \
openssl req -new -x509 -newkey rsa:2048 -subj "/CN=KEK/" -keyout KEK.key -out KEK.crt -days 7300 -nodes -sha256 && \
openssl req -new -x509 -newkey rsa:2048 -subj "/CN=db/"  -keyout db.key  -out db.crt  -days 7300 -nodes -sha256 && \

# Prepare installation in EFI
UUID="$(uuidgen --random)" && \
cert-to-efi-sig-list -g "${UUID}" PK.crt PK.esl && \
cert-to-efi-sig-list -g "${UUID}" KEK.crt KEK.esl && \
cert-to-efi-sig-list -g "${UUID}" db.crt db.esl && \
sign-efi-sig-list -k PK.key  -c PK.crt  PK  PK.esl  PK.auth && \
sign-efi-sig-list -k PK.key  -c PK.crt  KEK KEK.esl KEK.auth && \
sign-efi-sig-list -k KEK.key -c KEK.crt db  db.esl  db.auth && \
popd; echo $?
```

If the following commands don't work you have install `db.auth`, `KEK.auth` and `PK.auth` over the `UEFI Firmware Settings` upon reboot after the completion of this installation guide. Further information can be found at the end of this installation guide. Beware that the following commands delete all existing keys.

```bash
# Make them mutable
chattr -i /sys/firmware/efi/efivars/{PK,KEK,db,dbx}* && \

# Install keys into EFI (PK last as it will enable Custom Mode locking out further unsigned changes)
efi-updatevar -f db.auth db && \
efi-updatevar -f KEK.auth KEK && \
efi-updatevar -f PK.auth PK && \

# Make them immutable
chattr +i /sys/firmware/efi/efivars/{PK,KEK,db,dbx}* && \
popd; echo $?
```

## fstab configuration

Set /etc/fstab:

```bash
echo "" >> /etc/fstab && \

(
cat <<EOF | column -t >> /etc/fstab
$(find /devEfi* -maxdepth 0 | while read -r I; do
  echo "UUID=$(blkid -s UUID -o value "$I")   ${I/devE/e}                   vfat  noatime,noauto,dmask=0022,fmask=0133  0 0"
done)
UUID=$(blkid -s UUID -o value /mapperBoot)   /boot                   btrfs noatime,noauto                        0 0
UUID=$(blkid -s UUID -o value /mapperSwap)   none                    swap  sw                                    0 0
UUID=$(blkid -s UUID -o value /mapperSystem)   /                       btrfs noatime,subvol=@root                  0 0
UUID=$(blkid -s UUID -o value /mapperSystem)   /home                   btrfs noatime,subvol=@home                  0 0
UUID=$(blkid -s UUID -o value /mapperSystem)   /var/cache/distfiles    btrfs noatime,subvol=@distfiles             0 0
UUID=$(blkid -s UUID -o value /mapperSystem)   /var/db/repos/gentoo    btrfs noatime,subvol=@portage               0 0
EOF
) && \
find /devEfi* -maxdepth 0 | while read -r I; do
  mkdir "${I/devE/e}"
  mount "${I/devE/e}"
done
echo $?
```

(Optional, but recommended) Use `TMPFS` to compile and for `/tmp`. This is recommended for SSDs and to speed up things, but requires sufficient amount of RAM.

```bash
echo "" >> /etc/fstab && \
TMPFS_SIZE=4G && \
cat <<EOF | column -t >> /etc/fstab
tmpfs /tmp     tmpfs noatime,nodev,nosuid,mode=1777,size=${TMPFS_SIZE},uid=root,gid=root 0 0
tmpfs /var/tmp tmpfs noatime,nodev,nosuid,mode=1777,size=${TMPFS_SIZE},uid=root,gid=root 0 0
EOF
```

## CPU, disk and kernel tools

Microcode updates are not necessary for virtual systems. Otherwise, install `sys-firmware/intel-microcode` if you have an Intel CPU. Or, follow the [Gentoo wiki instruction](https://wiki.gentoo.org/wiki/AMD_microcode) to update the microcode on AMD systems.

```bash
! grep -q "[[:space:]]hypervisor[[:space:]]" <(grep "^flags[[:space:]]*:[[:space:]]*" /proc/cpuinfo) && \
grep -q "^vendor_id[[:space:]]*:[[:space:]]*GenuineIntel$" /proc/cpuinfo && \
echo "sys-firmware/intel-microcode intel-ucode" >> /etc/portage/package.license && \
echo "sys-firmware/intel-microcode -* hostonly initramfs" >> /etc/portage/package.use && \
emerge sys-firmware/intel-microcode; echo $?
```

Install genkernel, filesystem and device mapper tools:

```bash
echo "sys-kernel/linux-firmware linux-fw-redistributable no-source-code" >> /etc/portage/package.license && \
emerge dev-util/ccache sys-fs/btrfs-progs sys-fs/cryptsetup sys-kernel/genkernel && (
    [ "$(lsblk -ndo type /devBoot)" == "raid1" ] && \
    emerge sys-fs/mdadm || \
    true
); echo $?
```

Configure `dev-util/ccache`, used to speed up genkernel:

```bash
mkdir -p /root/.cache/ccache /var/cache/ccache && \
cat <<EOF > /var/cache/ccache/ccache.conf; echo $?
compression = true
compression_level = 1
EOF
```

Configure genkernel:

```bash
cp -av /etc/genkernel.conf{,.old} && \
(
    [ "$(lsblk -ndo type /devBoot)" == "raid1" ] && \
    sed -i 's/^#MDADM="no"$/MDADM="yes"/' /etc/genkernel.conf || \
    true
) && \
sed -i \
-e 's/^#MOUNTBOOT="yes"$/MOUNTBOOT="yes"/' \
-e 's/^#SAVE_CONFIG="yes"$/SAVE_CONFIG="yes"/' \
-e 's/^#LUKS="no"$/LUKS="yes"/' \
-e 's/^#BTRFS="no"$/BTRFS="yes"/' \
-e 's/^#BOOTLOADER="no"$/BOOTLOADER="grub2"/' \
-e 's/^#MODULEREBUILD="yes"$/MODULEREBUILD="yes"/' \
-e 's|^#KERNEL_CC="gcc"$|KERNEL_CC="/usr/lib/ccache/bin/gcc"|' \
-e 's|^#UTILS_CC="gcc"$|UTILS_CC="/usr/lib/ccache/bin/gcc"|' \
-e 's|^#UTILS_CXX="g++"$|UTILS_CXX="/usr/lib/ccache/bin/g++"|' \
/etc/genkernel.conf && \
diff -y --suppress-common-lines /etc/genkernel.conf /etc/genkernel.conf.old
```

Delete old config:

```
rm /etc/genkernel.conf.old
```

Setup `dropbear` config directory and `/etc/dropbear/authorized_keys`:

```bash
mkdir --mode=0755 /etc/dropbear && \
rsync -a /etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/root/.ssh/authorized_keys /etc/dropbear/; echo $?
```

## Grub

Install `sys-boot/grub`:

```bash
echo "sys-boot/grub -* device-mapper grub_platforms_efi-64" >> /etc/portage/package.use/main && \
emerge sys-boot/grub; echo $?
```

### Base Grub configuration

```bash
(
    [ "$(lsblk -ndo type /devBoot)" == "raid1" ] && \
    MDADM_MOD=" domdadm" || \
    MDADM_MOD=""
) && \
cat <<EOF >> /etc/default/grub; echo $?

MY_CRYPT_ROOT="$(blkid -s UUID -o value /devSystem* | sed 's/^/crypt_roots=UUID=/' | paste -d " " -s -) root_key=key"
MY_CRYPT_SWAP="$(blkid -s UUID -o value /devSwap* | sed 's/^/crypt_swaps=UUID=/' | paste -d " " -s -) swap_key=key"
MY_FS="rootfstype=btrfs rootflags=subvol=@root"
MY_CPU="mitigations=auto,nosmt"
MY_MOD="dobtrfs${MDADM_MOD}"
GRUB_CMDLINE_LINUX_DEFAULT="\${MY_CRYPT_ROOT} \${MY_CRYPT_SWAP} \${MY_FS} \${MY_CPU} \${MY_MOD} keymap=de"
GRUB_ENABLE_CRYPTODISK="y"
GRUB_DISABLE_OS_PROBER="y"
EOF
```

### ESP Grub configuration

In the following, a minimal Grub config for each EFI system partition is created. Take care of the line marked with `TODO`.

```bash
ls -1d /efi* | while read -r I; do
UUID="$(blkid -s UUID -o value "/devEfi${I#/efi}")"

cat <<EOF > "/etc/gentoo-installation/secureboot/grub-initial_${I#/}.cfg"
# Enforce that all loaded files must have a valid signature.
set check_signatures=enforce
export check_signatures

set superusers="root"
export superusers
# Replace the first TODO with the result of grub-mkpasswd-pbkdf2 with your custom passphrase.
password_pbkdf2 root grub.pbkdf2.sha512.10000.TODO

# NOTE: We export check_signatures/superusers so they are available in all
# further contexts to ensure the password check is always enforced.

search --no-floppy --fs-uuid --set=root ${UUID}

configfile /grub.cfg

# Without this we provide the attacker with a rescue shell if he just presses
# <return> twice.
echo /EFI/grub/grub.cfg did not boot the system but returned to initial.cfg.
echo Rebooting the system in 10 seconds.
sleep 10
reboot
EOF
done; echo $?
```

### SystemRescueCD Grub configuration

Credits:
- https://www.system-rescue.org/manual/Installing_SystemRescue_on_the_disk/
- https://www.system-rescue.org/manual/Booting_SystemRescue/

Setup remote LUKS unlocking:

```bash
# Change settings depending on your requirements; set correct MAC address for XX:XX:XX:XX:XX:XX
echo "dosshd ip=192.168.10.2/24 gk.net.gw=192.168.10.1 gk.net.iface=XX:XX:XX:XX:XX:XX gk.sshd.port=50023" > /etc/gentoo-installation/systemrescuecd_dosshd.conf
```

Create the Grub config to boot into the rescue system:

```bash
UUID="$(blkid -s UUID -o value /devRescue | tr -d '-')"
cat <<EOF >> /etc/grub.d/40_custom; echo $?

menuentry 'SystemRescueCD' {
    cryptomount -u ${UUID}
    set root='cryptouuid/${UUID}'
    search --no-floppy --fs-uuid --set=root --hint='cryptouuid/${UUID}' $(blkid -s UUID -o value /mapperRescue)
    echo   'Loading Linux kernel ...'
    linux  /sysresccd/boot/x86_64/vmlinuz cryptdevice=UUID=$(blkid -s UUID -o value /devRescue):root root=/dev/mapper/root archisobasedir=sysresccd archisolabel=rescue noautologin
    echo   'Loading initramfs ...'
    initrd /sysresccd/boot/x86_64/sysresccd.img
}
EOF
```

## Kernel installation

Install [LTS kernel](https://www.kernel.org/category/releases.html):

```bash
INSTALL_LTS_KERNEL="true" && (
cat <<EOF >> /etc/portage/package.accept_keywords/main
sys-kernel/gentoo-kernel-bin ~amd64
sys-kernel/gentoo-sources ~amd64
sys-kernel/linux-headers ~amd64
EOF
) && (
[ "${INSTALL_LTS_KERNEL}" == "true" ] && \
cat <<EOF >> /etc/portage/package.mask/main
>=sys-kernel/gentoo-kernel-bin-5.16
>=sys-kernel/gentoo-sources-5.16
>=sys-kernel/linux-headers-5.16
EOF
) && (
cat <<EOF >> /etc/portage/package.use/main
sys-fs/btrfs-progs -convert
sys-kernel/gentoo-kernel-bin -initramfs
EOF
) && \
emerge sys-kernel/gentoo-sources && \
eselect kernel list && \
eselect kernel set 1; echo $?
```

Configure the kernel from scratch or use the configuration from `sys-kernel/gentoo-kernel-bin` with:

```bash
gkb2gs.sh
```

Customise kernel configuration and build kernel and initramfs for local and remote (via SSH) LUKS unlock:

```bash
# I usually make following changes for systems with Intel CPU:
#     Processor type and features  --->
#         [ ] Support for extended (non-PC) x86 platforms
#             Processor family (Core 2/newer Xeon)  --->
#         <*> CPU microcode loading support
#         [*]   Intel microcode loading support
#         [ ]   AMD microcode loading support
#     Binary Emulations --->
#         [ ] IA32 Emulation
#         [ ] x32 ABI for 64-bit mode
#     Device Drivers  --->
#         Generic Driver Options --->
#             Firmware Loader --->
#                 -*-   Firmware loading facility
#                 [ ] Enable the firmware sysfs fallback mechanism
#     Kernel hacking  --->
#         Generic Kernel Debugging Instruments  --->
#             [ ] Magic SysRq key
#         [ ] Remote debugging over FireWire early on boot
genkernel.sh
```

`genkernel.sh` prints out SSH fingerprints. Write them down to double check upon initial SSH connection to the initramfs system.

For now, ignore the request to sign files. The GnuPG keypair must be created first and other files must be signed, too. This will be done in the next chapter.

## GnuPG boot file signing

The whole boot process must be GnuPG signed. You can use either RSA or some NIST-P based ECC. Unfortunately, `ed25519/cv25519` as well as `ed448/cv448` are not supported. It seems Grub builds upon [libgcrypt 1.5.3](https://git.savannah.gnu.org/cgit/grub.git/commit/grub-core?id=d1307d873a1c18a1e4344b71c027c072311a3c14), but support for `ed25519/cv25519` has been added upstream later on in [version 1.6.0](https://git.gnupg.org/cgi-bin/gitweb.cgi?p=libgcrypt.git;a=blob;f=NEWS;h=bc70483f4376297a11ed44b40d5b8a71a478d321;hb=HEAD#l709), while [version 1.9.0](https://git.gnupg.org/cgi-bin/gitweb.cgi?p=libgcrypt.git;a=blob;f=NEWS;h=bc70483f4376297a11ed44b40d5b8a71a478d321;hb=HEAD#l139) comes with `ed448/cv448` support.

Create a GnuPG keypair, e.g.:

```bash
# gpg --full-gen-key
gpg (GnuPG) 2.2.32; Copyright (C) 2021 Free Software Foundation, Inc.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.

gpg: directory '/root/.gnupg' created
gpg: keybox '/root/.gnupg/pubring.kbx' created
Please select what kind of key you want:
   (1) RSA and RSA (default)
   (2) DSA and Elgamal
   (3) DSA (sign only)
   (4) RSA (sign only)
  (14) Existing key from card
Your selection? 4
RSA keys may be between 1024 and 4096 bits long.
What keysize do you want? (3072)
Requested keysize is 3072 bits
Please specify how long the key should be valid.
         0 = key does not expire
      <n>  = key expires in n days
      <n>w = key expires in n weeks
      <n>m = key expires in n months
      <n>y = key expires in n years
Key is valid for? (0)
Key does not expire at all
Is this correct? (y/N) y

GnuPG needs to construct a user ID to identify your key.

Real name: grubEfi
Email address:
Comment:
You selected this USER-ID:
    "grubEfi"

Change (N)ame, (C)omment, (E)mail or (O)kay/(Q)uit? o
```

Result:

```bash
# gpg --list-keys
gpg: checking the trustdb
gpg: marginals needed: 3  completes needed: 1  trust model: pgp
gpg: depth: 0  valid:   1  signed:   0  trust: 0-, 0q, 0n, 0m, 0f, 1u
/root/.gnupg/pubring.kbx
------------------------
pub   rsa3072 2022-02-15 [SC]
      714F5DD28AC1A31E04BCB850B158334ADAF5E3C0
uid           [ultimate] grubEfi
```

Export your GnuPG public key and sign "grub-initial_efi*.cfg" (copy&paste one after the other):

```bash
# Change Key ID
KEY_ID="0x714F5DD28AC1A31E04BCB850B158334ADAF5E3C0"

# Export public key
gpg --export-options export-minimal --export "${KEY_ID}" > /etc/gentoo-installation/secureboot/gpg.pub; echo $?

# If signature creation fails...
GPG_TTY="$(tty)"
export GPG_TTY

# Sign initial grub.cfg
ls -1d /efi* | while read -r I; do
    gpg --local-user "${KEY_ID}" --detach-sign "/etc/gentoo-installation/secureboot/grub-initial_${I#/}.cfg"; echo $?
done

# Stop the gpg-agent
gpgconf --kill all
```

Sign your boot files with GnuPG:

```bash
# Change Key ID
KEY_ID="0x714F5DD28AC1A31E04BCB850B158334ADAF5E3C0"

find /boot /mnt/rescue -type f -exec gpg --detach-sign --local-user "${KEY_ID}" {} \; && \
gpgconf --kill all; echo $?
```

## EFI binary

Create the EFI binary/ies and Secure Boot sign them:

```bash
# GRUB doesn't allow loading new modules from disk when secure boot is in
# effect, therefore pre-load the required modules.
MODULES=
MODULES="${MODULES} part_gpt fat ext2"             # partition and file systems for EFI
MODULES="${MODULES} configfile"                    # source command
MODULES="${MODULES} verify gcry_sha512 gcry_rsa"   # signature verification
MODULES="${MODULES} password_pbkdf2"               # hashed password
MODULES="${MODULES} echo normal linux linuxefi"    # boot linux
MODULES="${MODULES} all_video"                     # video output
MODULES="${MODULES} search search_fs_uuid"         # search --fs-uuid
MODULES="${MODULES} reboot sleep"                  # sleep, reboot
MODULES="${MODULES} gzio part_gpt part_msdos ext2" # SystemRescueCD modules
MODULES="${MODULES} $(grub-mkconfig | grep insmod | awk '{print $NF}' | sort -u | paste -d ' ' -s -)"

ls -1d /efi* | while read -r I; do
    mkdir -p "${I}/EFI/boot" && \
    grub-mkstandalone \
        --directory /usr/lib/grub/x86_64-efi \
        --disable-shim-lock \
        --format x86_64-efi \
        --modules "$(ls -1 /usr/lib/grub/x86_64-efi/ | grep -w $(tr ' ' '\n' <<<"${MODULES}" | sort -u | grep -v "^$" | sed -e 's/^/-e /' -e 's/$/.mod/' | paste -d ' ' -s -) | paste -d ' ' -s -)" \
        --pubkey /etc/gentoo-installation/secureboot/gpg.pub \
        --output "${I}/EFI/boot/bootx64.efi" \
        "boot/grub/grub.cfg=/etc/gentoo-installation/secureboot/grub-initial_${I#/}.cfg" \
        "boot/grub/grub.cfg.sig=/etc/gentoo-installation/secureboot/grub-initial_${I#/}.cfg.sig" && \
    sbsign --key /etc/gentoo-installation/secureboot/db.key --cert /etc/gentoo-installation/secureboot/db.crt --output "${I}/EFI/boot/bootx64.efi" "${I}/EFI/boot/bootx64.efi" && \
    efibootmgr --create --disk "/dev/$(lsblk -ndo pkname "$(readlink -f "${I/efi/devEfi}")")" --part 1 --label "gentoo ${I#/}" --loader '\EFI\boot\bootx64.efi'
    echo $?
done
```

## Boot file installation

Copy relevant files from `/boot` to `/efi*/`:

```bash
boot2efi.sh && \
ls -1d /efi* | while read -r I; do
    mount "${I}"
done
```

Result:

```bash
tree -a /boot /efi*
/boot
├── initramfs-5.15.23-gentoo-x86_64.img
├── initramfs-5.15.23-gentoo-x86_64.img.sig
├── System.map-5.15.23-gentoo-x86_64
├── System.map-5.15.23-gentoo-x86_64.sig
├── vmlinuz-5.15.23-gentoo-x86_64
├── vmlinuz-5.15.23-gentoo-x86_64.sig
/efia
├── EFI
│   └── boot
│       └── bootx64.efi
├── grub.cfg
├── grub.cfg.sig
├── initramfs-5.15.23-gentoo-x86_64-ssh.img
├── initramfs-5.15.23-gentoo-x86_64-ssh.img.sig
├── System.map-5.15.23-gentoo-x86_64-ssh
├── System.map-5.15.23-gentoo-x86_64-ssh.sig
├── vmlinuz-5.15.23-gentoo-x86_64-ssh
└── vmlinuz-5.15.23-gentoo-x86_64-ssh.sig
/efib
├── EFI
│   └── boot
│       └── bootx64.efi
├── grub.cfg
├── grub.cfg.sig
├── initramfs-5.15.23-gentoo-x86_64-ssh.img
├── initramfs-5.15.23-gentoo-x86_64-ssh.img.sig
├── System.map-5.15.23-gentoo-x86_64-ssh
├── System.map-5.15.23-gentoo-x86_64-ssh.sig
├── vmlinuz-5.15.23-gentoo-x86_64-ssh
└── vmlinuz-5.15.23-gentoo-x86_64-ssh.sig

4 directories, 34 files
```

## Configuration

Set hostname:

```bash
sed -i 's/^hostname="localhost"/hostname="micro"/' /etc/conf.d/hostname
```

Set IP address:

```bash
# Change interface name and settings according to your requirements
echo 'config_enp0s3="10.0.2.15 netmask 255.255.255.0 brd 10.0.2.255"
routes_enp0s3="default via 10.0.2.2"' >> /etc/conf.d/net && \
( cd /etc/init.d && ln -s net.lo net.enp0s3 ) && \
rc-update add net.enp0s3 default; echo $?
```

Set `/etc/hosts`:

```bash
sed -i 's/localhost$/localhost micro/' /etc/hosts
```

Set /etc/rc.conf:

```bash
sed -i 's/#rc_logger="NO"/rc_logger="YES"/' /etc/rc.conf
```

Set /etc/conf.d/keymaps:

```bash
sed -i 's/keymap="us"/keymap="de-latin1-nodeadkeys"/' /etc/conf.d/keymaps
```

`clock="UTC"` should be set in /etc/conf.d/hwclock which is the default.

## Tools

Setup system logger:

```bash
emerge app-admin/sysklogd && \
rc-update add sysklogd default; echo $?
```

Setup cronie:

```bash
emerge sys-process/cronie && \
rc-update add cronie default; echo $?
```

Enable ssh service:

```bash
rc-update add sshd default
```

Install DHCP client (you never know...):

```bash
emerge net-misc/dhcpcd
```

## Further customisations

  - acpid:

```bash
emerge sys-power/acpid && \
rc-update add acpid default; echo $?
```

  - chrony:

```bash
! grep -q "[[:space:]]hypervisor[[:space:]]" <(grep "^flags[[:space:]]*:[[:space:]]*" /proc/cpuinfo) && \
emerge net-misc/chrony && \
rc-update add chronyd default && \
sed -i 's/^server/#server/' /etc/chrony/chrony.conf && \
cat <<EOF >> /etc/chrony/chrony.conf; echo $?

# https://blog.cloudflare.com/nts-is-now-rfc/
server time.cloudflare.com iburst nts

# https://www.netnod.se/time-and-frequency/network-time-security
# https://www.netnod.se/time-and-frequency/how-to-use-nts
server nts.netnod.se       iburst nts

# https://nts.time.nl
server nts.time.nl         iburst nts

# https://www.ptb.de/cms/ptb/fachabteilungen/abtq/gruppe-q4/ref-q42/zeitsynchronisation-von-rechnern-mit-hilfe-des-network-time-protocol-ntp.html
server ptbtime1.ptb.de     iburst nts
server ptbtime2.ptb.de     iburst nts
server ptbtime3.ptb.de     iburst nts

# NTS cookie jar to minimise NTS-KE requests upon chronyd restart
ntsdumpdir /var/lib/chrony

rtconutc
EOF
```

  - consolefont:

```bash
sed -i 's/^consolefont="\(.*\)"$/consolefont="lat9w-16"/' /etc/conf.d/consolefont && \
rc-update add consolefont boot; echo $?
```

  - dmcrypt:

```bash
LAST_LINE="$(cat /etc/conf.d/dmcrypt | tail -n 1)" && \
sed -i '$ d' /etc/conf.d/dmcrypt && \
echo "target='boot'
source=UUID='$(blkid -s UUID -o value /devBoot)'
key='/key/mnt/key/key'

${LAST_LINE}" >> /etc/conf.d/dmcrypt && \
rc-update add dmcrypt boot; echo $?
```

  - fish shell:

```bash
echo "=dev-libs/libpcre2-$(emerge --search '%^dev-libs/libpcre2$' | grep -i 'latest version available' | awk '{print $NF}') pcre32" >> /etc/portage/package.use/main && \
echo "app-shells/fish ~amd64" >> /etc/portage/package.accept_keywords/main && \
emerge app-shells/fish && (
cat <<EOF | tee -a /root/.bashrc >> /home/david/.bashrc

# Use fish in place of bash
# keep this line at the bottom of ~/.bashrc
[ -x /bin/fish ] && SHELL=/bin/fish exec /bin/fish
EOF
); echo $?
```

`root` setup:

```bash
/bin/fish -c 'alias cp="cp -i"; alias mv="mv -i"; alias rm="rm -i"; funcsave cp; funcsave mv; funcsave rm; fish_config prompt choose terlar; fish_config prompt save'
```

`non-root` setup:

```bash
su -l david -c "/bin/fish -c 'alias cp=\"cp -i\"; alias mv=\"mv -i\"; alias rm=\"rm -i\"; funcsave cp; funcsave mv; funcsave rm; fish_config prompt choose terlar; fish_config prompt save'"
```

  - mcelog:

```bash
echo "app-admin/mcelog ~amd64" >> /etc/portage/package.accept_keywords/main && \
emerge app-admin/mcelog && \
rc-update add mcelog default; echo $?
```

  - If you have `sys-fs/mdadm` installed:

```bash
[ "$(lsblk -ndo type /devBoot)" == "raid1" ] && \
echo "" >> /etc/mdadm.conf && \
mdadm --detail --scan >> /etc/mdadm.conf
```

  - rng-tools:

```bash
echo "sys-apps/rng-tools jitterentropy" >> /etc/portage/package.use/main && \
emerge sys-apps/rng-tools && \
rc-update add rngd default; echo $?
```

  - ssh:

```bash
rsync -av /etc/dropbear/authorized_keys /home/david/.ssh/ && \
chmod og= /home/david/.ssh/authorized_keys && \
chown david: /home/david/.ssh/authorized_keys && \
cp -av /etc/ssh/sshd_config{,.old} && \
sed -i \
-e 's/^#Port 22$/Port 50022/' \
-e 's/^#PermitRootLogin prohibit-password$/PermitRootLogin no/' \
-e 's/^#KbdInteractiveAuthentication yes$/KbdInteractiveAuthentication no/' \
-e 's/^#X11Forwarding no$/X11Forwarding no/' /etc/ssh/sshd_config && \
grep -q "^PasswordAuthentication no$" /etc/ssh/sshd_config && \
(
cat <<EOF >> /etc/ssh/sshd_config

AuthenticationMethods publickey

KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
HostKeyAlgorithms ssh-ed25519
Ciphers chacha20-poly1305@openssh.com,aes128-gcm@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256,hmac-sha2-512

AllowUsers david
EOF
) && \
ssh-keygen -A && \
sshd -t && \
diff /etc/ssh/sshd_config{,.old}
```

Write down fingerprints to double check upon initial SSH connection to the Gentoo Linux machine:

```bash
find /etc/ssh/ -type f -name "ssh_host*\.pub" -exec ssh-keygen -lf {} \;
```

Setup client SSH config:

```bash
(
cat <<EOF > /home/david/.ssh/config
AddKeysToAgent no
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
HostKeyAlgorithms ssh-ed25519-cert-v01@openssh.com,sk-ssh-ed25519-cert-v01@openssh.com,ssh-ed25519,sk-ssh-ed25519@openssh.com
Ciphers chacha20-poly1305@openssh.com,aes128-gcm@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256,hmac-sha2-512
HashKnownHosts no
StrictHostKeyChecking ask
EOF
) && \
chown david: /home/david/.ssh/config; echo $?
```

  - sysrq (if you don't want to disable in kernel):

```bash
echo "kernel.sysrq = 0" > /etc/sysctl.d/99sysrq.conf
```

  - misc tools:

```bash
emerge app-misc/screen app-portage/gentoolkit app-admin/eclean-kernel; echo $?
```

## Cleanup and reboot

  - stage3 and dev* files:

```bash
rm -fv /stage3-* /portage-latest.tar.xz* /devBoot /devEfi* /devRescue /devSystem* /devSwap* /mapperBoot /mapperRescue /mapperSwap /mapperSystem; echo $?
```

  - exit and reboot (copy&paste one after the other):

```bash
exit
exit
exit
cd
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -R /mnt/gentoo
reboot
```

## Firewall rules

Create firewall rules:

```bash
bash -c '
rsync -av /root/firewall_base.sh /usr/local/sbin/firewall.sh && \
(
cat <<EOF >> /usr/local/sbin/firewall.sh

iptables -A INPUT -p tcp --dport 50022 -m conntrack --ctstate NEW -j ACCEPT
ip6tables -A INPUT -p tcp --dport 50022 -m conntrack --ctstate NEW -j ACCEPT
EOF
) && \
chown root: /usr/local/sbin/firewall.sh && \
chmod u+x /usr/local/sbin/firewall.sh; echo $?
'
```

Save firewall rules:

```bash
bash -c '
(
[ ! -f /sbin/iptables ] && emerge iptables || true
)  && \
/usr/local/sbin/firewall.sh && \
rc-service iptables save && \
rc-service ip6tables save && \
rc-update add iptables default && \
rc-update add ip6tables default; echo $?
'
```

## Installation of Secure Boot files via UEFI Firmware Settings

If `efi-updatevar` fails, you can import Secure Boot files after the completion of this installation guide.

First, boot into the Gentoo Linux and save necessary files in `DER` form:

```bash
bash -c '
(
! mountpoint /efia && \\
mount /efia || true
) && \\
openssl x509 -outform der -in /etc/gentoo-installation/secureboot/db.crt -out /efia/db.der && \\
openssl x509 -outform der -in /etc/gentoo-installation/secureboot/KEK.crt -out /efia/KEK.der && \\
openssl x509 -outform der -in /etc/gentoo-installation/secureboot/PK.crt -out /efia/PK.der; echo $?
'
```

Reboot into `UEFI Firmware Settings` and import `db.der`, `KEK.der` and `PK.der`. Thereafter, enable Secure Boot. Upon successfull boot with Secure Boot enabled, you can delete `db.der`, `KEK.der` and `PK.der` in `/efia`.

## Update Linux kernel

For every kernel update, execute:

```bash
# Install kernel update with "emerge"

# List kernels
eselect kernel list

# Select the kernel of your choice with
eselect kernel set <NUMBER>

# Configure the kernel from scratch, use an old config or use the configuration from sys-kernel/gentoo-kernel-bin with
gkb2gs.sh

# Customise kernel configuration and build kernel
genkernel.sh

# GnuPG sign files printed out by genkernel.sh

# Copy files from /boot to /efi*
boot2efi.sh
```

## Remote unlock

SSH into the machine, execute `cryptsetup luksOpen` for every LUKS volume you want to open. Example:

```bash
# At least luksOpen the swap and system partitions, see
# https://github.com/duxsco/gentoo-installation#disk-layout
#
# Example:
cryptsetup luksOpen /dev/sda4 sda4
cryptsetup luksOpen /dev/sdb4 sdb4
cryptsetup luksOpen /dev/sda5 sda5
cryptsetup luksOpen /dev/sdb5 sdb5
etc.
```

If you are finished, execute to resume boot:

```bash
touch /tmp/SWAP.opened /tmp/ROOT.opened && rm /tmp/remote-rescueshell.lock
```

## Other Gentoo Linux repos

https://github.com/duxsco?tab=repositories&q=gentoo-
