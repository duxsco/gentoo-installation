#!/usr/bin/env bash

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

iptables -A INPUT -p icmp --icmp-type 8 -j ACCEPT

# https://datatracker.ietf.org/doc/html/rfc4890#section-4.4.1
ip6tables -A INPUT -p icmpv6 --icmpv6-type 128 -j ACCEPT
ip6tables -A INPUT -p icmpv6 --icmpv6-type 133 -j ACCEPT
ip6tables -A INPUT -p icmpv6 --icmpv6-type 134 -j ACCEPT
ip6tables -A INPUT -p icmpv6 --icmpv6-type 135 -j ACCEPT
ip6tables -A INPUT -p icmpv6 --icmpv6-type 136 -j ACCEPT
ip6tables -A INPUT -p icmpv6 --icmpv6-type 141 -j ACCEPT
ip6tables -A INPUT -p icmpv6 --icmpv6-type 142 -j ACCEPT
ip6tables -A INPUT -p icmpv6 --icmpv6-type 130 -j ACCEPT -s fe80::/10
ip6tables -A INPUT -p icmpv6 --icmpv6-type 131 -j ACCEPT -s fe80::/10
ip6tables -A INPUT -p icmpv6 --icmpv6-type 132 -j ACCEPT -s fe80::/10
ip6tables -A INPUT -p icmpv6 --icmpv6-type 143 -j ACCEPT -s fe80::/10
ip6tables -A INPUT -p icmpv6 --icmpv6-type 148 -j ACCEPT
ip6tables -A INPUT -p icmpv6 --icmpv6-type 149 -j ACCEPT
ip6tables -A INPUT -p icmpv6 --icmpv6-type 151 -j ACCEPT -s fe80::/10
ip6tables -A INPUT -p icmpv6 --icmpv6-type 152 -j ACCEPT -s fe80::/10
ip6tables -A INPUT -p icmpv6 --icmpv6-type 153 -j ACCEPT -s fe80::/10

iptables  -A FORWARD -m conntrack --ctstate INVALID,UNTRACKED -j DROP
iptables  -A INPUT   -m conntrack --ctstate INVALID,UNTRACKED -j DROP
ip6tables -A FORWARD -m conntrack --ctstate INVALID,UNTRACKED -j DROP
ip6tables -A INPUT   -m conntrack --ctstate INVALID,UNTRACKED -j DROP

iptables  -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables  -A INPUT   -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ip6tables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ip6tables -A INPUT   -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

iptables -A INPUT -i lo -j ACCEPT
ip6tables -A INPUT -i lo -j ACCEPT

iptables  -A INPUT -p tcp --dport 50024 -j ACCEPT
ip6tables -A INPUT -p tcp --dport 50024 -j ACCEPT
