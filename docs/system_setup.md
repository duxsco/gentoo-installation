## 6.1. Portage Setup

Make "dispatch-conf" show [diffs in color](https://wiki.gentoo.org/wiki/Dispatch-conf#Changing_diff_or_merge_tools) and use [vimdiff for merging](https://wiki.gentoo.org/wiki/Dispatch-conf#Use_.28g.29vimdiff_to_merge_changes):

```shell hl_lines="1"
rsync -a /etc/dispatch-conf.conf /etc/._cfg0000_dispatch-conf.conf && \
sed -i \
-e "s/diff=\"diff -Nu '%s' '%s'\"/diff=\"diff --color=always -Nu '%s' '%s'\"/" \
-e "s/merge=\"sdiff --suppress-common-lines --output='%s' '%s' '%s'\"/merge=\"vimdiff -c'saveas %s' -c next -c'setlocal noma readonly' -c prev %s %s\"/" \
/etc/._cfg0000_dispatch-conf.conf && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Install [app-portage/cpuid2cpuflags](https://wiki.gentoo.org/wiki/CPU_FLAGS_X86#Using_cpuid2cpuflags) to further configure [make.conf](https://wiki.gentoo.org/wiki//etc/portage/make.conf) in the next codeblock:

```shell
emerge --oneshot app-portage/cpuid2cpuflags
```

Configure [make.conf](https://wiki.gentoo.org/wiki//etc/portage/make.conf) (copy&paste one after the other):

```shell hl_lines="1"
rsync -av /etc/portage/make.conf /etc/portage/._cfg0000_make.conf

# If you use distcc, beware of:
# https://wiki.gentoo.org/wiki/Distcc#-march.3Dnative
#
# You could resolve "-march=native" with app-misc/resolve-march-native
sed -i 's/COMMON_FLAGS="-O2 -pipe"/COMMON_FLAGS="-march=native -O2 -pipe"/' /etc/portage/._cfg0000_make.conf

# https://wiki.gentoo.org/wiki/EMERGE_DEFAULT_OPTS
# https://wiki.gentoo.org/wiki/Binary_package_guide#Excluding_creation_of_some_packages
# for all other flags, take a look at "man emerge" or
# https://gitweb.gentoo.org/proj/portage.git/tree/man/emerge.1
echo 'EMERGE_DEFAULT_OPTS="--buildpkg --buildpkg-exclude '\''*/*-bin sys-kernel/* virtual/*'\'' --noconfmem --with-bdeps=y --complete-graph=y"' >> /etc/portage/._cfg0000_make.conf

# https://wiki.gentoo.org/wiki/Localization/Guide#L10N
# https://wiki.gentoo.org/wiki/Localization/Guide#LINGUAS
echo '
L10N="de"
LINGUAS="${L10N}"' >> /etc/portage/._cfg0000_make.conf

# https://wiki.gentoo.org/wiki/GENTOO_MIRRORS
# https://www.gentoo.org/downloads/mirrors/
echo '
GENTOO_MIRRORS="https://ftp-stud.hs-esslingen.de/pub/Mirrors/gentoo/ https://ftp.fau.de/gentoo/ https://ftp.tu-ilmenau.de/mirror/gentoo/"' >> /etc/portage/._cfg0000_make.conf

# https://wiki.gentoo.org/wiki/Handbook:AMD64/Full/Portage#Fetch_commands
#
# Default values from /usr/share/portage/config/make.globals are:
# FETCHCOMMAND="wget -t 3 -T 60 --passive-ftp -O \"\${DISTDIR}/\${FILE}\" \"\${URI}\""
# RESUMECOMMAND="wget -c -t 3 -T 60 --passive-ftp -O \"\${DISTDIR}/\${FILE}\" \"\${URI}\""
# File in git: https://gitweb.gentoo.org/proj/portage.git/tree/cnf/make.globals
#
# They are insufficient in my opinion.
# Thus, I am enforcing TLSv1.2 or greater, secure TLSv1.2 cipher suites and https-only.
# TLSv1.3 cipher suites are secure. Thus, I don't set "--tls13-ciphers".
echo 'FETCHCOMMAND="curl --fail --silent --show-error --location --proto '\''=https'\'' --tlsv1.2 --ciphers '\''ECDHE+AESGCM+AES256:ECDHE+CHACHA20:ECDHE+AESGCM+AES128'\'' --retry 2 --connect-timeout 60 -o \"\${DISTDIR}/\${FILE}\" \"\${URI}\""
RESUMECOMMAND="${FETCHCOMMAND} --continue-at -"' >> /etc/portage/._cfg0000_make.conf

# Some useflags I set for personal use.
# Feel free to adjust as with any other codeblock. 😄
echo '
USE_HARDENED="caps pie -sslv3 -suid verify-sig"
USE="${USE_HARDENED} fish-completion"' >> /etc/portage/._cfg0000_make.conf

# https://wiki.gentoo.org/wiki/CPU_FLAGS_X86#Invocation
echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags
```

If you don't live in Germany, you probably should change [GENTOO_MIRRORS](https://wiki.gentoo.org/wiki/GENTOO_MIRRORS) previously set in above codeblock. You can pick the mirrors from the [mirror list](https://www.gentoo.org/downloads/mirrors/), use [mirrorselect](https://wiki.gentoo.org/wiki/Mirrorselect) or do as I do and select local/regional, IPv4/IPv6 dual-stack and TLSv1.3 supporting mirrors (copy&paste one after the other):

```shell
# Install app-misc/yq
ACCEPT_KEYWORDS=~amd64 emerge --oneshot app-misc/yq

# Get a list of country codes and names:
curl -fsSL --proto '=https' --tlsv1.3 https://api.gentoo.org/mirrors/distfiles.xml | xq -r '.mirrors.mirrorgroup[] | "\(.["@country"]) \(.["@countryname"])"' | sort -k2.2

# Choose your countries the mirrors should be located in:
country='"AU","BE","BR","CA","CH","CL","CN","CZ","DE","DK","ES","FR","GR","HK","IL","IT","JP","KR","KZ","LU","NA","NC","NL","PH","PL","PT","RO","RU","SG","SK","TR","TW","UK","US","ZA"'

# Get a list of mirrors available over IPv4/IPv6 dual-stack in the countries of your choice with TLSv1.3 support
curl -fsSL --proto '=https' --tlsv1.3 https://api.gentoo.org/mirrors/distfiles.xml | xq -r ".mirrors.mirrorgroup[] | select([.\"@country\"] | inside([${country}])) | .mirror | if type==\"array\" then .[] else . end | .uri | if type==\"array\" then .[] else . end | select(.\"@protocol\" == \"http\" and .\"@ipv4\" == \"y\" and .\"@ipv6\" == \"y\" and (.\"#text\" | startswith(\"https://\"))) | .\"#text\"" | while read -r i; do
  if curl -fs --proto '=https' --tlsv1.3 -I "${i}" >/dev/null; then
    echo "${i}"
  fi
done
```

I prefer English manpages and ignore above [L10N](https://wiki.gentoo.org/wiki/Localization/Guide#L10N) setting for "sys-apps/man-pages". Makes using Stackoverflow easier :wink:.

```shell
echo "sys-apps/man-pages -l10n_de" >> /etc/portage/package.use/main && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Mitigate [CVE-2022-29154](https://bugs.gentoo.org/show_bug.cgi?id=CVE-2022-29154) among others before using "rsync" via "eix-sync":

```shell
echo 'net-misc/rsync ~amd64' >> /etc/portage/package.accept_keywords/main && \
emerge --oneshot net-misc/rsync && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Install [app-portage/eix](https://wiki.gentoo.org/wiki/Eix):

```shell
emerge -at app-portage/eix
```

Execute ["eix-sync"](https://wiki.gentoo.org/wiki/Eix#Method_2:_Using_eix-sync):

```shell
eix-sync && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Read [Gentoo news items](https://www.gentoo.org/glep/glep-0042.html):

```shell
eselect news list
# eselect news read 1
# eselect news read 2
# etc.
```

(Optional) Switch over to the custom [hardened](https://wiki.gentoo.org/wiki/Project:Hardened) and [merged-usr](https://www.freedesktop.org/wiki/Software/systemd/TheCaseForTheUsrMerge/) profile. Additional ressources:

- [My custom profiles](https://github.com/duxsco/gentoo-installation/tree/main/overlay/duxsco/profiles)
- [Creating custom profiles](https://wiki.gentoo.org/wiki/Profile_(Portage)#Creating_custom_profiles)
- [Switching to a hardened profile](https://wiki.gentoo.org/wiki/Hardened_Gentoo#Switching_to_a_Hardened_profile)
- [Switching to merged-usr](https://groups.google.com/g/linux.gentoo.dev/c/xqZYsMmCoME/m/XlplgAnTAwAJ)

```shell
env ACCEPT_KEYWORDS="~amd64" emerge --oneshot sys-apps/merge-usr && \
merge-usr && \
eselect profile set duxsco:hardened-systemd && \
env-update && source /etc/profile && export PS1="(chroot) $PS1" && \
emerge --oneshot sys-devel/gcc && \
emerge --oneshot sys-devel/binutils sys-libs/glibc && \
env-update && source /etc/profile && export PS1="(chroot) $PS1" && \
emerge -e @world && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Update the system:

```shell
touch /etc/sysctl.conf && \

# add LUKS volume and systemd-boot support
echo "sys-apps/systemd cryptsetup gnuefi" >> /etc/portage/package.use/main && \
emerge -atuDN @world
```

## 6.2. Non-Root User Creation

Create a [non-root user](https://wiki.gentoo.org/wiki/Handbook:AMD64/Full/Installation#Optional:_User_accounts) with ["wheel" group membership and thus the privilege to use "sudo"](https://wiki.gentoo.org/wiki/FAQ#How_do_I_add_a_normal_user.3F) and set a temporary password compatible with English keyboard layout. Later on, you have to [take care of localisation](/post-boot_configuration/#81-systemd-configuration) and will be able to set a secure password of your choice thereafter.

```shell
useradd -m -G wheel -s /bin/bash david && \
chmod u=rwx,og= /home/david && \
echo -e 'alias cp="cp -i"\nalias mv="mv -i"\nalias rm="rm -i"' >> /home/david/.bash_aliases && \
chown david:david /home/david/.bash_aliases && \
echo 'source "${HOME}/.bash_aliases"' >> /home/david/.bashrc && \
passwd david
```

(Optional, but recommended if you want to use SSH) Create your [~/.ssh/authorized_keys](https://wiki.gentoo.org/wiki/SSH#Passwordless_authentication):

```shell
rsync -av --chown=david:david /etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/root/.ssh/authorized_keys /home/david/.ssh/ && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Setup [app-admin/sudo](https://wiki.gentoo.org/wiki/Sudo):

```shell
echo "app-admin/sudo -sendmail" >> /etc/portage/package.use/main && \
emerge app-admin/sudo && \
{ [[ -d /etc/sudoers.d ]] || mkdir -m u=rwx,g=rx,o= /etc/sudoers.d; } && \
echo "%wheel ALL=(ALL) ALL" | EDITOR="tee" visudo -f /etc/sudoers.d/wheel && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Setup [app-editors/vim](https://wiki.gentoo.org/wiki/Vim):

```shell hl_lines="4"
USE="-verify-sig" emerge --oneshot dev-libs/libsodium && \
emerge --oneshot dev-libs/libsodium app-editors/vim app-vim/molokai && \
emerge --select --noreplace app-editors/vim app-vim/molokai && \
cp -av /etc/portage/make.conf /etc/portage/._cfg0000_make.conf && \
sed -i 's/^USE="\([^"]*\)"$/USE="\1 vim-syntax"/' /etc/portage/._cfg0000_make.conf && \
echo "filetype plugin on
filetype indent on
set number
set paste
syntax on
colorscheme molokai" | tee -a /root/.vimrc >> /home/david/.vimrc  && \
chown david:david /home/david/.vimrc && \
eselect editor set vi && \
eselect vi set vim && \
env-update && source /etc/profile && export PS1="(chroot) $PS1" && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

## 6.3. Configuration of /etc/fstab

Setup [/etc/fstab](https://wiki.gentoo.org/wiki//etc/fstab):

```shell
SWAP_UUID="$(blkid -s UUID -o value /mapperSwap)" && \
SYSTEM_UUID="$(blkid -s UUID -o value /mapperSystem)" && \
echo "" >> /etc/fstab && \
echo "
$(find /devEfi* -maxdepth 0 | while read -r i; do
  echo "UUID=$(blkid -s UUID -o value "$i") ${i/devE/boot\/e} vfat noatime,dmask=0022,fmask=0133 0 0"
done)
UUID=${SWAP_UUID}   none                 swap  sw                        0 0
UUID=${SYSTEM_UUID} /                    btrfs noatime,subvol=@root      0 0
UUID=${SYSTEM_UUID} /home                btrfs noatime,subvol=@home      0 0
UUID=${SYSTEM_UUID} /var/cache/binpkgs   btrfs noatime,subvol=@binpkgs   0 0
UUID=${SYSTEM_UUID} /var/cache/distfiles btrfs noatime,subvol=@distfiles 0 0
UUID=${SYSTEM_UUID} /var/db/repos/gentoo btrfs noatime,subvol=@ebuilds   0 0
UUID=${SYSTEM_UUID} /var/tmp             btrfs noatime,subvol=@var_tmp   0 0
" | column -o " " -t >> /etc/fstab && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

## 6.4. Secure Boot

Credits:

- [https://www.funtoo.org/Secure_Boot](https://www.funtoo.org/Secure_Boot)
- [https://www.rodsbooks.com/efi-bootloaders/secureboot.html](https://www.rodsbooks.com/efi-bootloaders/secureboot.html)
- [https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot)

In order to add your custom keys, "setup mode" must have been enabled in your "UEFI Firmware Settings" before booting into SystemRescueCD. But, you can [install secure boot files later on](/post-boot_configuration/#82-secure-boot-setup) if you missed enabling "setup mode". In the following, however, you have to generate secure boot files either way.

Install required tools:

```shell
echo "sys-boot/mokutil ~amd64" >> /etc/portage/package.accept_keywords/main && \
emerge -at app-crypt/efitools app-crypt/sbsigntools sys-boot/mokutil
```

Create secure boot files:

```shell
mkdir --mode=0700 /etc/gentoo-installation/secureboot && \
pushd /etc/gentoo-installation/secureboot && \

# Create the keys
openssl req -new -x509 -newkey rsa:3072 -subj "/CN=PK/"  -keyout PK.key  -out PK.crt  -days 7300 -nodes -sha256 && \
openssl req -new -x509 -newkey rsa:3072 -subj "/CN=KEK/" -keyout KEK.key -out KEK.crt -days 7300 -nodes -sha256 && \
openssl req -new -x509 -newkey rsa:3072 -subj "/CN=db/"  -keyout db.key  -out db.crt  -days 7300 -nodes -sha256 && \

# Prepare installation in EFI
uuid="$(uuidgen --random)" && \
cert-to-efi-sig-list -g "${uuid}" PK.crt PK.esl && \
cert-to-efi-sig-list -g "${uuid}" KEK.crt KEK.esl && \
cert-to-efi-sig-list -g "${uuid}" db.crt db.esl && \
sign-efi-sig-list -k PK.key  -c PK.crt  PK  PK.esl  PK.auth && \
sign-efi-sig-list -k PK.key  -c PK.crt  KEK KEK.esl KEK.auth && \
sign-efi-sig-list -k KEK.key -c KEK.crt db  db.esl  db.auth && \

popd && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

If the following commands don't work, you have to install "db.auth", "KEK.auth" and "PK.auth" over the "UEFI Firmware Settings" later on. Further information can be found in chapter [8.2. Secure Boot Setup](/post-boot_configuration/#82-secure-boot-setup). Beware that the following commands delete all existing secure boot keys and databases.

```shell
pushd /etc/gentoo-installation/secureboot && \

# Make them mutable
{ chattr -i /sys/firmware/efi/efivars/{PK,KEK,db,dbx}* || true; } && \

# Install keys into EFI (PK last as it will enable Custom Mode locking out further unsigned changes)
efi-updatevar -f db.auth db && \
efi-updatevar -f KEK.auth KEK && \
efi-updatevar -f PK.auth PK && \

# Make them immutable
{ chattr +i /sys/firmware/efi/efivars/{PK,KEK,db,dbx}* || true; } && \

popd && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

## 6.5. Kernel Installation

Install `sys-boot/efibootmgr`:

```shell
emerge -at sys-boot/efibootmgr
```

Setup ESP(s):

```shell
while read -r my_esp; do
  # install the EFI boot manager:
  # https://wiki.archlinux.org/title/systemd-boot#Installing_the_EFI_boot_manager
  bootctl --esp-path="/boot/${my_esp}" install && \

  # create the boot entry
  # https://wiki.gentoo.org/wiki/Efibootmgr#Creating_a_boot_entry
  efibootmgr --create --disk "/dev/$(lsblk -ndo pkname "$(readlink -f "/${my_esp/efi/devEfi}")")" --part 1 --label "gentoo31415efi ${my_esp}" --loader '\EFI\systemd\systemd-bootx64.efi' && \

  # setup systemd-boot
  # https://wiki.gentoo.org/wiki/Systemd-boot#loader.conf
  echo -e "timeout 10\neditor no" > "/boot/${my_esp}/loader/loader.conf" && \

  # move the precreated EFI binary of the rescue system into ESP
  mv "/boot/${my_esp}/systemrescuecd.efi" "/boot/${my_esp}/EFI/Linux/" && \

  # secure boot sign EFI binaries
  sbsign --key /etc/gentoo-installation/secureboot/db.key --cert /etc/gentoo-installation/secureboot/db.crt --output "/boot/${my_esp}/EFI/systemd/systemd-bootx64.efi" "/boot/${my_esp}/EFI/systemd/systemd-bootx64.efi" && \
  sbsign --key /etc/gentoo-installation/secureboot/db.key --cert /etc/gentoo-installation/secureboot/db.crt --output "/boot/${my_esp}/EFI/BOOT/BOOTX64.EFI" "/boot/${my_esp}/EFI/BOOT/BOOTX64.EFI" && \
  sbsign --key /etc/gentoo-installation/secureboot/db.key --cert /etc/gentoo-installation/secureboot/db.crt --output "/boot/${my_esp}/EFI/Linux/systemrescuecd.efi" "/boot/${my_esp}/EFI/Linux/systemrescuecd.efi" && \

  echo -e "\e[1;32mSUCCESS\e[0m"
done < <(grep -Po "^UUID=[0-9A-F]{4}-[0-9A-F]{4}[[:space:]]+/boot/\Kefi[a-z](?=[[:space:]]+vfat[[:space:]]+)" /etc/fstab)
```

Microcode updates are [not necessary for virtual machines](https://unix.stackexchange.com/a/572757). If on bare-metal, install "sys-firmware/intel-microcode" if you have an Intel CPU or follow the [Gentoo wiki instruction](https://wiki.gentoo.org/wiki/AMD_microcode) to update the microcode on AMD systems.

```shell
! grep -q -w "hypervisor" <(grep "^flags[[:space:]]*:[[:space:]]*" /proc/cpuinfo) && \
grep -q "^vendor_id[[:space:]]*:[[:space:]]*GenuineIntel$" /proc/cpuinfo && \
echo "sys-firmware/intel-microcode intel-ucode" >> /etc/portage/package.license && \
echo "sys-firmware/intel-microcode hostonly" >> /etc/portage/package.use/main && \
emerge -at sys-firmware/intel-microcode && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Setup [portage hooks](https://github.com/duxsco/gentoo-installation/blob/main/bin/portage_hook_kernel) that take care of [unified kernel image](https://wiki.archlinux.org/title/Unified_kernel_image) creation and [secure boot signing](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#Manually_with_sbsigntools):

```shell
mkdir -p /etc/portage/env/sys-apps /etc/portage/env/sys-firmware /etc/portage/env/sys-kernel && \
rsync -a --numeric-ids --chown=0:0 --chmod=u=rw,go=r /root/portage_hook_kernel /etc/portage/env/sys-firmware/intel-microcode && \
rsync -a --numeric-ids --chown=0:0 --chmod=u=rw,go=r /root/portage_hook_kernel /etc/portage/env/sys-kernel/gentoo-kernel-bin && \
rsync -a --numeric-ids --chown=0:0 --chmod=u=rw,go=r /root/portage_hook_kernel /etc/portage/env/sys-kernel/linux-firmware && \
rm -f /root/portage_hook_kernel && \
echo 'if [[ ${EBUILD_PHASE} == postinst ]]; then
    while read -r my_esp; do
        bootctl --esp-path="/boot/${my_esp}" --no-variables --graceful update && \
        sbsign --key /etc/gentoo-installation/secureboot/db.key --cert /etc/gentoo-installation/secureboot/db.crt --output "/boot/${my_esp}/EFI/systemd/systemd-bootx64.efi" "/boot/${my_esp}/EFI/systemd/systemd-bootx64.efi" && \
        sbsign --key /etc/gentoo-installation/secureboot/db.key --cert /etc/gentoo-installation/secureboot/db.crt --output "/boot/${my_esp}/EFI/BOOT/BOOTX64.EFI" "/boot/${my_esp}/EFI/BOOT/BOOTX64.EFI"

        if [[ $? -ne 0 ]]; then
cat <<'\''EOF'\''

  ___________________________
< Failed to Secure Boot sign! >
  ---------------------------
         \   ^__^ 
          \  (oo)\_______
             (__)\       )\/\
                 ||----w |
                 ||     ||

EOF
        fi
    done < <(grep -Po "^UUID=[0-9A-F]{4}-[0-9A-F]{4}[[:space:]]+/boot/\Kefi[a-z](?=[[:space:]]+vfat[[:space:]]+)" /etc/fstab)
fi' > /etc/portage/env/sys-apps/systemd && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Setup [sys-kernel/dracut](https://wiki.gentoo.org/wiki/Dracut). If you don't wear tin foil hats :wink:, you may want to change the [line "mitigations=auto,nosmt"](https://www.kernel.org/doc/html/latest/admin-guide/kernel-parameters.html) below (copy&paste one after the other):

```shell
emerge -at sys-kernel/dracut

system_uuid="$(blkid -s UUID -o value /mapperSystem)"
my_crypt_root="$(blkid -s UUID -o value /devSystem* | sed 's/^/rd.luks.uuid=/' | paste -d " " -s -)"
my_crypt_swap="$(blkid -s UUID -o value /devSwap* | sed 's/^/rd.luks.uuid=/' | paste -d " " -s -)"

unset my_systemd_cryptenroll

# If you intend to use systemd-cryptenroll, define this variable:
# my_systemd_cryptenroll=",tpm2-device=auto"

echo "
# make a generic image, but use custom kernel command-line parameters
hostonly=no
hostonly_cmdline=yes

use_fstab=yes
compress=xz
show_modules=yes

# create an unified kernel image
uefi=yes

# integrate microcode updates
early_microcode=yes

# point to the correct UEFI stub loader
uefi_stub=/usr/lib/systemd/boot/efi/linuxx64.efi.stub

# set files used to secure boot sign
uefi_secureboot_cert=/etc/gentoo-installation/secureboot/db.crt
uefi_secureboot_key=/etc/gentoo-installation/secureboot/db.key

# kernel command-line parameters
CMDLINE=(
  ro
  root=UUID=${system_uuid}
  ${my_crypt_root}
  ${my_crypt_swap}
  rd.luks.options=password-echo=no${my_systemd_cryptenroll}
  rootfstype=btrfs
  rootflags=subvol=@root
  mitigations=auto,nosmt
)
kernel_cmdline="\${CMDLINE[*]}"
unset CMDLINE" >> /etc/dracut.conf
```

(Optional) Use [LTS (longterm) kernels](https://kernel.org/category/releases.html):

```shell
echo "\
>=sys-fs/btrfs-progs-5.16
>=sys-kernel/gentoo-kernel-bin-5.16
>=sys-kernel/linux-headers-5.16
>=virtual/dist-kernel-5.16" >> /etc/portage/package.mask/main
```

Install packages required for booting:

```shell
echo "sys-fs/btrfs-progs ~amd64
sys-kernel/gentoo-kernel-bin ~amd64
sys-kernel/linux-headers ~amd64
virtual/dist-kernel ~amd64" >> /etc/portage/package.accept_keywords/main && \

# I prefer to create a "fresh" btrfs FS instead of converting
# reiserfs and ext2/3/4 to btrfs.
echo "sys-fs/btrfs-progs -convert" >> /etc/portage/package.use/main && \

# Dracut will take care of initramfs creation.
echo "sys-kernel/gentoo-kernel-bin -initramfs" >> /etc/portage/package.use/main && \

# Accept required licenses.
echo "sys-kernel/linux-firmware linux-fw-redistributable no-source-code" >> /etc/portage/package.license && \

# Install packages
{
  [ -e /devSwapb ] && \
  emerge -at sys-fs/btrfs-progs sys-fs/mdadm sys-kernel/linux-firmware || \
  emerge -at sys-fs/btrfs-progs sys-kernel/linux-firmware
}
```

Install the [kernel](https://wiki.gentoo.org/wiki/Kernel):

```shell
emerge -at sys-kernel/gentoo-kernel-bin
```

## 6.6. Initial systemd configuration

Do some [initial configuration](https://wiki.gentoo.org/wiki/Systemd#Configuration):

```shell
systemd-firstboot --prompt --setup-machine-id
```

If you **don't** plan to keep your setup slim for the later [SELinux setup](/selinux/), the use of preset files may be s.th. to consider:

> Most services are disabled when systemd is first installed. A "preset" file is provided, and may be used to enable a reasonable set of default services. ([source](https://wiki.gentoo.org/wiki/Systemd#Preset_services))

```shell
systemctl preset-all
# or
systemctl preset-all --preset-mode=enable-only
```

## 6.7. Additional Packages

Setup [/etc/hosts](https://wiki.gentoo.org/wiki/Handbook:AMD64/Installation/System#The_hosts_file) (copy&paste one after the other):

```shell hl_lines="5"
# Set the hostname of your choice
my_hostname="micro"

rsync -a /etc/hosts /etc/._cfg0000_hosts && \
sed -i "s/localhost$/localhost ${my_hostname}/" /etc/._cfg0000_hosts && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

(Optional) Enable the SSH service:

```shell
systemctl --no-reload enable sshd.service
```

Install [app-shells/starship](https://starship.rs/):

```shell
# If you have insufficient ressources, you may want to execute "emerge --oneshot dev-lang/rust-bin" beforehand.
echo "app-shells/starship ~amd64" >> /etc/portage/package.accept_keywords/main && \
emerge app-shells/starship && \
mkdir --mode=0700 /home/david/.config /root/.config && \
touch /home/david/.config/starship.toml && \
chown -R david:david /home/david/.config && \
echo '[hostname]
ssh_only = false
format =  "[$hostname](bold red) "
' | tee /root/.config/starship.toml > /home/david/.config/starship.toml && \
starship preset nerd-font-symbols | tee -a /root/.config/starship.toml >> /home/david/.config/starship.toml && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Install [app-shells/fish](https://wiki.gentoo.org/wiki/Fish):

```shell
echo "=dev-libs/libpcre2-$(qatom -F "%{PVR}" "$(portageq best_visible / dev-libs/libpcre2)") pcre32" >> /etc/portage/package.use/main && \
echo "app-shells/fish ~amd64" >> /etc/portage/package.accept_keywords/main && \
emerge app-shells/fish && \
echo '
# Use fish in place of bash
# keep this line at the bottom of ~/.bashrc
if [[ -z ${chrooted} ]]; then
    if [[ -x /bin/fish ]]; then
        SHELL=/bin/fish exec /bin/fish
    fi
elif [[ -z ${chrooted_su} ]]; then
    export chrooted_su=true
    source /etc/profile && su --login --whitelist-environment=chrooted,chrooted_su
else
    env-update && source /etc/profile && export PS1="(chroot) $PS1"
fi' >> /root/.bashrc && \
echo '
# Use fish in place of bash
# keep this line at the bottom of ~/.bashrc
if [[ -x /bin/fish ]]; then
    SHELL=/bin/fish exec /bin/fish
fi' >> /home/david/.bashrc && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Setup [auto-completion for the fish shell](https://wiki.archlinux.org/title/fish#Command_completion) (copy&paste one after the other):

```shell
# root
/bin/fish -c fish_update_completions

# non-root
su -l david -c "/bin/fish -c fish_update_completions"
```

Enable aliases and starship (copy&paste one after the other):

```shell
su -
exit
su - david
exit
sed -i 's/^end$/    source "$HOME\/.bash_aliases"\n    starship init fish | source\nend/' /root/.config/fish/config.fish
sed -i 's/^end$/    source "$HOME\/.bash_aliases"\n    starship init fish | source\nend/' /home/david/.config/fish/config.fish
```

Install [nerd fonts](https://www.nerdfonts.com/):

```shell
emerge media-libs/fontconfig && \
su -l david -c "curl --proto '=https' --tlsv1.3 -fsSL -o /tmp/FiraCode.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v2.2.2/FiraCode.zip" && \
b2sum -c <<<"9f8ada87945ff10d9eced99369f7c6d469f9eaf2192490623a93b2397fe5b6ee3f0df6923b59eb87e92789840a205adf53c6278e526dbeeb25d0a6d307a07b18  /tmp/FiraCode.zip" && \
mkdir /tmp/FiraCode && \
unzip -d /tmp/FiraCode /tmp/FiraCode.zip && \
rm -f /tmp/FiraCode/*Windows* /tmp/FiraCode/Fura* && \
mkdir /usr/share/fonts/nerd-firacode && \
rsync -a --chown=0:0 --chmod=a=r /tmp/FiraCode/*.ttf /usr/share/fonts/nerd-firacode/ && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

If you have "sys-fs/mdadm" installed ([link](https://wiki.gentoo.org/wiki/Gentoo_installation_tips_and_tricks#Software_RAID)):

```shell hl_lines="2"
[[ -e /devSwapb ]] && \
rsync -a /etc/mdadm.conf /etc/._cfg0000_mdadm.conf && \
echo "" >> /etc/._cfg0000_mdadm.conf && \
mdadm --detail --scan >> /etc/._cfg0000_mdadm.conf && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Setup "net-misc/openssh":

```shell hl_lines="1"
rsync -a /etc/ssh/sshd_config /etc/ssh/._cfg0000_sshd_config && \
sed -i \
-e 's/^#Port 22$/Port 50022/' \
-e 's/^#PermitRootLogin prohibit-password$/PermitRootLogin no/' \
-e 's/^#KbdInteractiveAuthentication yes$/KbdInteractiveAuthentication no/' \
-e 's/^#X11Forwarding no$/X11Forwarding no/' /etc/ssh/._cfg0000_sshd_config && \
grep -q "^PasswordAuthentication no$" /etc/ssh/._cfg0000_sshd_config && \
echo "
AuthenticationMethods publickey

KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

AllowUsers david" >> /etc/ssh/._cfg0000_sshd_config && \
ssh-keygen -A && \
sshd -t && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Write down fingerprints to double check upon initial SSH connection to the Gentoo Linux machine:

```shell
find /etc/ssh/ -type f -name "ssh_host*\.pub" -exec ssh-keygen -vlf {} \;
```

Setup client SSH config:

```shell
echo "AddKeysToAgent no
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
HashKnownHosts no
StrictHostKeyChecking ask
VisualHostKey yes" > /home/david/.ssh/config && \
chown david:david /home/david/.ssh/config && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Disable "magic SysRq" for [security sake](https://wiki.gentoo.org/wiki/Vlock#Disable_SysRq_key):

```shell
echo "kernel.sysrq = 0" > /etc/sysctl.d/99sysrq.conf
```

Misc tools:

```shell
emerge -at app-misc/screen app-portage/gentoolkit
```
