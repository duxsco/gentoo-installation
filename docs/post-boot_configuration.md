## 9.1. Systemd Configuration

Some configuration needs to be done after systemd has been started.

Do some [initial configuration](https://wiki.gentoo.org/wiki/Systemd#Configuration) (copy&paste one after the other):

```bash
systemd-firstboot --prompt --setup-machine-id
systemctl --preset-mode=enable-only preset-all
```

Setup [localisation](https://wiki.gentoo.org/wiki/Systemd#Locale):

```bash
bash -c '
localectl set-locale LANG="de_DE.UTF-8" LC_COLLATE="C.UTF-8" LC_MESSAGES="en_US.UTF-8" && \
localectl status && \
env-update && source /etc/profile; echo $?
'
```

Setup timedatectl:

```bash
bash -c '
timedatectl set-timezone Europe/Berlin && \
if ! grep -q -w "hypervisor" <(grep "^flags[[:space:]]*:[[:space:]]*" /proc/cpuinfo); then
    rsync -av /etc/systemd/timesyncd.conf /etc/systemd/._cfg0000_timesyncd.conf && \
    sed -i -e "s/#NTP=/NTP=0.de.pool.ntp.org 1.de.pool.ntp.org 2.de.pool.ntp.org 3.de.pool.ntp.org/" -e "s/#FallbackNTP=.*/FallbackNTP=0.europe.pool.ntp.org 1.europe.pool.ntp.org 2.europe.pool.ntp.org 3.europe.pool.ntp.org/" /etc/systemd/._cfg0000_timesyncd.conf && \
    timedatectl set-ntp true
    echo $?
fi && \
timedatectl; echo $?
'
```

Setup nftables:

```bash
bash -c '
emerge net-firewall/nftables && \
rsync -a /etc/conf.d/nftables /etc/conf.d/._cfg0000_nftables && \
sed -i "s/^SAVE_ON_STOP=\"yes\"$/SAVE_ON_STOP=\"no\"/" /etc/conf.d/._cfg0000_nftables && \
/usr/local/sbin/firewall.nft && \
nft list ruleset > /var/lib/nftables/rules-save && \
systemctl enable nftables-restore; echo $?
'
```

## 9.2. Measured Boot

You have two options for `Measured Boot`:

- `systemd-cryptenroll`: I prefer this on local systems where I have access to tty and can take care of (optional) pin prompts which are supported with systemd 251. With pins, you don't have the problem of your laptop, for example, getting stolen and auto-unlocking upon boot. Furthermore, I experienced faster boot with `systemd-cryptenroll` than with `clevis`, and you don't have to use the `app-crypt/clevis` package from (unofficial) [guru overlay](https://wiki.gentoo.org/wiki/Project:GURU).
- `clevis`: I prefer this on remote systems, e.g. a server in colocation, where I can take care of auto-unlock via TPM 2.0 and Tang pin.

Use either `systemd-cryptenroll` or `clevis` in the following.

### 9.2.1.a) systemd-cryptenroll

Install `app-crypt/tpm2-tools`:

```bash
echo "=app-crypt/tpm2-tools-5.2-r1 ~amd64" >> /etc/portage/package.accept_keywords/main && \
emerge -av tpm2-tools
```

Add support for TPM to dracut and systemd:

```bash
bash -c '
sed -i "s/\(sys-apps\/systemd cryptsetup\)/\1 tpm/" /etc/portage/package.use/main && \
echo \'add_dracutmodules+=" tpm2-tss "\' >> /etc/dracut.conf; echo $?
'
```

Enable newer version with required bug fixes and features:

```bash
echo "=sys-kernel/dracut-056-r1 ~amd64
=sys-apps/systemd-251.2 ~amd64" >> /etc/portage/package.accept_keywords/main
```

Update:

```bash
emerge -atuDN @world
```

Reboot your system!

Make sure that TPM 2.0 devices (should only be one) are recognised:

```bash
systemd-cryptenroll --tpm2-device=list
```

Make sure that the PCRs you are going to use have a valid hash and don't contain only zeroes:

```bash
tpm2_pcrread sha256
```

Create new LUKS keyslots on all swap and system partitions. You need to **boot with each EFI binary (one ESP for each disk) and repeat keyslot creation** for each one, because different PCR5 values are created depending on the EFI binary you booted with.

```bash
# Adjust PCR IDs, e.g.: --tpm2-pcrs=1+7
# Further info can be found at:
# https://www.freedesktop.org/software/systemd/man/systemd-cryptenroll.html#id-1.7.3.10.2.2
#
# "--tpm2-with-pin=yes" is optional.
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+1+2+3+4+5+6+7 --tpm2-with-pin=yes /dev/sda4
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+1+2+3+4+5+6+7 --tpm2-with-pin=yes /dev/sda5
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+1+2+3+4+5+6+7 --tpm2-with-pin=yes /dev/sdb4
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+1+2+3+4+5+6+7 --tpm2-with-pin=yes /dev/sdb5
# etc.
```

Remove overlay directory containing `app-crypt/clevis`:

```bash
rm -rf /root/localrepo
```

### 9.2.1.b) clevis

Install `dev-vcs/git`:

```bash
emerge -at dev-vcs/git
```

Install `app-crypt/clevis`:

```bash
emerge -1 app-eselect/eselect-repository && \
eselect repository create localrepo && \
sed -i '/^location[[:space:]]*=[[:space:]]*\/var\/db\/repos\/localrepo$/a auto-sync = false' /etc/portage/repos.conf/eselect-repo.conf && \
rsync -a /root/localrepo /var/db/repos/ && \
rm -rf /root/localrepo && \
echo "app-crypt/clevis ~amd64
dev-libs/jose ~amd64
dev-libs/luksmeta ~amd64
app-crypt/tpm2-tools ~amd64" >> /etc/portage/package.accept_keywords/main && \
emerge -at app-crypt/clevis
```

Make sure that the PCRs you are going to use have a valid hash and don't contain only zeroes:

```bash
tpm2_pcrread sha256
```

Bind all swap and system LUKS volumes. You need to **boot with each EFI binary (one ESP for each disk) and repeat keyslot creation** for each one, because different PCR5 values are created depending on the EFI binary you booted with.

```bash
# Adjust PCR IDs, e.g.: "pcr_ids":"1,7"
# Further info can be found at:
# https://www.freedesktop.org/software/systemd/man/systemd-cryptenroll.html#id-1.7.3.10.2.2
clevis luks bind -d /dev/sda4 tpm2 '{"pcr_bank":"sha256","pcr_ids":"0,1,2,3,4,5,6,7"}'
clevis luks bind -d /dev/sda5 tpm2 '{"pcr_bank":"sha256","pcr_ids":"0,1,2,3,4,5,6,7"}'
clevis luks bind -d /dev/sdb4 tpm2 '{"pcr_bank":"sha256","pcr_ids":"0,1,2,3,4,5,6,7"}'
clevis luks bind -d /dev/sdb5 tpm2 '{"pcr_bank":"sha256","pcr_ids":"0,1,2,3,4,5,6,7"}'
# etc.
```

Show results:

```bash
clevis luks list -d /dev/sda4
clevis luks list -d /dev/sda5
clevis luks list -d /dev/sdb4
clevis luks list -d /dev/sdb5
# etc.
# Sample output:
# 1: tpm2 '{"hash":"sha256","key":"ecc","pcr_bank":"sha256","pcr_ids":"1,2,3,4,5,6,7"}'
```

### 9.2.2. Initramfs Rebuild

Enable [portage hook](https://wiki.gentoo.org/wiki//etc/portage/bashrc) and reinstall `sys-kernel/gentoo-kernel-bin` to integrate clevis OR systemd's TPM support in initramfs and GnuPG auto-sign `/boot` files:

```bash
mv /root/bashrc /etc/portage/ && \
chmod u=rw,og=r /etc/portage/bashrc && \
emerge sys-kernel/gentoo-kernel-bin
```

Make sure you have:

```bash
❯ ls -la /boot/
total 125628
drwx------ 1 root root      424 14. Jun 23:39 ./
drwxr-xr-x 1 root root      140 14. Jun 23:13 ../
-rw-r--r-- 1 root root  5822827 14. Jun 23:39 System.map
-rw-r--r-- 1 root root  5822827 14. Jun 22:35 System.map.old
-rw-r--r-- 1 root root      438 14. Jun 23:12 System.map.old.sig
-rw-r--r-- 1 root root      438 14. Jun 23:39 System.map.sig
-rw-r--r-- 1 root root   235283 14. Jun 23:39 config
-rw-r--r-- 1 root root   235283 14. Jun 22:35 config.old
-rw-r--r-- 1 root root      438 14. Jun 23:12 config.old.sig
-rw-r--r-- 1 root root      438 14. Jun 23:39 config.sig
-rw-r--r-- 1 root root     1390 14. Jun 23:11 grub.cfg
-rw-r--r-- 1 root root      438 14. Jun 23:12 grub.cfg.sig
-rw-r--r-- 1 root root 58616905 14. Jun 23:39 initramfs
-rw-r--r-- 1 root root 36435427 14. Jun 22:35 initramfs.old
-rw-r--r-- 1 root root      438 14. Jun 23:12 initramfs.old.sig
-rw-r--r-- 1 root root      438 14. Jun 23:39 initramfs.sig
-rw-r--r-- 1 root root 10698848 14. Jun 23:39 vmlinuz
-rw-r--r-- 1 root root 10698848 14. Jun 22:35 vmlinuz.old
-rw-r--r-- 1 root root      438 14. Jun 23:12 vmlinuz.old.sig
-rw-r--r-- 1 root root      438 14. Jun 23:39 vmlinuz.sig
```

`.old` and `.old.sig` files are those of the initial package installation within chroot. `initramfs.old` doesn't have clevis and systemd's TPM support integrated.

## 9.4. Package Cleanup

Remove extraneous packages (should be only `app-editors/nano`, `app-eselect/eselect-repository`, `app-misc/yq` and `app-portage/cpuid2cpuflags`):

```bash
emerge --depclean -a
```
