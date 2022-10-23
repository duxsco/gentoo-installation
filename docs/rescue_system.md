!!! info
    A [feature request](https://gitlab.com/systemrescue/systemrescue-sources/-/issues/292) has been opened to have SystemRescue support "measured boot".

While we are still on SystemRescue and not within chroot, download the SystemRescue .iso file and create a customised one out of it.

## 4.1. Downloads And Verification

Prepare the working directory:

```shell
mkdir -p /mnt/gentoo/etc/gentoo-installation/systemrescuecd && \
chown meh:meh /mnt/gentoo/etc/gentoo-installation/systemrescuecd && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Import the GnuPG public key used to sign the SystemRescue .iso:

```shell
su -l meh -c "
mkdir --mode=0700 /tmp/gpgHomeDir && \
curl -fsSL --proto '=https' --tlsv1.3 https://www.system-rescue.org/security/signing-keys/gnupg-pubkey-fdupoux-20210704-v001.pem | gpg --homedir /tmp/gpgHomeDir --import && \
gpg --homedir /tmp/gpgHomeDir --import-ownertrust <<<'62989046EB5C7E985ECDF5DD3B0FEA9BE13CA3C9:6:' && \
gpgconf --homedir /tmp/gpgHomeDir --kill all && \
echo -e '\e[1;32mSUCCESS\e[0m'
"
```

Download the .iso and .asc files:

```shell
rescue_system_version="$(su -l meh -c "curl -fsS --proto '=https' --tlsv1.3 https://gitlab.com/systemrescue/systemrescue-sources/-/raw/main/VERSION")" && \
su -l meh -c "
curl --continue-at - -L --proto '=https' --tlsv1.2 --ciphers 'ECDHE+AESGCM+AES256:ECDHE+CHACHA20:ECDHE+AESGCM+AES128' --output /mnt/gentoo/etc/gentoo-installation/systemrescuecd/systemrescue.iso \"https://sourceforge.net/projects/systemrescuecd/files/sysresccd-x86/${rescue_system_version}/systemrescue-${rescue_system_version}-amd64.iso/download?use_mirror=netcologne\" && \
curl -fsSL --proto '=https' --tlsv1.3 --output /mnt/gentoo/etc/gentoo-installation/systemrescuecd/systemrescue.iso.asc \"https://www.system-rescue.org/releases/${rescue_system_version}/systemrescue-${rescue_system_version}-amd64.iso.asc\" && \
echo -e '\e[1;32mSUCCESS\e[0m'
"
```

Verify the .iso file with GnuPG:

```shell
su -l meh -c "
gpg --homedir /tmp/gpgHomeDir --verify /mnt/gentoo/etc/gentoo-installation/systemrescuecd/systemrescue.iso.asc /mnt/gentoo/etc/gentoo-installation/systemrescuecd/systemrescue.iso && \
gpgconf --homedir /tmp/gpgHomeDir --kill all
" && \
chown -R 0:0 /mnt/gentoo/etc/gentoo-installation/systemrescuecd && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

## 4.2. Configuration

Create the folder structure which will contain SystemRescue customisations:

```shell
mkdir -p /mnt/gentoo/etc/gentoo-installation/systemrescuecd/{recipe/{iso_delete,iso_add/{autorun,sysresccd,sysrescue.d},iso_patch_and_script,build_into_srm/{etc/{ssh,sysctl.d},usr/local/sbin}},work} && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Disable "magic SysRq" for [security sake](https://wiki.gentoo.org/wiki/Vlock#Disable_SysRq_key):

```shell
echo "kernel.sysrq = 0" > /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/etc/sysctl.d/99sysrq.conf && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Copy [chroot.sh created by disk.sh](https://github.com/duxsco/gentoo-installation/blob/main/bin/disk.sh#L202-L281):

```shell
rsync -av --numeric-ids --chown=0:0 --chmod=u=rwx,go=r /tmp/chroot.sh /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/usr/local/sbin/ && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Copy the [firewall script](https://github.com/duxsco/gentoo-installation/blob/main/bin/firewall.sh):

```shell
# set firewall rules upon bootup.
rsync -av --numeric-ids --chown=0:0 --chmod=u=rw,go=r /tmp/firewall.sh /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/iso_add/autorun/autorun && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Create the settings YAML (copy&paste one after the other):

```shell
# disable bash history
set +o history

# replace "MyPassWord123" with the password you want to use to login via TTY on the rescue system
crypt_pass="$(python3 -c 'import crypt; print(crypt.crypt("MyPassWord123", crypt.mksalt(crypt.METHOD_SHA512)))')"

# enable bash history
set -o history

# set default settings
echo "\
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
    rootcryptpass: '${crypt_pass}'

autorun:
    ar_disable: false
    ar_nowait: true
    ar_nodel: false
    ar_ignorefail: false\
" > /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/iso_add/sysrescue.d/500-settings.yaml

# unset the password variable
unset crypt_pass
```

Integrate additional packages required for [chroot.sh](https://github.com/duxsco/gentoo-installation/blob/main/bin/disk.sh#L202-L281) to work:

```shell
pacman -Sy clevis libpwquality luksmeta sbctl sbsigntools tpm2-tools && \
cowpacman2srm /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/iso_add/sysresccd/zz_additional_packages.srm && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

## 4.3 (Optional) SSH Server

!!! info

    This section is only required if you want to access the rescue system over SSH.

Take care of [public key authentication](https://wiki.gentoo.org/wiki/SSH#Passwordless_authentication) (copy&paste one after the other):

```shell
mkdir -p /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/root/.ssh

# add your ssh public keys to
# /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/root/.ssh/authorized_keys

# set correct modes
chmod u=rwx,g=rx,o= /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/root
chmod -R u=rwX,go= /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/root/.ssh
```

Configure the SSH server:

```shell
rsync -a /etc/ssh/sshd_config /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/etc/ssh/sshd_config && \

# do some ssh server hardening
sed -i \
-e 's/^#Port 22$/Port 50023/' \
-e 's/^#PasswordAuthentication yes/PasswordAuthentication no/' \
-e 's/^#X11Forwarding no$/X11Forwarding no/' /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/etc/ssh/sshd_config && \

grep -q "^KbdInteractiveAuthentication no$" /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/etc/ssh/sshd_config  && \
echo "
AuthenticationMethods publickey

KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com" >> /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/etc/ssh/sshd_config && \

# create ssh_host_* files in build_into_srm/etc/ssh/
ssh-keygen -A -f /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm && \

{ diff /etc/ssh/sshd_config /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/etc/ssh/sshd_config || true; } && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Open the SSH port:

```shell
echo "
iptables  -A INPUT -p tcp --dport 50023 -j ACCEPT
ip6tables -A INPUT -p tcp --dport 50023 -j ACCEPT" >> /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/iso_add/autorun/autorun
```

Write down fingerprints to double check upon initial SSH connection to the rescue system:

```shell
find /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/etc/ssh/ -type f -name "ssh_host*\.pub" -exec ssh-keygen -vlf {} \; && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

## 4.4. Folder Structure

After running through above installation steps, you should have the following file/folder structure:

=== "SSH setup"

    ```shell
    ❯ tree -a /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe
    /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe
    ├── build_into_srm
    │   ├── etc
    │   │   ├── ssh
    │   │   │   ├── sshd_config
    │   │   │   ├── ssh_host_ecdsa_key
    │   │   │   ├── ssh_host_ecdsa_key.pub
    │   │   │   ├── ssh_host_ed25519_key
    │   │   │   ├── ssh_host_ed25519_key.pub
    │   │   │   ├── ssh_host_rsa_key
    │   │   │   └── ssh_host_rsa_key.pub
    │   │   └── sysctl.d
    │   │       └── 99sysrq.conf
    │   ├── root
    │   │   └── .ssh
    │   │       └── authorized_keys
    │   └── usr
    │       └── local
    │           └── sbin
    │               └── chroot.sh
    ├── iso_add
    │   ├── autorun
    │   │   └── autorun
    │   ├── sysresccd
    │   │   └── zz_additional_packages.srm
    │   └── sysrescue.d
    │       └── 500-settings.yaml
    ├── iso_delete
    └── iso_patch_and_script
    
    15 directories, 13 files
    ```

=== "non-SSH setup"

    ```shell
    ❯ tree -a /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe
    /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe
    ├── build_into_srm
    │   ├── etc
    │   │   └── sysctl.d
    │   │       └── 99sysrq.conf
    │   └── usr
    │       └── local
    │           └── sbin
    │               └── chroot.sh
    ├── iso_add
    │   ├── autorun
    │   │   └── autorun
    │   ├── sysresccd
    │   │   └── zz_additional_packages.srm
    │   └── sysrescue.d
    │       └── 500-settings.yaml
    ├── iso_delete
    └── iso_patch_and_script
    
    12 directories, 5 files
    ```

## 4.5. ISO And Rescue Partition

[Create an installation medium](https://www.system-rescue.org/scripts/sysrescue-customize/) with above changes:

```shell
sysrescue-customize \
    --auto --overwrite \
    -s /mnt/gentoo/etc/gentoo-installation/systemrescuecd/systemrescue.iso \
    -d /mnt/gentoo/etc/gentoo-installation/systemrescuecd/systemrescue_custom.iso \
    -r /mnt/gentoo/etc/gentoo-installation/systemrescuecd/recipe \
    -w /mnt/gentoo/etc/gentoo-installation/systemrescuecd/work && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Copy the content of the custom installation medium to the "rescue" partition:

```shell
mkdir /mnt/iso /mnt/gentoo/mnt/rescue && \
mount -o loop,ro /mnt/gentoo/etc/gentoo-installation/systemrescuecd/systemrescue_custom.iso /mnt/iso && \
mount -o noatime /mnt/gentoo/mapperRescue /mnt/gentoo/mnt/rescue && \
rsync -HAXSacv --delete /mnt/iso/{autorun,sysresccd,sysrescue.d} /mnt/gentoo/mnt/rescue/ && \
umount /mnt/iso && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

## 4.6. Kernel Installation

Create the [unified kernel image](https://wiki.archlinux.org/title/Unified_kernel_image#Manually) which will be used to boot the rescue system:

```shell
echo "cryptdevice=UUID=$(blkid -s UUID -o value /mnt/gentoo/devRescue):root root=/dev/mapper/root archisobasedir=sysresccd archisolabel=rescue31415fs noautologin loadsrm=y" > /tmp/my_cmdline && \
objcopy \
  --add-section .osrel="/usr/lib/os-release" --change-section-vma .osrel=0x20000 \
  --add-section .cmdline="/tmp/my_cmdline" --change-section-vma .cmdline=0x30000 \
  --add-section .linux="/mnt/gentoo/mnt/rescue/sysresccd/boot/x86_64/vmlinuz" --change-section-vma .linux=0x2000000 \
  --add-section .initrd="/mnt/gentoo/mnt/rescue/sysresccd/boot/x86_64/sysresccd.img" --change-section-vma .initrd=0x3000000 \
  "/usr/lib/systemd/boot/efi/linuxx64.efi.stub" "/tmp/systemrescuecd.efi" && \
while read -r my_esp; do
  mkdir "${my_esp/devE/boot\/e}" && \
  mount -o noatime,dmask=0022,fmask=0133 "${my_esp}" "${my_esp/devE/boot\/e}" && \
  rsync -av "/tmp/systemrescuecd.efi" "${my_esp/devE/boot\/e}/" && \
  echo -e "\e[1;32mSUCCESS\e[0m"
done < <(find /mnt/gentoo/devEfi* -maxdepth 0)
```
