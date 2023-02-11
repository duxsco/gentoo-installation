## 9.1. non-Gentoo Images

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
  echo -e "timeout 5\neditor no" > "/boot/${my_esp}/loader/loader.conf" && \

  # move the precreated EFI binary of the rescue system into ESP
  mv "/boot/${my_esp}/systemrescuecd.efi" "/boot/${my_esp}/EFI/Linux/" && \

  # secure boot sign EFI binaries
  sbctl sign "/boot/${my_esp}/EFI/systemd/systemd-bootx64.efi" && \
  sbctl sign "/boot/${my_esp}/EFI/BOOT/BOOTX64.EFI" && \
  sbctl sign "/boot/${my_esp}/EFI/Linux/systemrescuecd.efi" && \

  echo -e "\e[1;32mSUCCESS\e[0m"
done < <(grep -Po "^UUID=[0-9A-F]{4}-[0-9A-F]{4}[[:space:]]+/boot/\Kefi[a-z](?=[[:space:]]+vfat[[:space:]]+)" /etc/fstab)
```

## 9.2. CPU Microcode

Microcode updates are [not necessary for virtual machines](https://unix.stackexchange.com/a/572757). On bare-metal, however, install "sys-firmware/intel-microcode" for Intel CPUs or follow the [Gentoo wiki instruction](https://wiki.gentoo.org/wiki/AMD_microcode) to update the microcode on AMD systems.

```shell
! grep -q -w "hypervisor" <(grep "^flags[[:space:]]*:[[:space:]]*" /proc/cpuinfo) && \
grep -q "^vendor_id[[:space:]]*:[[:space:]]*GenuineIntel$" /proc/cpuinfo && \
echo "sys-firmware/intel-microcode intel-ucode" >> /etc/portage/package.license && \
echo "sys-firmware/intel-microcode hostonly" >> /etc/portage/package.use/main && \
emerge -at sys-firmware/intel-microcode && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

## 9.3. Portage Hooks

Setup [portage hooks](https://github.com/duxsco/gentoo-installation/blob/main/bin/portage_hook_kernel) ([wiki entry](https://wiki.gentoo.org/wiki//etc/portage/bashrc)) that take care of [unified kernel image](https://wiki.archlinux.org/title/Unified_kernel_image) creation and [secure boot signing](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#sbctl):

```shell
mkdir -p /etc/portage/env/sys-apps /etc/portage/env/sys-kernel && \
rsync -a --numeric-ids --chown=0:0 --chmod=u=rw,go=r /root/portage_hook_kernel /etc/portage/env/sys-kernel/gentoo-kernel && \
rsync -a --numeric-ids --chown=0:0 --chmod=u=rw,go=r /root/portage_hook_kernel /etc/portage/env/sys-kernel/gentoo-kernel-bin && \
rm -f /root/portage_hook_kernel && \
echo 'if [[ ${EBUILD_PHASE} == postinst ]]; then
    while read -r my_esp; do
        bootctl --esp-path="/boot/${my_esp}" --no-variables --graceful update && \
        sbctl sign "/boot/${my_esp}/EFI/systemd/systemd-bootx64.efi" && \
        sbctl sign "/boot/${my_esp}/EFI/BOOT/BOOTX64.EFI"

        if [[ $? -ne 0 ]]; then
cat <<'\''EOF'\'' >&2

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

## 9.4. Dracut

Setup [sys-kernel/dracut](https://wiki.gentoo.org/wiki/Dracut). If you don't wear tin foil hats :wink:, you may want to change the [line "mitigations=auto,nosmt"](https://www.kernel.org/doc/html/latest/admin-guide/kernel-parameters.html) below (copy&paste one after the other):

``` { .shell .no-copy }
emerge -at app-crypt/sbsigntools sys-kernel/dracut

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
uefi_secureboot_cert=/usr/share/secureboot/keys/db/db.pem
uefi_secureboot_key=/usr/share/secureboot/keys/db/db.key

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
kernel_cmdline=\"\${CMDLINE[*]}\"
unset CMDLINE" >> /etc/dracut.conf
```

## 9.5. Packages

(Optional) Use [LTS (longterm) kernels](https://kernel.org/category/releases.html):

```shell
echo "\
>=sys-fs/btrfs-progs-6.2
>=sys-kernel/gentoo-kernel-6.2
>=sys-kernel/gentoo-kernel-bin-6.2
>=sys-kernel/linux-headers-6.2
>=virtual/dist-kernel-6.2" >> /etc/portage/package.mask/main
```

Configure packages required for booting:

```shell
echo "sys-fs/btrfs-progs ~amd64
sys-kernel/gentoo-kernel ~amd64
sys-kernel/gentoo-kernel-bin ~amd64
sys-kernel/linux-headers ~amd64
virtual/dist-kernel ~amd64" >> /etc/portage/package.accept_keywords/main && \

# I prefer to create a "fresh" btrfs FS instead of converting
# reiserfs and ext2/3/4 to btrfs.
echo "sys-fs/btrfs-progs -convert" >> /etc/portage/package.use/main && \

# Dracut will take care of initramfs creation.
echo "sys-kernel/gentoo-kernel -initramfs" >> /etc/portage/package.use/main && \
echo "sys-kernel/gentoo-kernel-bin -initramfs" >> /etc/portage/package.use/main && \

# Accept required licenses.
echo "sys-kernel/linux-firmware linux-fw-redistributable no-source-code" >> /etc/portage/package.license
```

## 9.6. Kernel Installation

??? note "Kernel Upgrade And Old Kernel Cleanup"
    After a kernel upgrade and system reboot, an `emerge --depclean` will leave certain files and folders on the system which you cannot delete with [eclean-kernel](https://wiki.gentoo.org/wiki/Kernel/Removal):

    ``` { .shell .no-copy }
    ❯ sudo -i eclean-kernel -n 1
    eclean-kernel has met the following issue:

      SystemError('No vmlinuz found. This seems ridiculous, aborting.')

    If you believe that the mentioned issue is a bug, please report it
    to https://github.com/mgorny/eclean-kernel/issues. If possible,
    please attach the output of 'eclean-kernel --list-kernels' and your
    regular eclean-kernel call with additional '--debug' argument.
    ```

    In following example, you have to delete the 5.15.87 kernel files and folders manually:

    ``` { .shell .no-copy }
    ❯ ls -1 /boot/efi*/EFI/Linux/ /usr/src/ /lib/modules/
    /boot/efia/EFI/Linux/:
    gentoo-5.15.87-gentoo-dist-hardened.efi
    gentoo-5.15.88-gentoo-dist-hardened.efi
    systemrescuecd.efi

    /boot/efib/EFI/Linux/:
    gentoo-5.15.87-gentoo-dist-hardened.efi
    gentoo-5.15.88-gentoo-dist-hardened.efi
    systemrescuecd.efi

    /lib/modules/:
    5.15.87-gentoo-dist-hardened/
    5.15.88-gentoo-dist-hardened/

    /usr/src/:
    linux@
    linux-5.15.88-gentoo-dist-hardened/
    ```

Install required packages:

```shell hl_lines="3"
if [[ -e /devSwapb ]]; then
  emerge -at sys-fs/btrfs-progs sys-fs/mdadm sys-kernel/linux-firmware && \
  rsync -a /etc/mdadm.conf /etc/._cfg0000_mdadm.conf && \
  echo "" >> /etc/._cfg0000_mdadm.conf && \
  mdadm --detail --scan >> /etc/._cfg0000_mdadm.conf && \
  echo -e "\e[1;32mSUCCESS\e[0m"
else
  emerge -at sys-fs/btrfs-progs sys-kernel/linux-firmware && \
  echo -e "\e[1;32mSUCCESS\e[0m"
fi
```

For [kernel](https://wiki.gentoo.org/wiki/Kernel) installation, you have two reasonable choices depending on whether you use a [hardened profile or not](/portage_setup/#64-optional-hardened-profiles):

=== "hardened profile"
    ```shell
    # This package makes use of "hardened" useflag.
    emerge -at sys-kernel/gentoo-kernel
    ```

=== "non-hardened profile"
    ```shell
    emerge -at sys-kernel/gentoo-kernel-bin
    ```
