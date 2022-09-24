!!! note
    I connect to libvirtd via TCP and SSH port forwarding, because I want to use my SSH key which is secured on a hardware token, and `virt-manager` doesn't seem to be able to handle my hardware token directly. Thus, I can't use s.th. like `qemu+ssh://david@192.168.10.3:50022/system`.

I prefer managing downloads and network myself:

```shell
echo "\
app-emulation/libvirt -virt-network
app-emulation/qemu -curl" >> /etc/portage/package.use/main
```

I setup the internal network manually:

```shell
❯ head /etc/systemd/network/br0.*
==> /etc/systemd/network/br0.netdev <==
[NetDev]
Name=br0
Kind=bridge

==> /etc/systemd/network/br0.network <==
[Match]
Name=br0

[Network]
Address=192.168.110.1/24
ConfigureWithoutCarrier=true
```

Install:

```shell
emerge -av app-emulation/libvirt
```

Enable libvirt's [TCP transport](https://libvirt.org/remote.html#transports):

```shell
systemctl enable libvirtd-tcp.socket && \
systemctl start libvirtd-tcp.socket && \
systemctl enable libvirt-guests.service && \
systemctl start libvirt-guests.service && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

systemd should listen now on TCP port 16509:

```shell
❯ lsof -nP -iTCP -sTCP:LISTEN
COMMAND    PID            USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
systemd      1            root   48u  IPv6  50548      0t0  TCP *:16509 (LISTEN)
systemd-r 1063 systemd-resolve   12u  IPv4  18306      0t0  TCP *:5355 (LISTEN)
systemd-r 1063 systemd-resolve   14u  IPv6  18309      0t0  TCP *:5355 (LISTEN)
systemd-r 1063 systemd-resolve   18u  IPv4  18313      0t0  TCP 127.0.0.53:53 (LISTEN)
systemd-r 1063 systemd-resolve   20u  IPv4  18315      0t0  TCP 127.0.0.54:53 (LISTEN)
sshd      1096            root    3u  IPv4  18400      0t0  TCP *:50022 (LISTEN)
sshd      1096            root    4u  IPv6  18401      0t0  TCP *:50022 (LISTEN)
```

Forward the connection with:

```shell
ssh -NL 56509:127.0.0.1:16509 -p 50022 david@192.168.10.3
```

Add this connection in `virt-manager`:

```shell
qemu+tcp://127.0.0.1:56509/system
```
