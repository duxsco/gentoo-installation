#!/usr/bin/env bash

# Credits:
# https://github.com/openwrt/openwrt/blob/master/package/network/config/firewall/files/firewall.config

iptables -F
iptables -X
iptables -t nat -F
ip6tables -F
ip6tables -X

iptables -P FORWARD DROP
iptables -P INPUT DROP
iptables -P OUTPUT ACCEPT
ip6tables -P FORWARD DROP
ip6tables -P INPUT DROP
ip6tables -P OUTPUT ACCEPT

iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
ip6tables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
ip6tables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

iptables -A INPUT -i lo -j ACCEPT
ip6tables -A INPUT -i lo -j ACCEPT

iptables -A INPUT -p icmp --icmp-type 8 -j ACCEPT

ip6tables -A INPUT -s fc00::/6 -d fc00::/6 -p udp --dport 546 -j ACCEPT
ip6tables -A INPUT -p icmpv6 --icmpv6-type 1 -j ACCEPT
ip6tables -A INPUT -p icmpv6 --icmpv6-type 2 -j ACCEPT
ip6tables -A INPUT -p icmpv6 --icmpv6-type 3 -j ACCEPT
ip6tables -A INPUT -p icmpv6 --icmpv6-type 4 -j ACCEPT
ip6tables -A INPUT -p icmpv6 --icmpv6-type 128 -j ACCEPT
ip6tables -A INPUT -p icmpv6 --icmpv6-type 129 -j ACCEPT
ip6tables -A INPUT -p icmpv6 --icmpv6-type 133 -j ACCEPT
ip6tables -A INPUT -p icmpv6 --icmpv6-type 134 -j ACCEPT
ip6tables -A INPUT -p icmpv6 --icmpv6-type 135 -j ACCEPT
ip6tables -A INPUT -p icmpv6 --icmpv6-type 136 -j ACCEPT
