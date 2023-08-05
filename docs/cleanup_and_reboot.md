Before rebooting, fetch "net-firewall/nftables" to be able to setup the firewall before connecting to the network with Gentoo Linux for the first time:

```shell
emerge --fetchonly net-firewall/nftables
```

Configure the [network connection](https://wiki.gentoo.org/wiki/Systemd#Network) (copy&paste one command after the other):

``` { .shell .no-copy }
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

Setup [systemd-resolved](https://wiki.archlinux.org/title/systemd-resolved) for DNS (copy&paste one command after the other):

``` { .shell hl_lines="5" .no-copy }
# https://wiki.gentoo.org/wiki/Resolv.conf
# https://wiki.archlinux.org/title/systemd-resolved
ln -rsf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

rsync -av /etc/systemd/resolved.conf /etc/systemd/._cfg0000_resolved.conf

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

After the reboot, you can test DNS resolving ([link](https://openwrt.org/docs/guide-user/services/dns/dot_unbound#testing)) and check `resolvectl status` output.

Exit, cleanup obsolete installation files as well as [symlinks to devices created by "disk.sh"](https://github.com/duxsco/gentoo-installation/blob/main/bin/disk.sh#L180-L199) and [reboot](https://wiki.gentoo.org/wiki/Handbook:AMD64/Full/Installation#Rebooting_the_system) (copy&paste one command after the other):

``` { .shell .no-copy }
[[ -f /gentoo-latest.tar.xz ]] && exit
[[ -f /gentoo-latest.tar.xz ]] && exit
[[ -f /gentoo-latest.tar.xz ]] && exit
cd
rm -fv /mnt/gentoo/{stage3-*,gentoo-latest.tar.xz*,devEfi*,devRescue,devSystem*,devSwap*,mapperRescue,mapperSwap,mapperSystem}
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -R /mnt/gentoo
reboot
```
