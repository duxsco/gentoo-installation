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

## 1.3. SSH Connectivity

After completion of this installation guide, SSH connections will be (optionally) possible via SSH public key authentication to the:

- Gentoo Linux system: `ssh -p 50022 david@<IP address>`
- Rescue system: `ssh -p 50023 root@<IP address>`

Both boot options are available in the boot menu.

## 1.4. Disk Layout

ESPs each with their own EFI entry are created one for each disk. Except for ESP, Btrfs/mdadm RAID 1 is used for all other partitions with RAID 5, RAID 6 and RAID 10 being further options for `swap`.

- Single disk:

```
PC∕Laptop
└── ∕dev∕sda
    ├── 1. EFI System Partition
    ├── 2. LUKS
    │   └── Btrfs (single)
    │       └── rescue
    ├── 3. LUKS
    │   └── SWAP
    └── 4. LUKS ("system" partition)
        └── Btrfs (single)
            └── subvolumes
                ├── @binpkgs
                ├── @distfiles
                ├── @home
                ├── @ebuilds
                ├── @root
                └── @var_tmp
```

- Two disks:

```
PC∕Laptop──────────────────────────┐
└── ∕dev∕sda                       └── ∕dev∕sdb
    ├── 1. EFI System Partition        ├── 1. EFI System Partition
    ├── 2. MDADM RAID 1                ├── 2. MDADM RAID 1
    │   └── LUKS                       │   └── LUKS
    │       └── Btrfs                  │       └── Btrfs
    │           └── rescue             │           └── rescue
    ├── 3. LUKS                        ├── 3. LUKS
    │   └── MDADM RAID 1               │   └── MDADM RAID 1
    │       └── SWAP                   │       └── SWAP
    └── 4. LUKS ("system" partition)   └── 4. LUKS ("system" partition)
        └── Btrfs raid1                    └── Btrfs raid1
            └── subvolume                      └── subvolume
                ├── @binpkgs                       ├── @binpkgs
                ├── @distfiles                     ├── @distfiles
                ├── @home                          ├── @home
                ├── @ebuilds                       ├── @ebuilds
                ├── @root                          ├── @root
                └── @var_tmp                       └── @var_tmp
```

- Three disks:

```
PC∕Laptop──────────────────────────┬──────────────────────────────────┐
└── ∕dev∕sda                       └── ∕dev∕sdb                       └── ∕dev∕sdc
    ├── 1. EFI System Partition        ├── 1. EFI System Partition        ├── 1. EFI System Partition
    ├── 2. MDADM RAID 1                ├── 2. MDADM RAID 1                ├── 2. MDADM RAID 1
    │   └── LUKS                       │   └── LUKS                       │   └── LUKS
    │       └── Btrfs                  │       └── Btrfs                  │       └── Btrfs
    │           └── rescue             │           └── rescue             │           └── rescue
    ├── 3. LUKS                        ├── 3. LUKS                        ├── 3. LUKS
    │   └── MDADM RAID 1|5             │   └── MDADM RAID 1|5             │   └── MDADM RAID 1|5
    │       └── SWAP                   │       └── SWAP                   │       └── SWAP
    └── 4. LUKS ("system" partition)   └── 4. LUKS ("system" partition)   └── 4. LUKS ("system" partition)
        └── Btrfs raid1c3                  └── Btrfs raid1c3                  └── Btrfs raid1c3
            └── subvolume                      └── subvolume                      └── subvolume
                ├── @binpkgs                       ├── @binpkgs                       ├── @binpkgs
                ├── @distfiles                     ├── @distfiles                     ├── @distfiles
                ├── @home                          ├── @home                          ├── @home
                ├── @ebuilds                       ├── @ebuilds                       ├── @ebuilds
                ├── @root                          ├── @root                          ├── @root
                └── @var_tmp                       └── @var_tmp                       └── @var_tmp
```

- Four disks:

```
PC∕Laptop──────────────────────────┬──────────────────────────────────┬──────────────────────────────────┐
└── ∕dev∕sda                       └── ∕dev∕sdb                       └── ∕dev∕sdc                       └── ∕dev∕sdd
    ├── 1. EFI System Partition        ├── 1. EFI System Partition        ├── 1. EFI System Partition        ├── 1. EFI System Partition
    ├── 2. MDADM RAID 1                ├── 2. MDADM RAID 1                ├── 2. MDADM RAID 1                ├── 2. MDADM RAID 1
    │   └── LUKS                       │   └── LUKS                       │   └── LUKS                       │   └── LUKS
    │       └── Btrfs                  │       └── Btrfs                  │       └── Btrfs                  │       └── Btrfs
    │           └── rescue             │           └── rescue             │           └── rescue             │           └── rescue
    ├── 3. LUKS                        ├── 3. LUKS                        ├── 3. LUKS                        ├── 3. LUKS
    │   └── MDADM RAID 1|5|6|10        │   └── MDADM RAID 1|5|6|10        │   └── MDADM RAID 1|5|6|10        │   └── MDADM RAID 1|5|6|10
    │       └── SWAP                   │       └── SWAP                   │       └── SWAP                   │       └── SWAP
    └── 4. LUKS ("system" partition)   └── 4. LUKS ("system" partition)   └── 4. LUKS ("system" partition)   └── 4. LUKS ("system" partition)
        └── Btrfs raid1c4                  └── Btrfs raid1c4                  └── Btrfs raid1c4                  └── Btrfs raid1c4
            └── subvolume                      └── subvolume                      └── subvolume                      └── subvolume
                ├── @binpkgs                       ├── @binpkgs                       ├── @binpkgs                       ├── @binpkgs
                ├── @distfiles                     ├── @distfiles                     ├── @distfiles                     ├── @distfiles
                ├── @home                          ├── @home                          ├── @home                          ├── @home
                ├── @ebuilds                       ├── @ebuilds                       ├── @ebuilds                       ├── @ebuilds
                ├── @root                          ├── @root                          ├── @root                          ├── @root
                └── @var_tmp                       └── @var_tmp                       └── @var_tmp                       └── @var_tmp
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

