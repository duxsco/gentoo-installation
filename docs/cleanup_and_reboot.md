  - Setup [network](https://wiki.gentoo.org/wiki/Systemd#Network) (copy&paste one after the other):

```shell
echo "\
[Match]
Name=enp1s0

[Network]
Address=192.168.10.2/24
Gateway=192.168.10.1
# https://wiki.archlinux.org/title/IPv6#systemd-networkd_3
LinkLocalAddressing=no
IPv6AcceptRA=no\
" >> /etc/systemd/network/50-static.network

systemctl --no-reload enable systemd-networkd.service
```

  - Setup DNS (copy&paste one after the other):

```shell hl_lines="5"
# https://wiki.gentoo.org/wiki/Resolv.conf
# https://wiki.archlinux.org/title/systemd-resolved
ln -rsf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

cp -av /etc/systemd/resolved.conf /etc/systemd/._cfg0000_resolved.conf

# https://www.kuketz-blog.de/empfehlungsecke/#dns
sed -i \
-e 's/#DNS=.*/DNS=2001:678:e68:f000::#dot.ffmuc.net 2001:678:ed0:f000::#dot.ffmuc.net 5.1.66.255#dot.ffmuc.net 185.150.99.255#dot.ffmuc.net/' \
-e 's/#FallbackDNS=.*/FallbackDNS=2a01:4f8:251:554::2#dns3.digitalcourage.de 5.9.164.112#dns3.digitalcourage.de/' \
-e 's/#Domains=.*/Domains=~./' \
-e 's/#DNSSEC=.*/DNSSEC=true/' \
-e 's/#DNSOverTLS=.*/DNSOverTLS=true/' \
/etc/systemd/._cfg0000_resolved.conf

systemctl --no-reload enable systemd-resolved.service
```

After reboot into Gentoo Linux, test DNS resolving ([link](https://openwrt.org/docs/guide-user/services/dns/dot_unbound#testing)) and check `resolvectl status` output.

  - stage3 and dev* files:

```shell
rm -fv /stage3-* /portage-latest.tar.xz* /devEfi* /devRescue /devSystem* /devSwap* /mapperRescue /mapperSwap /mapperSystem && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

  - exit and reboot (copy&paste one after the other):

```shell
exit
exit
exit
cd
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -R /mnt/gentoo
reboot
```
