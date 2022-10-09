!!! warning "Disclaimer"
    This installation guide, **called "guide" in the following**, builds upon [the official Gentoo Linux installation handbook](https://wiki.gentoo.org/wiki/Handbook:AMD64/Full/Installation). It's written with great care. Nevertheless, you are expected not to blindly copy&paste commands! Please, **understand** what you are going to do **and adjust commands if required**!

## 1.1. System Requirements

Beside [official hardware requirements](https://wiki.gentoo.org/wiki/Handbook:AMD64/Full/Installation#Hardware_requirements), the guide has additional ones:

- **Secure Boot and TPM 2.0:** It builds heavily on "secure boot" and requires "TPM 2.0" not only for "secure boot" but also for "measured boot" to function. Make sure that the system is in "setup mode" in order to be able to add your custom "secure boot" keys. You can, however, boot without "setup mode" and import them later on depending on the hardware in use. For this, you can follow the instructions in section [8.2. Secure Boot Setup](/post-boot_configuration/#82-secure-boot-setup) at that point in time.

- **systemd and Measured Boot:** The guide requires the use of systemd for "measured boot" to work without restrictions. [Clevis](https://wiki.gentoo.org/wiki/Trusted_Platform_Module) may be an option if you want to stay with OpenRC. But, I haven't tested this. Alternatively, you can take a look at my [older documentation](https://github.com/duxsco/gentoo-installation/tree/v2.1.1) which, however, doesn't support "measured boot" and isn't maintained by me anymore.
- **x86_64 Architecture:** To keep things simple, the guide presumes that you intend to install on a x86_64 system. This is the only architecture that has been tested by me! And, it's the only architecture still [actively supported by SystemRescueCD](https://www.system-rescue.org/Download/).

## 1.2. Technologies

The guide results in a system that is/uses:

- [x] **Secure Boot**: All EFI binaries and unified kernel images are signed.
- [x] **Measured Boot**: [systemd-cryptenroll](https://wiki.archlinux.org/title/Trusted_Platform_Module#systemd-cryptenroll) or [clevis](https://github.com/latchset/clevis) is used to check the system for manipulations via TPM 2.0 PCRs.
- [x] **Fully encrypted**: Except for ESP(s), all partitions are LUKS encrypted.
- [x] **RAID**: Except for ESP(s), btrfs and mdadm based RAID are used for all partitions if the number of disks is ≥2.
- [x] **Rescue system**: A customised SystemRescueCD supports SSH logins and provides a convenient [chroot.sh](https://github.com/duxsco/gentoo-installation/blob/main/bin/disk.sh#L202-L281) script.
- [x] **Hardened Gentoo Linux (optional)** for a highly secure, high stability production environment ([link](https://wiki.gentoo.org/wiki/Project:Hardened)).
- [x] **SELinux (optional)** provides Mandatory Access Control using type enforcement and role-based access control ([link](https://wiki.gentoo.org/wiki/Project:SELinux)).

## 1.3. SSH Connectivity

After completion of this guide, optional SSH connections will be possible to the following systems using SSH public key authentication:

=== "Gentoo Linux installation"

    ```shell
    ssh -p 50022 david@<IP address>
    ```

=== "SystemRescueCD installation"

    ```shell
    ssh -p 50023 root@<IP address>
    ```

## 1.4. Disk Layout

ESPs are created one for each disk. Except for them, [btrfs](https://btrfs.readthedocs.io/en/latest/mkfs.btrfs.html#profiles) or [mdadm](https://raid.wiki.kernel.org/index.php/Introduction#The_RAID_levels) based RAID 1 is used for all other partitions on a dual- or multi-disk setup with RAID 5, RAID 6 and RAID 10 being further options for the swap device. The 2nd partition doesn't make use of btrfs RAID due to [limitations of SystemRescueCD](https://gitlab.com/systemrescue/systemrescue-sources/-/issues/292#note_1036225171).

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
