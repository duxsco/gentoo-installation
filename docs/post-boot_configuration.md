## 8.1. Systemd Configuration

Some configuration needs to be done after systemd has been started.

Do some [initial configuration](https://wiki.gentoo.org/wiki/Systemd#Configuration) (copy&paste one after the other):

```bash
systemd-firstboot --prompt --setup-machine-id
systemctl preset-all
```

Re-enable services you need if they have been disabled by above second command.

Setup [localisation](https://wiki.gentoo.org/wiki/Systemd#Locale):

```bash
/bin/bash -c '
localectl set-locale LANG="de_DE.UTF-8" LC_COLLATE="C.UTF-8" LC_MESSAGES="en_US.UTF-8" && \
localectl status && \
env-update && source /etc/profile; echo $?
'
```

Setup timedatectl:

```bash
/bin/bash -c '
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
/bin/bash -c '
emerge net-firewall/nftables && \
rsync -a /etc/conf.d/nftables /etc/conf.d/._cfg0000_nftables && \
sed -i "s/^SAVE_ON_STOP=\"yes\"$/SAVE_ON_STOP=\"no\"/" /etc/conf.d/._cfg0000_nftables && \
/usr/local/sbin/firewall.nft && \
nft list ruleset > /var/lib/nftables/rules-save && \
systemctl enable nftables-restore; echo $?
'
```

## 8.2. Secure Boot Setup

If `efi-updatevar` failed in [one of the previous sections](/system_setup/#64-secure-boot), you can import Secure Boot files the following way.

First, boot into the Gentoo Linux and save necessary files in `DER` form:

```bash
/bin/bash -c '
(
! mountpoint --quiet /boot/efia && \
mount /boot/efia || true
) && \
openssl x509 -outform der -in /etc/gentoo-installation/secureboot/db.crt -out /boot/efia/db.der && \
openssl x509 -outform der -in /etc/gentoo-installation/secureboot/KEK.crt -out /boot/efia/KEK.der && \
openssl x509 -outform der -in /etc/gentoo-installation/secureboot/PK.crt -out /boot/efia/PK.der; echo $?
'
```

Reboot into `UEFI Firmware Settings` and import `db.der`, `KEK.der` and `PK.der`. Thereafter, enable Secure Boot. Upon successful boot with Secure Boot enabled, you can delete `db.der`, `KEK.der` and `PK.der` in `/boot/efia`.

To check whether Secure Boot is enabled execute:

```bash
mokutil --sb-state
```

To list the installed Secure Boot keys/certs:

```bash
efi-readvar
```

## 8.3. Measured Boot

You have two options for `Measured Boot`:

- `systemd-cryptenroll`: I prefer this on local systems where I have access to tty and can take care of (optional) pin prompts which are supported with systemd >=251. With pins, you don't have the problem of your laptop, for example, getting stolen and auto-unlocking upon boot. Furthermore, I experienced faster boot with `systemd-cryptenroll` than with `clevis` due to the use of PBKDF2 (with secure keys), and you don't have to use the `app-crypt/clevis` package from (unofficial) [guru overlay](https://wiki.gentoo.org/wiki/Project:GURU).
- `clevis`: I prefer this on remote systems, e.g. a server in colocation, where I can take care of auto-unlock via TPM 2.0 and Tang pin.

Use either `systemd-cryptenroll` or `clevis` in the following.

### 8.3.1.a) systemd-cryptenroll

Install `app-crypt/tpm2-tools`:

```bash
echo "=app-crypt/tpm2-tools-5.2-r1 ~amd64" >> /etc/portage/package.accept_keywords/main && \
emerge -av tpm2-tools
```

Add support for TPM to dracut and systemd:

```bash
/bin/bash -c '
sed -i "s/\(sys-apps\/systemd \)/\1 tpm /" /etc/portage/package.use/main && \
echo \'add_dracutmodules+=" tpm2-tss "\' >> /etc/dracut.conf; echo $?
'
```

Enable newer version with required bug fixes and features:

```bash
echo "=sys-apps/systemd-251.2 ~amd64" >> /etc/portage/package.accept_keywords/main
```

Update and make sure `sys-apps/systemd` got updated:

```bash
emerge -atuDN @world
```

Make sure that TPM 2.0 devices (should only be one) are recognised:

```bash
systemd-cryptenroll --tpm2-device=list
```

Make sure that the PCRs you are going to use have a valid hash and don't contain only zeroes:

```bash
tpm2_pcrread sha256
```

Create new LUKS keyslots on all swap and system partitions.

```bash
# I only use PCR7 as recommended in the first sentence after following table:
# https://www.freedesktop.org/software/systemd/man/systemd-cryptenroll.html#id-1.7.3.10.2.2
#
# "--tpm2-with-pin=yes" is optional:
# https://www.freedesktop.org/software/systemd/man/systemd-cryptenroll.html#--tpm2-with-pin=BOOL
#
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes /dev/sda3
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes /dev/sda4
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes /dev/sdb3
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes /dev/sdb4
# etc.
```

Remove overlay directory containing `app-crypt/clevis`:

```bash
rm -rf /root/localrepo
```

Reboot your system!

### 8.3.1.b) clevis

If you don't have a DHCP server available to the new system, add [the following network settings](https://www.systutorials.com/docs/linux/man/7-dracut.cmdline/#lbAN) to the `CMDLINE` array variable in `/etc/dracut.conf`:

```
ip=192.168.10.2::192.168.10.1:255.255.255.0:micro:enp1s0:off
```

Install `dev-vcs/git`:

```bash
echo 'dev-vcs/git -webdav' >> /etc/portage/package.use/main && \
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

Bind all swap and system LUKS volumes.

```bash
# I only use PCR7 as recommended in the first sentence after following table:
# https://www.freedesktop.org/software/systemd/man/systemd-cryptenroll.html#id-1.7.3.10.2.2
#
clevis luks bind -d /dev/sda3 sss '{"t": 2, "pins": {"tpm2": {"pcr_bank":"sha256","pcr_ids":"7"}, "tang": {"url": "http://tang.local"}}}'
clevis luks bind -d /dev/sda4 sss '{"t": 2, "pins": {"tpm2": {"pcr_bank":"sha256","pcr_ids":"7"}, "tang": {"url": "http://tang.local"}}}'
clevis luks bind -d /dev/sdb3 sss '{"t": 2, "pins": {"tpm2": {"pcr_bank":"sha256","pcr_ids":"7"}, "tang": {"url": "http://tang.local"}}}'
clevis luks bind -d /dev/sdb4 sss '{"t": 2, "pins": {"tpm2": {"pcr_bank":"sha256","pcr_ids":"7"}, "tang": {"url": "http://tang.local"}}}'
# etc.
```

Show results:

```bash
clevis luks list -d /dev/sda3
clevis luks list -d /dev/sda4
clevis luks list -d /dev/sdb3
clevis luks list -d /dev/sdb4
# etc.
```

### 8.3.2. Rebuild Unified Kernel Image

Rebuild the unified kernel image:

```bash
emerge -at sys-kernel/gentoo-kernel-bin
```

## 8.4. Package Cleanup

Remove extraneous packages (should be only `app-editors/nano`, `app-eselect/eselect-repository`, `app-misc/yq` and `app-portage/cpuid2cpuflags`):

```bash
emerge --depclean -a
```
