## 8.1. Basic Configuration

Setup [/etc/fstab](https://wiki.gentoo.org/wiki//etc/fstab):

```shell
SWAP_UUID="$(blkid -s UUID -o value /mapperSwap)" && \
SYSTEM_UUID="$(blkid -s UUID -o value /mapperSystem)" && \
echo "" >> /etc/fstab && \
echo "
$(while read -r i; do
  echo "UUID=$(blkid -s UUID -o value "$i") ${i/devE/boot\/e} vfat noatime,dmask=0022,fmask=0133 0 0"
done < <(find /devEfi* -maxdepth 0))
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

Setup [/etc/hosts](https://wiki.gentoo.org/wiki/Handbook:AMD64/Installation/System#The_hosts_file) (copy&paste one after the other):

```shell hl_lines="4"
# Set the hostname of your choice
my_hostname="micro"

rsync -a /etc/hosts /etc/._cfg0000_hosts && \
sed -i "s/localhost$/localhost ${my_hostname}/" /etc/._cfg0000_hosts && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Disable "magic SysRq" for [security sake](https://wiki.gentoo.org/wiki/Vlock#Disable_SysRq_key):

```shell
echo "kernel.sysrq = 0" > /etc/sysctl.d/99sysrq.conf
```

Install miscellaneous tools:

```shell
emerge -at app-misc/screen app-portage/gentoolkit
```

## 8.2. systemd Preparation

Apply systemd useflags:

```shell
touch /etc/sysctl.conf && \

# add LUKS volume and systemd-boot support
echo "sys-apps/systemd cryptsetup gnuefi" >> /etc/portage/package.use/main && \

emerge -atuDN @world
```

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

## 8.3. Secure Boot

!!! danger "Warnings on OptionROM"

    While using sbctl, take warnings such as the following serious and make sure to understand the implications:

    > Could not find any TPM Eventlog in the system. This means we do not know if there is any OptionROM present on the system.

    > etc.

    > Please read the FAQ for more information: https://github.com/Foxboron/sbctl/wiki/FAQ#option-rom

In order to add your custom keys, "setup mode" must have been enabled in your "UEFI Firmware Settings" before booting into SystemRescueCD. But, you can [install secure boot files later on](/post-boot_configuration/#122-secure-boot-setup) if you missed enabling "setup mode". In the following, however, you have to generate secure boot files either way.

Install "app-crypt/sbctl":

```shell
emerge -at app-crypt/sbctl
```

Create and enroll secure boot files ([link](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#sbctl)):

```shell
❯ sbctl status
Installed:      ✗ sbctl is not installed
Setup Mode:     ✗ Enabled
Secure Boot:    ✗ Disabled

❯ sbctl create-keys
Created Owner UUID 4cdeb60c-d2ce-4ed9-af89-2b659c21f6e4
Creating secure boot keys...✓
Secure boot keys created!

❯ sbctl enroll-keys
Enrolling keys to EFI variables...✓
Enrolled keys to the EFI variables!

❯ sbctl status
Installed:      ✓ sbctl is installed
Owner GUID:     4cdeb60c-d2ce-4ed9-af89-2b659c21f6e4
Setup Mode:     ✓ Disabled
Secure Boot:    ✗ Disabled
```
