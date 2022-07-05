
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
