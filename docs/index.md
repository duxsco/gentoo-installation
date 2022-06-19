## 1.1. Disclaimer

⚠ This installation guide was primarily written for my personal use to avoid reinventing the wheel over and over. **Thus, don't blindly copy&paste the commands! Understand what you are going to do and adjust commands if required!** I point this out, even though it should go without saying... ⚠

⚠ The installation guide builds heavily on `Secure Boot` and requires TPM 2.0 for `Measured Boot`. Make sure that the system is in `Setup Mode` in order to be able to add your custom `Secure Boot` keys. You can, however, boot without `Setup Mode` and import the `Secure Boot` keys later on depending on the hardware in use ([link](#installation-of-secure-boot-files-via-uefi-firmware-settings)). ⚠

## 1.2. Technologies

The following installation guide results in a system that is/uses:

- **Secure Boot**: EFI binary/binaries in ESP(s) are Secure Boot signed.
- **Measured Boot**: All files in `/boot`, e.g. grub.cfg, initramfs, kernel, are GnuPG signed. Furthermore, [systemd-cryptenroll](https://wiki.archlinux.org/title/Trusted_Platform_Module#systemd-cryptenroll) or [clevis](https://github.com/latchset/clevis) is used to automatically decrypt LUKS volumes. You can secure the use of `systemd-cryptenroll` with a pin, though.
- **Fully encrypted**: Except ESP(s) and `/boot`, all partitions are LUKS encrypted.
- **RAID**: mdadm and BTRFS based RAID are used wherever it makes sense if the number of disks is >= 2.
- **Rescue system** based on a **customised SystemRescueCD** that provides the `chroot.sh` script to conveniently chroot into your Gentoo installation.

## 1.3. SSH Connectivity

After completion of this installation guide, SSH connections will be possible via SSH public key authentication to the:

- Gentoo Linux system: `ssh -p 50022 david@<IP address>`
- Rescue system: `ssh -p 50023 root@<IP address>`

Both boot options are available in GRUB's boot menu.

## 1.4. Disk Layout

ESPs each with their own EFI entry are created one for each disk. Alternatively, you can store the ESP on multiple removable drives. This scenario won't be outlined in the following codeblocks. You just need to think of `1. EFI System Partition` missing in below scenarios.

Except for ESP, BTRFS/MDADM RAID 1 is used for all other partitions with RAID 5, RAID 6 and RAID 10 being further options for `swap`.

- Single disk:

```
PC∕Laptop
└── ∕dev∕sda
    ├── 1. EFI System Partition
    ├── 2. Btrfs (single)
    │   └── /boot
    ├── 3. LUKS
    │   └── Btrfs (single)
    │       └── rescue
    ├── 4. LUKS
    │   └── SWAP
    └── 5. LUKS ("system" partition)
        └── Btrfs (single)
            └── subvolumes
                ├── @binpkgs
                ├── @distfiles
                ├── @home
                ├── @ebuilds
                └── @root
```

- Two disks:

```
PC∕Laptop──────────────────────────┐
└── ∕dev∕sda                       └── ∕dev∕sdb
    ├── 1. EFI System Partition        ├── 1. EFI System Partition
    ├── 2. Btrfs raid1                 ├── 2. Btrfs raid1
    │   └── /boot                      │   └── /boot
    ├── 3. MDADM RAID 1                ├── 3. MDADM RAID 1
    │   └── LUKS                       │   └── LUKS
    │       └── Btrfs                  │       └── Btrfs
    │           └── rescue             │           └── rescue
    ├── 4. LUKS                        ├── 4. LUKS
    │   └── MDADM RAID 1               │   └── MDADM RAID 1
    │       └── SWAP                   │       └── SWAP
    └── 5. LUKS ("system" partition)   └── 5. LUKS ("system" partition)
        └── BTRFS raid1                    └── BTRFS raid1
            └── subvolume                      └── subvolume
                ├── @binpkgs                       ├── @binpkgs
                ├── @distfiles                     ├── @distfiles
                ├── @home                          ├── @home
                ├── @ebuilds                       ├── @ebuilds
                └── @root                          └── @root
```

- Three disks:

```
PC∕Laptop──────────────────────────┬──────────────────────────────────┐
└── ∕dev∕sda                       └── ∕dev∕sdb                       └── ∕dev∕sdc
    ├── 1. EFI System Partition        ├── 1. EFI System Partition        ├── 1. EFI System Partition
    ├── 2. Btrfs raid1c3               ├── 2. Btrfs raid1c3               ├── 2. Btrfs raid1c3
    │   └── /boot                      │   └── /boot                      │   └── /boot
    ├── 3. MDADM RAID 1                ├── 3. MDADM RAID 1                ├── 3. MDADM RAID 1
    │   └── LUKS                       │   └── LUKS                       │   └── LUKS
    │       └── Btrfs                  │       └── Btrfs                  │       └── Btrfs
    │           └── rescue             │           └── rescue             │           └── rescue
    ├── 4. LUKS                        ├── 4. LUKS                        ├── 4. LUKS
    │   └── MDADM RAID 1|5             │   └── MDADM RAID 1|5             │   └── MDADM RAID 1|5
    │       └── SWAP                   │       └── SWAP                   │       └── SWAP
    └── 5. LUKS ("system" partition)   └── 5. LUKS ("system" partition)   └── 5. LUKS ("system" partition)
        └── BTRFS raid1c3                  └── BTRFS raid1c3                  └── BTRFS raid1c3
            └── subvolume                      └── subvolume                      └── subvolume
                ├── @binpkgs                       ├── @binpkgs                       ├── @binpkgs
                ├── @distfiles                     ├── @distfiles                     ├── @distfiles
                ├── @home                          ├── @home                          ├── @home
                ├── @ebuilds                       ├── @ebuilds                       ├── @ebuilds
                └── @root                          └── @root                          └── @root
```

- Four disks:

```
PC∕Laptop──────────────────────────┬──────────────────────────────────┬──────────────────────────────────┐
└── ∕dev∕sda                       └── ∕dev∕sdb                       └── ∕dev∕sdc                       └── ∕dev∕sdd
    ├── 1. EFI System Partition        ├── 1. EFI System Partition        ├── 1. EFI System Partition        ├── 1. EFI System Partition
    ├── 2. Btrfs raid1c4               ├── 2. Btrfs raid1c4               ├── 2. Btrfs raid1c4               ├── 2. Btrfs raid1c4
    │   └── /boot                      │   └── /boot                      │   └── /boot                      │   └── /boot
    ├── 3. MDADM RAID 1                ├── 3. MDADM RAID 1                ├── 3. MDADM RAID 1                ├── 3. MDADM RAID 1
    │   └── LUKS                       │   └── LUKS                       │   └── LUKS                       │   └── LUKS
    │       └── Btrfs                  │       └── Btrfs                  │       └── Btrfs                  │       └── Btrfs
    │           └── rescue             │           └── rescue             │           └── rescue             │           └── rescue
    ├── 4. LUKS                        ├── 4. LUKS                        ├── 4. LUKS                        ├── 4. LUKS
    │   └── MDADM RAID 1|5|6|10        │   └── MDADM RAID 1|5|6|10        │   └── MDADM RAID 1|5|6|10        │   └── MDADM RAID 1|5|6|10
    │       └── SWAP                   │       └── SWAP                   │       └── SWAP                   │       └── SWAP
    └── 5. LUKS ("system" partition)   └── 5. LUKS ("system" partition)   └── 5. LUKS ("system" partition)   └── 5. LUKS ("system" partition)
        └── BTRFS raid1c4                  └── BTRFS raid1c4                  └── BTRFS raid1c4                  └── BTRFS raid1c4
            └── subvolume                      └── subvolume                      └── subvolume                      └── subvolume
                ├── @binpkgs                       ├── @binpkgs                       ├── @binpkgs                       ├── @binpkgs
                ├── @distfiles                     ├── @distfiles                     ├── @distfiles                     ├── @distfiles
                ├── @home                          ├── @home                          ├── @home                          ├── @home
                ├── @ebuilds                       ├── @ebuilds                       ├── @ebuilds                       ├── @ebuilds
                └── @root                          └── @root                          └── @root                          └── @root
```

- More disks can be used (see: `man mkfs.btrfs | sed -n '/^PROFILES$/,/^[[:space:]]*└/p'`). RAID 10 is only available to setups with an even number of disks.

## 1.5. LUKS Key Slots

On the `rescue` partition, LUKS key slots are set as follows:

  - 0: Rescue password

On all other LUKS volumes, LUKS key slots are set as follows:

  - 0: Fallback password for emergency
  - 1: Measured Boot
    - Option A: TPM 2.0 with optional pin to unlock with [systemd-cryptenroll](https://wiki.archlinux.org/title/Trusted_Platform_Module#systemd-cryptenroll)
    - Option B: [Shamir Secret Sharing](https://github.com/latchset/clevis#pin-shamir-secret-sharing) combining [TPM2](https://github.com/latchset/clevis#pin-tpm2) and [Tang](https://github.com/latchset/clevis#pin-tang) pin ([Tang project](https://github.com/latchset/tang)) to automatically unlock with Clevis

The following steps are basically those in [the official Gentoo Linux installation handbook](https://wiki.gentoo.org/wiki/Handbook:AMD64/Full/Installation) with some customisations added.

