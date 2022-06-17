## GnuPG Homedir Creation

The whole boot process must be GnuPG signed. You can use either RSA or some NIST-P based ECC. Unfortunately, `ed25519/cv25519` as well as `ed448/cv448` are not supported. It seems Grub builds upon [libgcrypt 1.5.3](https://git.savannah.gnu.org/cgit/grub.git/commit/grub-core?id=d1307d873a1c18a1e4344b71c027c072311a3c14), but support for `ed25519/cv25519` has been added upstream later on in [version 1.6.0](https://git.gnupg.org/cgi-bin/gitweb.cgi?p=libgcrypt.git;a=blob;f=NEWS;h=bc70483f4376297a11ed44b40d5b8a71a478d321;hb=HEAD#l709), while [version 1.9.0](https://git.gnupg.org/cgi-bin/gitweb.cgi?p=libgcrypt.git;a=blob;f=NEWS;h=bc70483f4376297a11ed44b40d5b8a71a478d321;hb=HEAD#l139) comes with `ed448/cv448` support.

Create GnuPG homedir:

```bash
mkdir --mode=0700 /etc/gentoo-installation/gnupg
```

Create a GnuPG keypair with `gpg --full-gen-key`. I personally don't set a passphrase for the keypair to allow for `sys-kernel/gentoo-kernel-bin` installation without getting prompted for the passphrase.

```bash
➤ gpg --homedir /etc/gentoo-installation/gnupg --full-gen-key
gpg (GnuPG) 2.2.32; Copyright (C) 2021 Free Software Foundation, Inc.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.

gpg: directory '/root/.gnupg' created
gpg: keybox '/root/.gnupg/pubring.kbx' created
Please select what kind of key you want:
   (1) RSA and RSA (default)
   (2) DSA and Elgamal
   (3) DSA (sign only)
   (4) RSA (sign only)
  (14) Existing key from card
Your selection? 4
RSA keys may be between 1024 and 4096 bits long.
What keysize do you want? (3072)
Requested keysize is 3072 bits
Please specify how long the key should be valid.
         0 = key does not expire
      <n>  = key expires in n days
      <n>w = key expires in n weeks
      <n>m = key expires in n months
      <n>y = key expires in n years
Key is valid for? (0)
Key does not expire at all
Is this correct? (y/N) y

GnuPG needs to construct a user ID to identify your key.

Real name: grubEfi
Email address:
Comment:
You selected this USER-ID:
    "grubEfi"

Change (N)ame, (C)omment, (E)mail or (O)kay/(Q)uit? o
```

Result:

```bash
➤ gpg --homedir /etc/gentoo-installation/gnupg --list-keys
gpg: checking the trustdb
gpg: marginals needed: 3  completes needed: 1  trust model: pgp
gpg: depth: 0  valid:   1  signed:   0  trust: 0-, 0q, 0n, 0m, 0f, 1u
/root/.gnupg/pubring.kbx
------------------------
pub   rsa3072 2022-02-15 [SC]
      714F5DD28AC1A31E04BCB850B158334ADAF5E3C0
uid           [ultimate] grubEfi
```

Export your GnuPG public key and sign `grub-initial_efi*.cfg` (copy&paste one after the other):

```bash
mkdir --mode=0700 /etc/gentoo-installation/boot

# Export public key
gpg --homedir /etc/gentoo-installation/gnupg --export-options export-minimal --export > /etc/gentoo-installation/boot/gpg.pub

# If signature creation fails...
GPG_TTY="$(tty)"
export GPG_TTY

# Sign microcode if existent
if [[ -f /boot/intel-uc.img ]]; then
  gpg --homedir /etc/gentoo-installation/gnupg --detach-sign /boot/intel-uc.img
  echo $?
fi

# Stop the gpg-agent
gpgconf --homedir /etc/gentoo-installation/gnupg --kill all
```

Sign your custom SystemRescueCD files with GnuPG:

```bash
find /mnt/rescue -type f -exec gpg --homedir /etc/gentoo-installation/gnupg --detach-sign {} \; && \
gpgconf --homedir /etc/gentoo-installation/gnupg --kill all; echo $?
```

## Secure Boot

Credits:

- [https://ruderich.org/simon/notes/secure-boot-with-grub-and-signed-linux-and-initrd](https://ruderich.org/simon/notes/secure-boot-with-grub-and-signed-linux-and-initrd)
- [https://www.funtoo.org/Secure_Boot](https://www.funtoo.org/Secure_Boot)
- [https://www.rodsbooks.com/efi-bootloaders/secureboot.html](https://www.rodsbooks.com/efi-bootloaders/secureboot.html)
- [https://fit-pc.com/wiki/index.php?title=Linux:_Secure_Boot](https://fit-pc.com/wiki/index.php?title=Linux:_Secure_Boot)
- [https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot)

In order to add your custom keys `Setup Mode` must have been enabled in your `UEFI Firmware Settings` before booting into SystemRescueCD. But, you can install Secure Boot files later on if you missed enabling `Setup Mode`. In the following, however, you have to generate Secure Boot files either way.

Install required tools on your system:

```bash
echo "sys-boot/mokutil ~amd64" >> /etc/portage/package.accept_keywords/main && \
emerge -at app-crypt/efitools app-crypt/sbsigntools sys-boot/mokutil
```

Create Secure Boot keys and certificates:

```bash
mkdir --mode=0700 /etc/gentoo-installation/secureboot && \
pushd /etc/gentoo-installation/secureboot && \

# Create the keys
openssl req -new -x509 -newkey rsa:2048 -subj "/CN=PK/"  -keyout PK.key  -out PK.crt  -days 7300 -nodes -sha256 && \
openssl req -new -x509 -newkey rsa:2048 -subj "/CN=KEK/" -keyout KEK.key -out KEK.crt -days 7300 -nodes -sha256 && \
openssl req -new -x509 -newkey rsa:2048 -subj "/CN=db/"  -keyout db.key  -out db.crt  -days 7300 -nodes -sha256 && \

# Prepare installation in EFI
uuid="$(uuidgen --random)" && \
cert-to-efi-sig-list -g "${uuid}" PK.crt PK.esl && \
cert-to-efi-sig-list -g "${uuid}" KEK.crt KEK.esl && \
cert-to-efi-sig-list -g "${uuid}" db.crt db.esl && \
sign-efi-sig-list -k PK.key  -c PK.crt  PK  PK.esl  PK.auth && \
sign-efi-sig-list -k PK.key  -c PK.crt  KEK KEK.esl KEK.auth && \
sign-efi-sig-list -k KEK.key -c KEK.crt db  db.esl  db.auth && \
popd; echo $?
```

If the following commands don't work you have to install `db.auth`, `KEK.auth` and `PK.auth` over the `UEFI Firmware Settings` upon reboot after the completion of this installation guide. Further information can be found at the end of this installation guide. Beware that the following commands delete all existing keys.

```bash
pushd /etc/gentoo-installation/secureboot && \

# Make them mutable
chattr -i /sys/firmware/efi/efivars/{PK,KEK,db,dbx}* && \

# Install keys into EFI (PK last as it will enable Custom Mode locking out further unsigned changes)
efi-updatevar -f db.auth db && \
efi-updatevar -f KEK.auth KEK && \
efi-updatevar -f PK.auth PK && \

# Make them immutable
chattr +i /sys/firmware/efi/efivars/{PK,KEK,db,dbx}* && \
popd; echo $?
```

## GRUB

Install `sys-boot/grub`:

```bash
echo "sys-boot/grub -* device-mapper grub_platforms_efi-64" >> /etc/portage/package.use/main && \
emerge -at sys-boot/grub; echo $?
```

### ESP(s)

In the following, a minimal Grub config for each ESP is created. Take care of the line marked with `TODO`.

```bash
cat <<EOF > /etc/gentoo-installation/boot/efi.cfg
# Enforce that all loaded files must have a valid signature.
set check_signatures=enforce
export check_signatures

set superusers="root"
export superusers
# Replace the first TODO with the result of grub-mkpasswd-pbkdf2 with your custom passphrase.
password_pbkdf2 root grub.pbkdf2.sha512.10000.TODO

# NOTE: We export check_signatures/superusers so they are available in all
# further contexts to ensure the password check is always enforced.

search --no-floppy --fs-uuid --set=root $(blkid -s UUID -o value /mapperBoot)

configfile /grub.cfg

# Without this we provide the attacker with a rescue shell if he just presses
# <return> twice.
echo /EFI/grub/grub.cfg did not boot the system but returned to initial.cfg.
echo Rebooting the system in 10 seconds.
sleep 10
reboot
EOF
```

Sign `efi.cfg`:

```bash
gpg --homedir /etc/gentoo-installation/gnupg --detach-sign /etc/gentoo-installation/boot/efi.cfg
```

Create the EFI binary/ies and Secure Boot sign them:

```bash
# GRUB doesn't allow loading new modules from disk when secure boot is in
# effect, therefore pre-load the required modules.
modules=
modules="${modules} part_gpt fat ext2"             # partition and file systems for EFI
modules="${modules} configfile"                    # source command
modules="${modules} verify gcry_sha512 gcry_rsa"   # signature verification
modules="${modules} password_pbkdf2"               # hashed password
modules="${modules} echo normal linux linuxefi"    # boot linux
modules="${modules} all_video"                     # video output
modules="${modules} search search_fs_uuid"         # search --fs-uuid
modules="${modules} reboot sleep"                  # sleep, reboot
modules="${modules} gzio part_gpt part_msdos ext2" # SystemRescueCD modules
modules="${modules} luks2 btrfs part_gpt cryptodisk gcry_rijndael pbkdf2 gcry_sha512 mdraid1x" # LUKS2 modules
modules="${modules} $(grub-mkconfig | grep insmod | awk '{print $NF}' | sort -u | paste -d ' ' -s -)"

ls -1d /efi* | while read -r i; do
    mkdir -p "${i}/EFI/boot" && \
    grub-mkstandalone \
        --directory /usr/lib/grub/x86_64-efi \
        --disable-shim-lock \
        --format x86_64-efi \
        --modules "$(ls -1 /usr/lib/grub/x86_64-efi/ | grep -w $(tr ' ' '\n' <<<"${modules}" | sort -u | grep -v "^$" | sed -e 's/^/-e /' -e 's/$/.mod/' | paste -d ' ' -s -) | paste -d ' ' -s -)" \
        --pubkey /etc/gentoo-installation/boot/gpg.pub \
        --output "${i}/EFI/boot/bootx64.efi" \
        boot/grub/grub.cfg=/etc/gentoo-installation/boot/efi.cfg \
        boot/grub/grub.cfg.sig=/etc/gentoo-installation/boot/efi.cfg.sig && \
    sbsign --key /etc/gentoo-installation/secureboot/db.key --cert /etc/gentoo-installation/secureboot/db.crt --output "${i}/EFI/boot/bootx64.efi" "${i}/EFI/boot/bootx64.efi" && \
    efibootmgr --create --disk "/dev/$(lsblk -ndo pkname "$(readlink -f "${i/efi/devEfi}")")" --part 1 --label "gentoo31415efi ${i#/}" --loader '\EFI\boot\bootx64.efi'
    echo $?
done
```

### /boot

```bash
rescue_uuid="$(blkid -s UUID -o value /devRescue | tr -d '-')"
system_uuid="$(blkid -s UUID -o value /mapperSystem)"
my_crypt_root="$(blkid -s UUID -o value /devSystem* | sed 's/^/rd.luks.uuid=/' | paste -d " " -s -)"
my_crypt_swap="$(blkid -s UUID -o value /devSwap* | sed 's/^/rd.luks.uuid=/' | paste -d " " -s -)"
if [[ -f /boot/intel-uc.img ]]; then
    my_microcode="/intel-uc.img "
else
    my_microcode=""
fi

cat <<EOF > /etc/gentoo-installation/boot/grub.cfg
set default=0
set timeout=5

menuentry 'Gentoo GNU/Linux' --unrestricted {
    echo 'Loading Linux ...'
    linux /vmlinuz ro root=UUID=${system_uuid} ${my_crypt_root} ${my_crypt_swap} rd.luks.options=tpm2-device=auto rootfstype=btrfs rootflags=subvol=@root mitigations=auto,nosmt
    echo 'Loading initial ramdisk ...'
    initrd ${my_microcode}/initramfs
}

menuentry 'Gentoo GNU/Linux (old)' --unrestricted {
    echo 'Loading Linux (old) ...'
    linux /vmlinuz.old ro root=UUID=${system_uuid} ${my_crypt_root} ${my_crypt_swap} rd.luks.options=tpm2-device=auto rootfstype=btrfs rootflags=subvol=@root mitigations=auto,nosmt
    echo 'Loading initial ramdisk ...'
    initrd ${my_microcode}/initramfs.old
}

menuentry 'SystemRescueCD' {
    cryptomount -u ${rescue_uuid}
    set root='cryptouuid/${rescue_uuid}'
    search --no-floppy --fs-uuid --set=root --hint='cryptouuid/${rescue_uuid}' $(blkid -s UUID -o value /mapperRescue)
    echo   'Loading Linux kernel ...'
    linux  /sysresccd/boot/x86_64/vmlinuz cryptdevice=UUID=$(blkid -s UUID -o value /devRescue):root root=/dev/mapper/root archisobasedir=sysresccd archisolabel=rescue31415fs noautologin loadsrm=y
    echo   'Loading initramfs ...'
    initrd /sysresccd/boot/x86_64/sysresccd.img
}
EOF
```

Copy `grub.cfg` and GnuPG sign files in `/boot`:

```bash
rsync -av /etc/gentoo-installation/boot/grub.cfg /boot/ && \
while read -r file; do mv "${file}" "$(cut -d "-" -f1 <<<"${file}")"; done < <(find /boot -type f -name "*dist*") && \
find /boot -type f -exec gpg --homedir /etc/gentoo-installation/gnupg --detach-sign {} \;
```

## ESP(s) And /boot Layout

Result on a single disk system:

```bash
➤ tree -a /boot /efia*
/boot
├── config
├── config.sig
├── grub.cfg
├── grub.cfg.sig
├── initramfs
├── initramfs.sig
├── System.map
├── System.map.sig
├── vmlinuz
└── vmlinuz.sig
/efia
└── EFI
    └── boot
        └── bootx64.efi

2 directories, 1 file
```
