Create your [~/.ssh/authorized_keys](https://wiki.gentoo.org/wiki/SSH#Passwordless_authentication):

```shell
rsync -av --chown=david:david /etc/gentoo-installation/systemrescuecd/recipe/build_into_srm/root/.ssh/authorized_keys /home/david/.ssh/ && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Setup "net-misc/openssh":

```shell hl_lines="1"
rsync -a /etc/ssh/sshd_config /etc/ssh/._cfg0000_sshd_config && \
sed -i \
-e 's/^#Port 22$/Port 50022/' \
-e 's/^#PermitRootLogin prohibit-password$/PermitRootLogin no/' \
-e 's/^#KbdInteractiveAuthentication yes$/KbdInteractiveAuthentication no/' \
-e 's/^#X11Forwarding no$/X11Forwarding no/' /etc/ssh/._cfg0000_sshd_config && \
grep -q "^PasswordAuthentication no$" /etc/ssh/._cfg0000_sshd_config && \
echo "
AuthenticationMethods publickey

KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

AllowUsers david" >> /etc/ssh/._cfg0000_sshd_config && \
ssh-keygen -A && \
sshd -t && \
systemctl --no-reload enable sshd.service && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Open the SSH port:

```shell hl_lines="1"
rsync -a /usr/local/sbin/firewall.nft /usr/local/sbin/._cfg0000_firewall.nft && \
sed -i 's/^#\([[:space:]]*\)tcp dport 50022 accept$/\1tcp dport 50022 accept/' /usr/local/sbin/._cfg0000_firewall.nft && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Write down fingerprints to double check upon initial SSH connection to the Gentoo Linux machine:

```shell
find /etc/ssh/ -type f -name "ssh_host*\.pub" -exec ssh-keygen -vlf {} \;
```