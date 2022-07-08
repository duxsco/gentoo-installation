## 6.1. Portage Setup

Make `dispatch-conf` show diffs in color and use vimdiff for merging:

```bash
rsync -a /etc/dispatch-conf.conf /etc/._cfg0000_dispatch-conf.conf && \
sed -i \
-e "s/diff=\"diff -Nu '%s' '%s'\"/diff=\"diff --color=always -Nu '%s' '%s'\"/" \
-e "s/merge=\"sdiff --suppress-common-lines --output='%s' '%s' '%s'\"/merge=\"vimdiff -c'saveas %s' -c next -c'setlocal noma readonly' -c prev '%s' '%s'\"/" \
/etc/._cfg0000_dispatch-conf.conf
```

Install to be able to configure `/etc/portage/make.conf`:

```bash
emerge -1 app-portage/cpuid2cpuflags
```

Configure portage (copy&paste one after the other):

```bash
rsync -a /etc/portage/make.conf /etc/portage/._cfg0000_make.conf

# If you use distcc, beware of:
# https://wiki.gentoo.org/wiki/Distcc#-march.3Dnative
#
# You could resolve "-march=native" with app-misc/resolve-march-native
sed -i 's/COMMON_FLAGS="-O2 -pipe"/COMMON_FLAGS="-march=native -O2 -pipe"/' /etc/portage/._cfg0000_make.conf

cat <<'EOF' >> /etc/portage/._cfg0000_make.conf
EMERGE_DEFAULT_OPTS="--buildpkg --buildpkg-exclude '*/*-bin sys-kernel/* virtual/*' --noconfmem --with-bdeps=y --complete-graph=y"

L10N="de"
LINGUAS="${L10N}"

GENTOO_MIRRORS="https://ftp-stud.hs-esslingen.de/pub/Mirrors/gentoo/ https://ftp.fau.de/gentoo/ https://ftp.tu-ilmenau.de/mirror/gentoo/"
FETCHCOMMAND="curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --ciphers 'ECDHE+AESGCM+AES256:ECDHE+CHACHA20:ECDHE+AESGCM+AES128' --retry 2 --connect-timeout 60 -o \"\${DISTDIR}/\${FILE}\" \"\${URI}\""
RESUMECOMMAND="${FETCHCOMMAND} --continue-at -"

USE_HARDENED="pie -sslv3 -suid verify-sig"
USE="${USE_HARDENED} fish-completion"

EOF

echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags
```

(Optional) Change `GENTOO_MIRRORS` in `/etc/portage/make.conf` (copy&paste one after the other):

```bash
# Install app-misc/yq
ACCEPT_KEYWORDS=~amd64 emerge -1 app-misc/yq

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

I prefer English manpages and ignore above `L10N` setting for `sys-apps/man-pages`. Makes using Stackoverflow easier 😉.

```bash
echo "sys-apps/man-pages -l10n_de" >> /etc/portage/package.use/main
```

Install `app-portage/eix`:

```bash
emerge -at app-portage/eix
```

Execute `eix-sync`:

```bash
eix-sync
```

Read Gentoo news items:

```
eselect news list
# eselect news read 1
# eselect news read 2
# etc.
```

Update system:

```bash
touch /etc/sysctl.conf && \
echo "sys-apps/systemd cryptsetup gnuefi" >> /etc/portage/package.use/main && \
emerge -atuDN @world
```

## 6.2. Non-Root User Creation

Create a non-root user and set a password you can use with English keyboard layout for now. You can set a secure password after rebooting and taking care of localisation.

```bash
useradd -m -G wheel -s /bin/bash david && \
chmod u=rwx,og= /home/david && \
echo -e 'alias cp="cp -i"\nalias mv="mv -i"\nalias rm="rm -i"' >> /home/david/.bash_aliases && \
chown david:david /home/david/.bash_aliases && \
echo 'source "${HOME}/.bash_aliases"' >> /home/david/.bashrc && \
passwd david
```

(Optional) Create your `authorized_keys`:

```bash
rsync -av --chown=david:david /etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/root/.ssh/authorized_keys /home/david/.ssh/
```

Setup sudo:

```bash
echo "app-admin/sudo -sendmail" >> /etc/portage/package.use/main && \
emerge app-admin/sudo && \
echo "%wheel ALL=(ALL) ALL" | EDITOR="tee" visudo -f /etc/sudoers.d/wheel; echo $?
```

Setup vim:

```bash
USE="-verify-sig" emerge -1 dev-libs/libsodium && \
emerge -1 dev-libs/libsodium app-editors/vim && \
emerge --select --noreplace app-editors/vim && \
sed -i 's/^USE="\([^"]*\)"$/USE="\1 vim-syntax"/' /etc/portage/make.conf && \
echo "filetype plugin on
filetype indent on
set number
set paste
syntax on" | tee -a /root/.vimrc >> /home/david/.vimrc  && \
chown david:david /home/david/.vimrc && \
eselect editor set vi && \
eselect vi set vim && \
env-update && source /etc/profile && export PS1="(chroot) $PS1"; echo $?
```

## 6.3. Configuration Of /etc/fstab

Setup /etc/fstab:

```bash
echo "" >> /etc/fstab
echo "
$(find /devEfi* -maxdepth 0 | while read -r i; do
  echo "UUID=$(blkid -s UUID -o value "$i")  ${i/devE/e}          vfat  noatime,dmask=0022,fmask=0133 0 0"
done)
UUID=$(blkid -s UUID -o value /mapperSwap)   none                 swap  sw                            0 0
UUID=$(blkid -s UUID -o value /mapperSystem) /                    btrfs noatime,subvol=@root          0 0
UUID=$(blkid -s UUID -o value /mapperSystem) /home                btrfs noatime,subvol=@home          0 0
UUID=$(blkid -s UUID -o value /mapperSystem) /var/cache/binpkgs   btrfs noatime,subvol=@binpkgs       0 0
UUID=$(blkid -s UUID -o value /mapperSystem) /var/cache/distfiles btrfs noatime,subvol=@distfiles     0 0
UUID=$(blkid -s UUID -o value /mapperSystem) /var/db/repos/gentoo btrfs noatime,subvol=@ebuilds       0 0" | column -o " " -t >> /etc/fstab && \
find /devEfi* -maxdepth 0 | while read -r i; do
  mkdir "${i/devE/e}"
  mount "${i/devE/e}"
done; echo $?
```

## 6.4. Secure Boot

Credits:

- [https://ruderich.org/simon/notes/secure-boot-with-grub-and-signed-linux-and-initrd](https://ruderich.org/simon/notes/secure-boot-with-grub-and-signed-linux-and-initrd)
- [https://www.funtoo.org/Secure_Boot](https://www.funtoo.org/Secure_Boot)
- [https://www.rodsbooks.com/efi-bootloaders/secureboot.html](https://www.rodsbooks.com/efi-bootloaders/secureboot.html)
- [https://fit-pc.com/wiki/index.php?title=Linux:_Secure_Boot](https://fit-pc.com/wiki/index.php?title=Linux:_Secure_Boot)
- [https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot)

In order to add your custom keys `Setup Mode` must have been enabled in your `UEFI Firmware Settings` before booting into SystemRescueCD. But, you can install Secure Boot files later on if you missed enabling `Setup Mode`. In the following, however, you have to generate Secure Boot files either way.

Install required tools on your system:

```bash
echo "sys-boot/mokutil ~amd64" >> /etc/portage/package.accept_keywords/main && \
emerge -at app-crypt/efitools app-crypt/sbsigntools sys-boot/mokutil
```

Create Secure Boot keys and certificates:

```bash
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
popd; echo $?
```

If the following commands don't work you have to install `db.auth`, `KEK.auth` and `PK.auth` over the `UEFI Firmware Settings` upon reboot after the completion of this installation guide. Further information can be found at the end of this installation guide. Beware that the following commands delete all existing keys.

```bash
pushd /etc/gentoo-installation/secureboot && \

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

## 6.5. Kernel Installation

Setup ESP(s):

```bash
while read -r my_esp; do
  bootctl --esp-path="/${my_esp}" install && \
  efibootmgr -b "$(efibootmgr -v | grep -Po "^Boot\K[0-9]+(?=\*[[:space:]]+Linux Boot Manager[[:space:]]+)")" -B && \
  efibootmgr --create --disk "/dev/$(lsblk -ndo pkname "$(readlink -f "/${my_esp/efi/devEfi}")")" --part 1 --label "gentoo31415efi ${my_esp}" --loader '\EFI\systemd\systemd-bootx64.efi' && \
  echo -e "timeout 10\neditor no" > "/${my_esp}/loader/loader.conf" && \
  sbsign --key /etc/gentoo-installation/secureboot/db.key --cert /etc/gentoo-installation/secureboot/db.crt --output "/${my_esp}/EFI/systemd/systemd-bootx64.efi" "/${my_esp}/EFI/systemd/systemd-bootx64.efi" && \
  sbsign --key /etc/gentoo-installation/secureboot/db.key --cert /etc/gentoo-installation/secureboot/db.crt --output "/${my_esp}/EFI/BOOT/BOOTX64.EFI" "/${my_esp}/EFI/BOOT/BOOTX64.EFI"
  echo $?
done < <(grep -Po "^UUID=[0-9A-F]{4}-[0-9A-F]{4}[[:space:]]+/\Kefi[a-z](?=[[:space:]]+vfat[[:space:]]+)" /etc/fstab)
```

Setup portage hook:

```bash
mkdir -p /etc/portage/env/sys-apps /etc/portage/env/sys-firmware /etc/portage/env/sys-kernel && \
rsync -a --numeric-ids --chown=0:0 --chmod=u=rw,go=r /root/portage_hook_kernel /etc/portage/env/sys-firmware/intel-microcode && \
rsync -a --numeric-ids --chown=0:0 --chmod=u=rw,go=r /root/portage_hook_kernel /etc/portage/env/sys-kernel/gentoo-kernel-bin && \
rsync -a --numeric-ids --chown=0:0 --chmod=u=rw,go=r /root/portage_hook_kernel /etc/portage/env/sys-kernel/linux-firmware && \
rm -f /root/portage_hook_kernel && \
echo 'if [[ ${EBUILD_PHASE} == postinst ]]; then
    while read -r my_esp; do
        bootctl --esp-path="/${my_esp}" --no-variables --graceful update && \
        sbsign --key /etc/gentoo-installation/secureboot/db.key --cert /etc/gentoo-installation/secureboot/db.crt --output "/${my_esp}/EFI/systemd/systemd-bootx64.efi" "/${my_esp}/EFI/systemd/systemd-bootx64.efi" && \
        sbsign --key /etc/gentoo-installation/secureboot/db.key --cert /etc/gentoo-installation/secureboot/db.crt --output "/${my_esp}/EFI/BOOT/BOOTX64.EFI" "/${my_esp}/EFI/BOOT/BOOTX64.EFI"

        if [[ $? -ne 0 ]]; then
cat <<EOF

  ___________________________
< Failed to Secure Boot sign! >
  ---------------------------
         \   ^__^ 
          \  (oo)\_______
             (__)\       )\/\\
                 ||----w |
                 ||     ||

EOF
        fi
    done < <(grep -Po "^UUID=[0-9A-F]{4}-[0-9A-F]{4}[[:space:]]+/\Kefi[a-z](?=[[:space:]]+vfat[[:space:]]+)" /etc/fstab)
fi' > /etc/portage/env/sys-apps/systemd; echo $?
```

Microcode updates are not necessary for virtual systems. Otherwise, install `sys-firmware/intel-microcode` if you have an Intel CPU. Or, follow the [Gentoo wiki instruction](https://wiki.gentoo.org/wiki/AMD_microcode) to update the microcode on AMD systems.

```bash
! grep -q -w "hypervisor" <(grep "^flags[[:space:]]*:[[:space:]]*" /proc/cpuinfo) && \
grep -q "^vendor_id[[:space:]]*:[[:space:]]*GenuineIntel$" /proc/cpuinfo && \
echo "sys-firmware/intel-microcode intel-ucode" >> /etc/portage/package.license && \
echo "sys-firmware/intel-microcode hostonly" >> /etc/portage/package.use/main && \
emerge -at sys-firmware/intel-microcode; echo $?
```

Setup `sys-kernel/dracut` (copy&paste one after the other):

```bash
emerge -at sys-kernel/dracut

rescue_uuid="$(blkid -s UUID -o value /devRescue | tr -d '-')"
system_uuid="$(blkid -s UUID -o value /mapperSystem)"
my_crypt_root="$(blkid -s UUID -o value /devSystem* | sed 's/^/rd.luks.uuid=/' | paste -d " " -s -)"
my_crypt_swap="$(blkid -s UUID -o value /devSwap* | sed 's/^/rd.luks.uuid=/' | paste -d " " -s -)"

# If you intend to use systemd-cryptenroll, define this variable:
# my_systemd_cryptenroll=",tpm2-device=auto"

cat <<EOF >> /etc/dracut.conf

hostonly=no
hostonly_cmdline=yes
use_fstab=yes
#compress=xz
show_modules=yes

uefi=yes
early_microcode=yes
uefi_stub=/usr/lib/systemd/boot/efi/linuxx64.efi.stub
uefi_secureboot_cert=/etc/gentoo-installation/secureboot/db.crt
uefi_secureboot_key=/etc/gentoo-installation/secureboot/db.key
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
unset CMDLINE
EOF
```

Install tools required for booting:

```bash
install_lts_kernel="true" && \
echo "sys-fs/btrfs-progs ~amd64
sys-kernel/gentoo-kernel-bin ~amd64
sys-kernel/linux-headers ~amd64
virtual/dist-kernel ~amd64" >> /etc/portage/package.accept_keywords/main && \
if [[ ${install_lts_kernel} == true ]]; then
cat <<EOF >> /etc/portage/package.mask/main
>=sys-fs/btrfs-progs-5.16
>=sys-kernel/gentoo-kernel-bin-5.16
>=sys-kernel/linux-headers-5.16
>=virtual/dist-kernel-5.16
EOF
fi && \
echo "sys-fs/btrfs-progs -convert" >> /etc/portage/package.use/main && \
echo "sys-kernel/gentoo-kernel-bin -initramfs" >> /etc/portage/package.use/main && \
echo "sys-kernel/linux-firmware linux-fw-redistributable no-source-code" >> /etc/portage/package.license && \
emerge -at sys-fs/btrfs-progs $(if [[ -e /devSwapb ]]; then echo -n "sys-fs/mdadm"; fi) sys-kernel/linux-firmware
```

Install the [kernel](https://www.kernel.org/category/releases.html):

```bash
emerge -at sys-kernel/gentoo-kernel-bin
```

## 6.6. Additional Packages

Set `/etc/hosts`:

```bash
rsync -a /etc/hosts /etc/._cfg0000_hosts && \
sed -i 's/localhost$/localhost micro/' /etc/._cfg0000_hosts
```

(Optional) Enable ssh service:

```bash
systemctl --no-reload enable sshd.service
```

  - starship:

```bash
# If you have insufficient ressources, you may want to "emerge -1 dev-lang/rust-bin" beforehand.
echo "app-shells/starship ~amd64" >> /etc/portage/package.accept_keywords/main && \
emerge app-shells/starship && \
mkdir --mode=0700 /home/david/.config /root/.config && \
touch /home/david/.config/starship.toml && \
chown -R david:david /home/david/.config && \
cat <<'EOF' | tee /root/.config/starship.toml > /home/david/.config/starship.toml; echo $?
[hostname]
ssh_only = false
format =  "[$hostname](bold red) "

EOF
```

  - fish shell:

```bash
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
fi' >> /home/david/.bashrc; echo $?
```

`root` setup:

```bash
/bin/fish -c fish_update_completions
```

`non-root` setup:

```bash
su -l david -c "/bin/fish -c fish_update_completions"
```

Enable aliases and starship (copy&paste one after the other):

```
su -
exit
su - david
exit
sed -i 's/^end$/    source "$HOME\/.bash_aliases"\n    starship init fish | source\nend/' /root/.config/fish/config.fish
sed -i 's/^end$/    source "$HOME\/.bash_aliases"\n    starship init fish | source\nend/' /home/david/.config/fish/config.fish
```

  - nerd fonts:

```bash
emerge media-libs/fontconfig && \
su -l david -c "curl --proto '=https' --tlsv1.3 -fsSL -o /tmp/FiraCode.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/FiraCode.zip" && \
b2sum -c <<<"81f1dce1c7724a838fc5c61886902db576f3d1e8a18d4ba077772e045e3aea9a97e424b6fcd92a40a419f3ba160b3cad09609812c5496709f4b6a52c2b7269e6  /tmp/FiraCode.zip" && \
mkdir /tmp/FiraCode && \
unzip -d /tmp/FiraCode /tmp/FiraCode.zip && \
rm -f /tmp/FiraCode/*Windows* /tmp/FiraCode/Fura* && \
mkdir /usr/share/fonts/nerd-firacode && \
rsync -a --chown=0:0 --chmod=a=r /tmp/FiraCode/*.otf /usr/share/fonts/nerd-firacode/; echo $?
```

Download the [Nerd Font Symbols Preset](https://starship.rs/presets/nerd-font.html), verify the content and install.

  - If you have `sys-fs/mdadm` installed:

```bash
[[ -e /devSwapb ]] && \
rsync -a /etc/mdadm.conf /etc/._cfg0000_mdadm.conf && \
echo "" >> /etc/._cfg0000_mdadm.conf && \
mdadm --detail --scan >> /etc/._cfg0000_mdadm.conf; echo $?
```

  - ssh:

```bash
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
HostKeyAlgorithms ssh-ed25519
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

AllowUsers david" >> /etc/ssh/._cfg0000_sshd_config && \
ssh-keygen -A && \
sshd -t; echo $?
```

Write down fingerprints to double check upon initial SSH connection to the Gentoo Linux machine:

```bash
find /etc/ssh/ -type f -name "ssh_host*\.pub" -exec ssh-keygen -vlf {} \;
```

Setup client SSH config:

```bash
echo "AddKeysToAgent no
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
HostKeyAlgorithms ssh-ed25519
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
HashKnownHosts no
StrictHostKeyChecking ask
VisualHostKey yes" > /home/david/.ssh/config && \
chown david:david /home/david/.ssh/config; echo $?
```

  - Disable `sysrq` for [security sake](https://wiki.gentoo.org/wiki/Vlock#Disable_SysRq_key):

```bash
echo "kernel.sysrq = 0" > /etc/sysctl.d/99sysrq.conf
```

  - misc tools:

```bash
emerge -at app-misc/screen app-portage/gentoolkit
```
