!!! warning "Disclaimer"
    This installation guide is based on [the official Gentoo Linux installation handbook](https://wiki.gentoo.org/wiki/Handbook:AMD64/Full/Installation). It is written with great care. Nevertheless, you are expected not to blindly copy&paste commands! Please, **understand** what you are going to do **and adjust commands if required**!

## 1.1. System Requirements

- **Secure Boot and TPM 2.0:** The installation guide builds heavily on "secure boot" and requires "TPM 2.0" for "measured boot". Make sure that the system is in "setup mode" in order to be able to add your custom "secure boot" keys. You can, however, boot without "setup mode" and import the "secure boot" keys later on depending on the hardware in use. For this, you can follow the instructions in section [8.2. Secure Boot Setup](/post-boot_configuration/#82-secure-boot-setup).

- **systemd and Measured Boot:** The installation guide requires the use of systemd for "measured boot" to work. If you want to stay with OpenRC you can take a look at my [older documentation](https://github.com/duxsco/gentoo-installation/tree/v2.1.1). That, however, doesn't support "measured boot" and isn't maintained by me anymore.

## 1.2. Technologies

The installation guide results in a system that is/uses:

- [x] **Secure Boot**: Any EFI binary and unified kernel image is signed.
- [x] **Measured Boot**: [systemd-cryptenroll](https://wiki.archlinux.org/title/Trusted_Platform_Module#systemd-cryptenroll) or [clevis](https://github.com/latchset/clevis) is used to check the system for manipulations via TPM 2.0 PCRs.
- [x] **Fully encrypted**: Except for ESP(s), all partitions are LUKS encrypted.
- [x] **RAID**: Except for ESP(s), btrfs and mdadm based RAID are used for all partitions if the number of disks is ≥2.
- [x] **Rescue system**: A customised SystemRescueCD supports SSH logins and provides a convenient [chroot.sh](https://github.com/duxsco/gentoo-installation/blob/01dad0465eb76d04bd4107a5ec16d02f5b2de30e/bin/disk.sh#L202-L281) script.
- [x] **Hardened Gentoo Linux (optional)** for a highly secure, high stability production environment ([link](https://wiki.gentoo.org/wiki/Project:Hardened)).
- [x] **SELinux (optional)** provides Mandatory Access Control using type enforcement and role-based access control ([link](https://wiki.gentoo.org/wiki/Project:SELinux)).

## 1.3. SSH Connectivity

After completion of this installation guide, optional SSH connections will be possible to the following systems using SSH public key authentication:

- Gentoo Linux installation: `ssh -p 50022 david@<IP address>`
- Rescue system: `ssh -p 50023 root@<IP address>`

## 1.4. Disk Layout

ESPs are created one for each disk. Except for them, [btrfs](https://btrfs.readthedocs.io/en/latest/mkfs.btrfs.html#profiles) or [mdadm](https://raid.wiki.kernel.org/index.php/Introduction#The_RAID_levels) based RAID 1 is used for all other partitions on a dual- or multi-disk setup with RAID 5, RAID 6 and RAID 10 being further options for the swap device.

=== "four disks"

    ![four disks](/images/four_disks.png)

=== "three disks"

    ![three disks](/images/three_disks.png)

=== "two disks"

    ![two disks](/images/two_disks.png)

=== "single disk"

    ![single disk](/images/single_disk.png)

## 1.5. LUKS Key Slots

On the "rescue" partition, LUKS key slots are set as follows:

  - 0: Rescue password

On all other LUKS volumes, LUKS key slots are set as follows:

  - 0: Fallback password for emergency
  - 1: Measured Boot
    - Option A: TPM 2.0 with optional pin to unlock with [systemd-cryptenroll](https://wiki.archlinux.org/title/Trusted_Platform_Module#systemd-cryptenroll)
    - Option B: [Shamir Secret Sharing](https://github.com/latchset/clevis#pin-shamir-secret-sharing) combining [TPM 2.0](https://github.com/latchset/clevis#pin-tpm2) and [Tang](https://github.com/latchset/clevis#pin-tang) pin ([Tang project](https://github.com/latchset/tang)) to automatically unlock with Clevis
