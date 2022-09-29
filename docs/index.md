## 1.1. Disclaimer

!!! warning
    Don't blindly copy&paste the commands! Understand what you are going to do and adjust commands if required! I point this out, even though it should go without saying...

!!! info "System Requirements"
    The installation guide builds heavily on `Secure Boot` and requires `TPM 2.0` for `Measured Boot`. Make sure that the system is in `Setup Mode` in order to be able to add your custom `Secure Boot` keys. You can, however, boot without `Setup Mode` and import the `Secure Boot` keys later on depending on the hardware in use. For this, you can follow the instructions in section [8.2. Secure Boot Setup](/post-boot_configuration/#82-secure-boot-setup).

## 1.2. Technologies

The following installation guide results in a system that is/uses:

- [x] **Secure Boot**: EFI binary/binaries in ESP(s) are Secure Boot signed.
- [x] **Measured Boot**: [systemd-cryptenroll](https://wiki.archlinux.org/title/Trusted_Platform_Module#systemd-cryptenroll) or [clevis](https://github.com/latchset/clevis) is used to check the system for manipulations via TPM2 PCRs (Platform Configuration Registers).
- [x] **Fully encrypted**: Except ESP(s), all partitions are LUKS encrypted.
- [x] **RAID**: If the number of disks is >=2, mdadm and Btrfs based RAID are used for all partitions other than ESP(s).
- [x] **Rescue system** based on a **customised SystemRescueCD** that provides the [chroot.sh](https://github.com/duxsco/gentoo-installation/blob/01dad0465eb76d04bd4107a5ec16d02f5b2de30e/bin/disk.sh#L202-L281) script to conveniently chroot into your Gentoo installation.
- [x] **Hardened Gentoo Linux (optional)** ([link](https://wiki.gentoo.org/wiki/Project:Hardened))
- [x] **SELinux (optional)** ([link](https://wiki.gentoo.org/wiki/Project:SELinux))

!!! important
    This guide requires the use of systemd for measured boot to work. If you don't want to switch over from OpenRC you can take a look at my [older documentation](https://github.com/duxsco/gentoo-installation/tree/v2.1.1). That isn't maintained anymore though.

## 1.3. SSH Connectivity

After completion of this installation guide, SSH connections will be (optionally) possible via SSH public key authentication to the:

- Gentoo Linux system: `ssh -p 50022 david@<IP address>`
- Rescue system: `ssh -p 50023 root@<IP address>`

Both boot options are available in the boot menu.

## 1.4. Disk Layout

ESPs each with their own EFI entry are created one for each disk. Except for ESP, Btrfs/mdadm RAID 1 is used for all other partitions with RAID 5, RAID 6 and RAID 10 being further options for `swap`.

=== "four disks"

    ![four disks](/images/four_disks.png)

=== "three disks"

    ![three disks](/images/three_disks.png)

=== "two disks"

    ![two disks](/images/two_disks.png)

=== "single disk"

    ![single disk](/images/single_disk.png)

More disks can be used (see: `man mkfs.btrfs | sed -n '/^PROFILES$/,/^[[:space:]]*└/p'`). RAID 10 is only available to setups with an even number of disks.

## 1.5. LUKS Key Slots

On the `rescue` partition, LUKS key slots are set as follows:

  - 0: Rescue password

On all other LUKS volumes, LUKS key slots are set as follows:

  - 0: Fallback password for emergency
  - 1: Measured Boot
    - Option A: TPM 2.0 with optional pin to unlock with [systemd-cryptenroll](https://wiki.archlinux.org/title/Trusted_Platform_Module#systemd-cryptenroll)
    - Option B: [Shamir Secret Sharing](https://github.com/latchset/clevis#pin-shamir-secret-sharing) combining [TPM2](https://github.com/latchset/clevis#pin-tpm2) and [Tang](https://github.com/latchset/clevis#pin-tang) pin ([Tang project](https://github.com/latchset/tang)) to automatically unlock with Clevis

The following steps are basically those in [the official Gentoo Linux installation handbook](https://wiki.gentoo.org/wiki/Handbook:AMD64/Full/Installation) with some customisations added.

