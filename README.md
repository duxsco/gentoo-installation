# Gentoo Linux installation

In the following, I am using the [Arch Linux Live CD](https://archlinux.org/download/), **not** the official Gentoo Linux installation CD. If not otherwise stated, commands are executed on the remote machine where Gentoo Linux needs to be installed, in the beginning via TTY, later on over SSH. Most of the time, you can copy&paste the whole code block, but understand the commands first and make adjustments (e.g. IP address, disk names) if required.

The installation steps make use of LUKS encryption wherever possible. Only the EFI System Partitions are not encrypted.
You need to boot using EFI (not BIOS), because the boot partition will be encrypted, and decryption of said partition with the help of GRUB won't work otherwise.

The number of disks, where Gentoo Linux will be installed, must be less than 5. Depending on the number of disks, BTRFS "single", "raid1", "raid1c3" or "raid1c4" is used for the `root` partition. Furthermore, MDADM RAID 1 may be used for `boot` and `swap` partitions. And, EFI System Partitions each with their own EFI entry are created one for each disk.

- Single disk:

```
PC∕Laptop
└── ∕dev∕sda
    ├── 1. EFI System Partition
    ├── 2. LUKS
    │   └── Btrfs (single)
    │       └── boot
    ├── 3. LUKS
    │   └── SWAP
    └── 4. LUKS
        └── Btrfs (single)
            └── subvolumes
                ├── @distfiles
                ├── @home
                ├── @portage
                └── @root
```

- Two disks:

```
PC∕Laptop
└── ∕dev∕sda                       └── ∕dev∕sdb
    ├── 1. EFI System Partition        ├── 1. EFI System Partition
    ├── 2. MDADM RAID 1                ├── 2. MDADM RAID 1
    │   └── LUKS                       │   └── LUKS
    │       └── Btrfs                  │       └── Btrfs
    │           └── boot               │           └── boot
    ├── 3. LUKS                        ├── 3. LUKS
    │   └── MDADM RAID 1               │   └── MDADM RAID 1
    │       └── SWAP                   │       └── SWAP
    └── 4. LUKS                        └── 4. LUKS
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
    ├── 3. LUKS                        ├── 3. LUKS                        ├── 3. LUKS
    │   └── MDADM RAID 1               │   └── MDADM RAID 1               │   └── MDADM RAID 1
    │       └── SWAP                   │       └── SWAP                   │       └── SWAP
    └── 4. LUKS                        └── 4. LUKS                        └── 4. LUKS
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
    ├── 3. LUKS                        ├── 3. LUKS                        ├── 3. LUKS                        ├── 3. LUKS
    │   └── MDADM RAID 1               │   └── MDADM RAID 1               │   └── MDADM RAID 1               │   └── MDADM RAID 1
    │       └── SWAP                   │       └── SWAP                   │       └── SWAP                   │       └── SWAP
    └── 4. LUKS                        └── 4. LUKS                        └── 4. LUKS                        └── 4. LUKS
        └── BTRFS (raid1c4)                └── BTRFS (raid1c4)                └── BTRFS (raid1c4)                └── BTRFS (raid1c4)
            └── subvolume                      └── subvolume                      └── subvolume                      └── subvolume
                ├── @distfiles                     ├── @distfiles                     ├── @distfiles                     ├── @distfiles
                ├── @home                          ├── @home                          ├── @home                          ├── @home
                ├── @portage                       ├── @portage                       ├── @portage                       ├── @portage
                └── @root                          └── @root                          └── @root                          └── @root
```

On LUKS encrypted disks, LUKS passphrase slot are set as follows:
  - 0: Keyfile (stored in initramfs to unlock `root` and `swap` partitions without interaction)
  - 1: Master password (fallback password for emergency)
  - 2: Boot password
    - shorter than "master", but still secure
    - keyboard layout independent (QWERTY vs QWERTZ)
    - used during boot to unlock `boot` partition via GRUB's password prompt

The following steps are basically those in [the official Gentoo Linux installation handbook](https://wiki.gentoo.org/wiki/Handbook:AMD64/Full/Installation) with some customisations added.

## Preparing Live-CD environment

Boot into SystemRescueCD and set the correct keyboard layout:

```bash
loadkeys de-latin1-nodeadkeys
```

Make sure you have booted with EFI:

```bash
[ -d /sys/firmware/efi ] && echo UEFI || echo BIOS
```

Do initial setup (copy&paste one after the other):

```bash
screen -S install

# Don't store commands with leading whitespace in ~/.bash_history
export HISTCONTROL="ignorespace"

# If no network setup via DHCP done...
ip a add ...
ip r add default ...
echo nameserver ... > /etc/resolv.conf

# Make sure you have enough entropy for cryptsetup's "--use-random"
pacman -Sy rng-tools
systemctl start rngd

# Alternatively, setup /root/.ssh/authorized_keys
passwd root
```

Execute following SCP/SSH commands **on your local machine** (copy&paste one after the other):

```bash
# Copy installation files to remote machine. Adjust port and IP.
scp -P XXX {disk.sh,fetch_files.sh} root@XXX:/tmp/
sha256sum disk.sh fetch_files.sh | sed 's#  #  /tmp/#' | ssh -p XXX root@... dd of=/tmp/sha256.txt

# From local machine, login into the remote machine
ssh -p XXX root@...
```

Resume `screen`:

```bash
screen -d -r install
```

Check file hashes:

```bash
sha256sum -c /tmp/sha256.txt
```

Disable `sysrq` for [security sake](https://wiki.gentoo.org/wiki/Vlock#Disable_SysRq_key):

```bash
sysctl -w kernel.sysrq=0
```

(Optional) Lock the screen on the remote machine by typing the following command on its keyboard (**not over SSH**):

```bash
# Execute "vlock" without any flags first.
# If relogin doesn't work you can switch tty to fix (e.g. set password again).
# If relogin succeeds execute vlock with flag "-a" to lock all tty.
vlock -a
```

Prepare the disks:

```bash
bash /tmp/disk.sh -h
# Place whitespace before following command to have bash not store passwords in ~/.bash_history.
    bash /tmp/disk.sh -b bootbootboot -m mastermaster -d "/dev/sda /dev/sdb etc." -s 12
```

## Prepare chroot

Set date:

```bash
date MMDDhhmmYYYY
```

Extract stage3 tarball:

```bash
tar -C /mnt/gentoo/ -xpvf /mnt/gentoo/stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner; echo $?
```

Mount:

```bash
mount --types proc /proc /mnt/gentoo/proc && \
mount --rbind /sys /mnt/gentoo/sys && \
mount --make-rslave /mnt/gentoo/sys && \
mount --rbind /dev /mnt/gentoo/dev && \
mount --make-rslave /mnt/gentoo/dev && \

mount -o noatime,subvol=@home /mnt/gentoo/mapperRoot /mnt/gentoo/home && \

touch /mnt/gentoo/var/cache/distfiles/.keep && \
mount -o noatime,subvol=@distfiles /mnt/gentoo/mapperRoot /mnt/gentoo/var/cache/distfiles && \

mkdir /mnt/gentoo/var/db/repos/gentoo && \
touch /mnt/gentoo/var/db/repos/gentoo/.keep && \
mount -o noatime,subvol=@portage /mnt/gentoo/mapperRoot /mnt/gentoo/var/db/repos/gentoo && \

mount -o noatime /mnt/gentoo/mapperBoot /mnt/gentoo/boot; echo $?
```

(Optional, but recommended) Use `TMPFS` to compile and for `/tmp`. This is recommended for SSDs and to speed up things., but requires sufficient amount of RAM.

```bash
# Change TMPFS_SIZE based on available RAM
TMPFS_SIZE=4G && \
mount -t tmpfs -o noatime,nodev,nosuid,mode=1777,size=${TMPFS_SIZE},uid=root,gid=root tmpfs /mnt/gentoo/tmp && \
mount -t tmpfs -o noatime,nodev,nosuid,mode=1777,size=${TMPFS_SIZE},uid=root,gid=root tmpfs /mnt/gentoo/var/tmp; echo $?
```

Extract portage tarball:

```bash
tar --strip-components=1 -C /mnt/gentoo/var/db/repos/gentoo/ -xvpJf /mnt/gentoo/portage-latest.tar.xz; echo $?
```

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

Set make.conf:

```bash
# If you use distcc, beware of:
# https://wiki.gentoo.org/wiki/Distcc#-march.3Dnative
sed -i 's/COMMON_FLAGS="-O2 -pipe"/COMMON_FLAGS="-march=native -O2 -pipe"/' /mnt/gentoo/etc/portage/make.conf

# The following cipher list contains only AEAD and PFS supporting ciphers. Decreasing priority from top to bottom:
#
# TLSv1.2:
#   ECDHE-ECDSA-AES128-GCM-SHA256
#   ECDHE-ECDSA-AES256-GCM-SHA384
#   ECDHE-ECDSA-CHACHA20-POLY1305
#   ECDHE-RSA-AES128-GCM-SHA256
#   ECDHE-RSA-AES256-GCM-SHA384
#   ECDHE-RSA-CHACHA20-POLY1305
#   DHE-RSA-AES128-GCM-SHA256
#   DHE-RSA-AES256-GCM-SHA384
#   DHE-RSA-CHACHA20-POLY1305
#
TLSv12_CIPHERS="$(openssl ciphers -s -v | grep -i aead | grep -i dhe | sort | sort -k1.1,1.1 -s -r | awk '{print $1}' | paste -d: -s -)"

cat <<EOF >> /mnt/gentoo/etc/portage/make.conf

MAKEOPTS="-j$(nproc --all) -l$(bc -l <<<"0.9 * $(nproc --all)")"
EMERGE_DEFAULT_OPTS="-j"

L10N="de"
LINGUAS="\${L10N}"

GENTOO_MIRRORS="https://ftp.fau.de/gentoo/ https://ftp-stud.hs-esslingen.de/pub/Mirrors/gentoo/ https://ftp.tu-ilmenau.de/mirror/gentoo/ https://mirror.leaseweb.com/gentoo/"
FETCHCOMMAND="curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --ciphers '${TLSv12_CIPHERS}' --retry 2 --connect-timeout 60 -o \"\\\${DISTDIR}/\\\${FILE}\" \"\\\${URI}\""
RESUMECOMMAND="curl --continue-at - --fail --silent --show-error --location --proto '=https' --tlsv1.2 --ciphers '${TLSv12_CIPHERS}' --retry 2 --connect-timeout 60 -o \"\\\${DISTDIR}/\\\${FILE}\" \"\\\${URI}\""

EOF
```

I prefer English manpages and ignore above `L10N` setting for `sys-apps/man-pages`. Makes using Stackoverflow easier 😉.

```bash
echo "sys-apps/man-pages -l10n_de" >> /mnt/gentoo/etc/portage/package.use/main
```

## Chroot

Chroot (copy&paste one after the other):

```bash
chroot /mnt/gentoo /bin/bash
source /etc/profile
su -
env-update && source /etc/profile && export PS1="(chroot) $PS1"
```

Enable webrsync. Thereafter, portage uses https only.

```bash
mkdir /etc/portage/repos.conf && \
sed 's/sync-type = rsync/sync-type = webrsync/' /usr/share/portage/config/repos.conf > /etc/portage/repos.conf/gentoo.conf && \
grep -q "sync-webrsync-verify-signature = yes" /etc/portage/repos.conf/gentoo.conf; echo $?
```

Update portage and check news:

```bash
emerge app-portage/eix && \
eix-sync && \
eselect news list
# eselect news read 1
# eselect news read 2
# etc.
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

Set USE flags in `/etc/portage/make.conf`:

```bash
ACCEPT_KEYWORDS=~amd64 emerge -1 app-portage/cpuid2cpuflags && \
cpuid2cpuflags | sed -e 's/: /="/' -e 's/$/"/' >> /etc/portage/make.conf && \
cat <<EOF >> /etc/portage/make.conf; echo $?
USE_HARDENED="pie -sslv3 -suid"
USE="\${CPU_FLAGS_X86} \${USE_HARDENED} fish-completion"

EOF
```

Update system. If any config files need to be merged the diff is shown by `dispatch-conf` in color:

```bash
sed -i "s/diff=\"diff -Nu '%s' '%s'\"/diff=\"diff --color=always -Nu '%s' '%s'\"/" /etc/dispatch-conf.conf && \
emerge -avuDN --with-bdeps=y --noconfmem --complete-graph=y @world
```

Make sure that `app-editors/nano` won't be removed and remove extraneous packages (should be only `app-misc/yq` and `app-portage/cpuid2cpuflags`):

```bash
emerge --select --noreplace app-editors/nano && \
emerge --depclean -a
```

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

## Kernel

Install [LTS kernel](https://www.kernel.org/category/releases.html):

```bash
INSTALL_LTS_KERNEL="true" && (
cat <<EOF >> /etc/portage/package.accept_keywords/main
sys-kernel/gentoo-kernel-bin ~amd64
sys-kernel/gentoo-sources ~amd64
EOF
) && (
[ "${INSTALL_LTS_KERNEL}" == "true" ] && \
cat <<EOF >> /etc/portage/package.mask/main
>=sys-kernel/gentoo-kernel-bin-5.11
>=sys-kernel/gentoo-sources-5.11
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

Add [genkernel user patches](https://github.com/duxsco/gentoo-genkernel-patches):

```bash
mkdir -p /etc/portage/patches/sys-kernel/genkernel && \
GENKERNEL_VERSION="$(emerge --search '%^sys-kernel/genkernel$' | grep -i 'latest version available' | awk '{print $NF}')" && (
su -l david -c "curl -fsSL --proto '=https' --tlsv1.3 \"https://raw.githubusercontent.com/duxsco/gentoo-genkernel-patches/${GENKERNEL_VERSION}/defaults_initrd.scripts.patch\"" > /etc/portage/patches/sys-kernel/genkernel/defaults_initrd.scripts.patch
) && (
su -l david -c "curl -fsSL --proto '=https' --tlsv1.3 \"https://raw.githubusercontent.com/duxsco/gentoo-genkernel-patches/${GENKERNEL_VERSION}/defaults_linuxrc.patch\"" > /etc/portage/patches/sys-kernel/genkernel/defaults_linuxrc.patch
); echo $?
```

Verify the patches (copy&paste one after the other):

```bash
# Switch to non-root user. All following commands are executed by non-root.
su - david

# Create GnuPG homedir
( umask 0077 && mkdir /tmp/gpgHomeDir )

# Fetch the public key; ADJUST THE MAIL ADDRESS!
gpg --homedir /tmp/gpgHomeDir --auto-key-locate clear,dane --locate-external-key d at "my github username" dot de

# Update ownertrust
echo "3AAE5FC903BB199165D4C02711BE5F68440E0758:6:" | gpg --homedir /tmp/gpgHomeDir --import-ownertrust

# Switch to temp directory
cd "$(mktemp -d)"

# Download files
GENKERNEL_VERSION="$(emerge --search '%^sys-kernel/genkernel$' | grep -i 'latest version available' | awk '{print $NF}')"
curl --location --proto '=https' --tlsv1.3 --remote-name-all "https://raw.githubusercontent.com/duxsco/gentoo-genkernel-patches/${GENKERNEL_VERSION}/sha256.txt{,.asc}"

# Verify GPG signature. Btw, the GPG key is the same one I use to sign my commits:
# https://github.com/duxsco/gentoo-genkernel-patches/commits/main
gpg --homedir /tmp/gpgHomeDir --verify sha256.txt.asc sha256.txt
gpg: Signature made Mi 18 Aug 2021 23:11:32 CEST
gpg:                using ECDSA key 7A16FF0E6B3B642B5C927620BFC38358839C0712
gpg: Good signature from "David Sardari <d@XXXXX.de>" [ultimate]

# Add paths to sha256.txt and verify
sed 's|  |  /etc/portage/patches/sys-kernel/genkernel/|' sha256.txt | sha256sum -c -
/etc/portage/patches/sys-kernel/genkernel/defaults_initrd.scripts.patch: OK
/etc/portage/patches/sys-kernel/genkernel/defaults_linuxrc.patch: OK

# Switch back to root
exit
```

Install genkernel, filesystem and device mapper tools:

```bash
echo "sys-kernel/linux-firmware linux-fw-redistributable no-source-code" >> /etc/portage/package.license && \
emerge sys-fs/btrfs-progs sys-fs/cryptsetup sys-kernel/genkernel
```

If you use more than one disk, install `sys-fs/mdadm`:

```bash
emerge -av sys-fs/mdadm
```

Configure genkernel:

```bash
cp -av /etc/genkernel.conf{,.old} && \
(
    eix -I -e sys-fs/mdadm && \
    sed -i 's/^#MDADM="no"$/MDADM="yes"/' /etc/genkernel.conf || \
    true
) && \
sed -i \
-e 's/^#MENUCONFIG="no"$/MENUCONFIG="yes"/' \
-e 's/^#MOUNTBOOT="yes"$/MOUNTBOOT="yes"/' \
-e 's/^#SAVE_CONFIG="yes"$/SAVE_CONFIG="yes"/' \
-e 's/^#LUKS="no"$/LUKS="yes"/' \
-e 's/^#BTRFS="no"$/BTRFS="yes"/' \
-e 's/^#BOOTLOADER="no"$/BOOTLOADER="grub2"/' \
-e 's/^#MODULEREBUILD="yes"$/MODULEREBUILD="yes"/' \
-e 's/^#INITRAMFS_OVERLAY=""$/INITRAMFS_OVERLAY="\/key"/' /etc/genkernel.conf && \
diff -y --suppress-common-lines /etc/genkernel.conf /etc/genkernel.conf.old
rm /etc/genkernel.conf.old
```

Set /etc/fstab. `/boot` entry is required by `sys-kernel/genkernel`:

```bash
echo "" >> /etc/fstab && \

(
cat <<EOF | column -t >> /etc/fstab
$(find /devEfi* -maxdepth 0 | while read -r I; do
  echo "UUID=$(blkid -s UUID -o value "$I")   "${I/devE/e}"                   vfat  noatime,noauto             0 0"
done)
UUID=$(blkid -s UUID -o value "/mapperBoot")        /boot                   btrfs noatime,noauto             0 0
UUID=$(blkid -s UUID -o value "/mapperSwap")               none                    swap  sw                         0 0
UUID=$(blkid -s UUID -o value /mapperRoot)   /                       btrfs noatime,subvol=@root       0 0
UUID=$(blkid -s UUID -o value /mapperRoot)   /home                   btrfs noatime,subvol=@home       0 0
UUID=$(blkid -s UUID -o value /mapperRoot)   /var/cache/distfiles    btrfs noatime,subvol=@distfiles  0 0
UUID=$(blkid -s UUID -o value /mapperRoot)   /var/db/repos/gentoo    btrfs noatime,subvol=@portage    0 0
EOF
) && \
find /devEfi* -maxdepth 0 | while read -r I; do
  mkdir "${I/devE/e}"
  mount "${I/devE/e}"
done
echo $?
```

(Optional, but recommended) Use `TMPFS` to compile and for `/tmp`. This is recommended for SSDs and to speed up things.

```bash
echo "" >> /etc/fstab

TMPFS_SIZE=4G
cat <<EOF | column -t >> /etc/fstab
tmpfs /tmp     tmpfs noatime,nodev,nosuid,mode=1777,size=${TMPFS_SIZE},uid=root,gid=root 0 0
tmpfs /var/tmp tmpfs noatime,nodev,nosuid,mode=1777,size=${TMPFS_SIZE},uid=root,gid=root 0 0
EOF
```

Download and verify [gkb2gs](https://github.com/duxsco/gentoo-gkb2gs) (copy&paste one after the other):

```bash
su -l david -c "curl -fsSL --proto '=https' --tlsv1.3 https://raw.githubusercontent.com/duxsco/gentoo-gkb2gs/main/gkb2gs.sh" > /usr/local/sbin/gkb2gs.sh

# Switch to non-root
su - david

# Switch to temp directory
cd "$(mktemp -d)"

# Download files
curl --location --proto '=https' --tlsv1.3 --remote-name-all "https://raw.githubusercontent.com/duxsco/gentoo-gkb2gs/main/gkb2gs.sh.sha256{,.asc}"

# And, verify as already done above for genkernel user patches
gpg --homedir /tmp/gpgHomeDir --verify gkb2gs.sh.sha256.asc gkb2gs.sh.sha256
sed 's|  |  /usr/local/sbin/|' gkb2gs.sh.sha256 | sha256sum -c -

# Switch back to root
exit
```

Make script executable and create kernel config:

```bash
# Create directory to store kernel configs
mkdir /etc/kernels

chmod u+x /usr/local/sbin/gkb2gs.sh
gkb2gs.sh
```

If you have an Intel CPU install `sys-firmware/intel-microcode`. Otherwise, follow the [Gentoo wiki instruction](https://wiki.gentoo.org/wiki/AMD_microcode) to use the AMD microcode.

```bash
echo "sys-firmware/intel-microcode intel-ucode" >> /etc/portage/package.license && \
emerge sys-firmware/intel-microcode && \
echo "MICROCODE_SIGNATURES=\"-s $(iucode_tool -S 2>&1 | grep -Po "with signature \K.*")\"" >> /etc/portage/make.conf && \
emerge sys-firmware/intel-microcode; echo $?
```

CPU microcode:

```bash
ls -1 /lib/firmware/intel-ucode/* | sed 's#/lib/firmware/##'
```

... outputs `intel-ucode/06-a5-02` in my case. Adjust below kernel config accordingly.

Build kernel and initramfs:

```bash
# I usually make following changes:
#     Processor type and features  --->
#         [ ] Support for extended (non-PC) x86 platforms
#             Processor family (Core 2/newer Xeon)  --->
#         <*> CPU microcode loading support
#         [*]   Intel microcode loading support
#     Device Drivers  --->
#         Generic Driver Options --->
#             Firmware Loader --->
#                 -*-   Firmware loading facility
#                 (intel-ucode/06-a5-02) Build named firmware blobs into the kernel binary
#                 (/lib/firmware) Firmware blobs root directory (NEW)
#                 [ ] Enable the firmware sysfs fallback mechanism
#     Kernel hacking  --->
#         Generic Kernel Debugging Instruments  --->
#             [ ] Magic SysRq key
#         [ ] Remote debugging over FireWire early on boot
genkernel all
```

## GRUB

Setup grub:

```bash
echo "sys-boot/grub -* device-mapper grub_platforms_efi-64" >> /etc/portage/package.use/main && \
emerge sys-boot/grub; echo $?
```

Configure grub:

```bash
(
cat <<EOF >> /etc/default/grub

MY_CRYPT_ROOT="$(blkid -s UUID -o value /devRoot* | sed 's/^/crypt_roots=UUID=/' | paste -d " " -s -) root_key=key"
MY_CRYPT_SWAP="$(blkid -s UUID -o value /devSwap* | sed 's/^/crypt_swaps=UUID=/' | paste -d " " -s -) swap_key=key"
MY_FS="rootfstype=btrfs rootflags=subvol=@root"
MY_CPU="mitigations=auto,nosmt"
MY_MOD="dobtrfs domdadm"
GRUB_CMDLINE_LINUX_DEFAULT="\${MY_CRYPT_ROOT} \${MY_CRYPT_SWAP} \${MY_FS} \${MY_CPU} \${MY_MOD} keymap=de"
GRUB_ENABLE_CRYPTODISK="y"
GRUB_DISABLE_OS_PROBER="y"
EOF
) && \

NUMBER_EFI="$(find /efi* -maxdepth 0 -type d | wc -l)" && \
(
find /efi* -maxdepth 0 -type d | while read -r I; do
  grub-install --target=x86_64-efi --efi-directory="$I" --bootloader-id="gentoo${I#/efi}"; echo $?; sync
  (( NUMBER_EFI-- ))
  if [[ $NUMBER_EFI -ne 0 ]]; then
    rm -rf /boot/grub
  fi
done
) && \
grub-mkconfig -o /boot/grub/grub.cfg; echo $?
```

## Configuration

Set hostname:

```bash
sed -i 's/^hostname="localhost"/hostname="micro"/' /etc/conf.d/hostname
```

(Optional) Set IP address:

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
echo "app-admin/sysklogd logrotate" >> /etc/portage/package.use/main && \
emerge app-admin/sysklogd && \
rc-update add sysklogd default; echo $?
```

Setup cronie:

```bash
emerge --select --noreplace sys-process/cronie && \
rc-update add cronie default; echo $?
```

(Optional) Enable ssh service:

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
/bin/fish -c 'alias cp="cp -i"; alias mv="mv -i"; alias rm="rm -i"; funcsave cp; funcsave mv; funcsave rm; fish_config prompt choose terlar; fish_config prompt save'
su -l david -c "/bin/fish -c 'alias cp=\"cp -i\"; alias mv=\"mv -i\"; alias rm=\"rm -i\"; funcsave cp; funcsave mv; funcsave rm; fish_config prompt choose terlar; fish_config prompt save'"
```

  - If you have `sys-fs/mdadm` installed:

```bash
echo "" >> /etc/mdadm.conf && \
mdadm --detail --scan >> /etc/mdadm.conf
```

  - rng-tools:

```bash
echo "sys-apps/rng-tools jitterentropy" >> /etc/portage/package.use/main && \
emerge sys-apps/rng-tools && \
rc-update add rngd default; echo $?
```

  - ssh (optional). Don't forget to fill `~/.ssh/authorized_keys`:

```bash
( umask 0177 && touch /home/david/.ssh/authorized_keys ) && \
chown david: /home/david/.ssh/authorized_keys && \
cp -av /etc/ssh/sshd_config{,.old} && \
sed -i \
-e 's/^#Port 22$/Port 50022/' \
-e 's/^#PermitRootLogin prohibit-password$/PermitRootLogin no/' \
-e 's/^#PasswordAuthentication yes/PasswordAuthentication no/' \
-e 's/^#ChallengeResponseAuthentication yes$/ChallengeResponseAuthentication no/' \
-e 's/^#X11Forwarding no$/X11Forwarding no/' /etc/ssh/sshd_config && \
(
cat <<EOF >> /etc/ssh/sshd_config

KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
HostKeyAlgorithms ssh-ed25519
Ciphers chacha20-poly1305@openssh.com,aes128-gcm@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256,hmac-sha2-512

AllowUsers david
EOF
) && \
ssh-keygen -A && \
sshd -t && \
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub; echo $?
diff /etc/ssh/sshd_config{,.old}
```

Setup client SSH config:

```
cat <<EOF > /home/david/.ssh/config
AddKeysToAgent no
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
HostKeyAlgorithms ssh-ed25519-cert-v01@openssh.com,sk-ssh-ed25519-cert-v01@openssh.com,ssh-ed25519,sk-ssh-ed25519@openssh.com
Ciphers chacha20-poly1305@openssh.com,aes128-gcm@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256,hmac-sha2-512
HashKnownHosts no
StrictHostKeyChecking ask
EOF
chown david: /home/david/.ssh/config
```

  - sysrq (if you don't want to disable in kernel):

```bash
sed -i 's/#kernel.sysrq = 0/kernel.sysrq = 0/' /etc/sysctl.conf
```

  - misc tools:

```bash
emerge app-misc/screen app-portage/gentoolkit app-admin/eclean-kernel; echo $?
```

## Cleanup and reboot

  - stage3 and dev* files:

```bash
rm -fv /stage3-amd64-hardened-openrc-* /portage-latest.tar.xz* /devBoot /devEfi* /devRoot* /devSwap* /mapperBoot /mapperSwap /mapperRoot; echo $?
```

  - exit and reboot (copy&paste one after the other):

```bash
exit
exit
cd
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -R /mnt/gentoo
reboot
```

## Other Gentoo Linux repos

https://github.com/duxsco?tab=repositories&q=gentoo-
