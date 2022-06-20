## 10.1. Secure Boot Setup

If `efi-updatevar` failed in one of the previous sections, you can import Secure Boot files the following way.

First, boot into the Gentoo Linux and save necessary files in `DER` form:

```bash
bash -c '
(
! mountpoint --quiet /efia && \\
mount /efia || true
) && \\
openssl x509 -outform der -in /etc/gentoo-installation/secureboot/db.crt -out /efia/db.der && \\
openssl x509 -outform der -in /etc/gentoo-installation/secureboot/KEK.crt -out /efia/KEK.der && \\
openssl x509 -outform der -in /etc/gentoo-installation/secureboot/PK.crt -out /efia/PK.der; echo $?
'
```

Reboot into `UEFI Firmware Settings` and import `db.der`, `KEK.der` and `PK.der`. Thereafter, enable Secure Boot. Upon successful boot with Secure Boot enabled, you can delete `db.der`, `KEK.der` and `PK.der` in `/efia`.

To check whether Secure Boot is enabled execute:

```bash
mokutil --sb-state
```

## 10.2. Enable SELinux

This is optional! Steps are documented in the [gentoo-selinux](https://github.com/duxsco/gentoo-selinux) repo.
