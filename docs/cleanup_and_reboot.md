  - Setup [network](https://wiki.gentoo.org/wiki/Systemd#Network) (copy&paste one after the other):

```bash
cat <<EOF >> /etc/systemd/network/50-static.network
[Match]
Name=enp1s0

[Network]
Address=192.168.10.2/24
Gateway=192.168.10.1
DNS=192.168.10.1
# https://wiki.archlinux.org/title/IPv6#systemd-networkd_3
LinkLocalAddressing=no
IPv6AcceptRA=no
EOF

systemctl --no-reload enable systemd-networkd.service

ln -snf /run/systemd/resolve/resolv.conf /etc/resolv.conf

systemctl --no-reload enable systemd-resolved.service
```

  - stage3 and dev* files:

```bash
rm -fv /stage3-* /portage-latest.tar.xz* /devBoot* /devEfi* /devRescue /devSystem* /devSwap* /mapperBoot /mapperRescue /mapperSwap /mapperSystem; echo $?
```

  - exit and reboot (copy&paste one after the other):

```bash
exit
exit
exit
cd
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -R /mnt/gentoo
reboot
```
