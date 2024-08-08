#!/bin/bash

set -e

# DO NOT KNOW IF THIS VERSION IS WORKING
# DO NOT KNOW IF THIS VERSION IS WORKING
# DO NOT KNOW IF THIS VERSION IS WORKING

# this is the script for setting up the server side
# you could connect to it using 'OpenVPN Connect' on Windows
# https://openvpn.net/client/

if [[ $EUID -ne 0 ]]; then
  echo "You must be a root user" 1>&2
  exit 1
fi

if [ -f /etc/debian_version ]; then
  DISTRO="Debian"
elif [ -f /etc/redhat-release ]; then
  DISTRO="RedHat"
else
  echo "Unsupported distribution" 1>&2
  exit 1
fi

# install packages based on dist
if [ "$DISTRO" = "Debian" ]; then
  apt-get update -q
  apt-get install -qy openvpn curl iptables-persistent openssl
elif [ "$DISTRO" = "RedHat" ]; then
  yum install -y epel-release
  yum install -y openvpn curl iptables-services openssl
  systemctl enable iptables
fi

# Set debconf selections for iptables-persistent
if [ "$DISTRO" = "Debian" ]; then
  debconf-set-selections <<EOF
iptables-persistent iptables-persistent/autosave_v4 boolean true
iptables-persistent iptables-persistent/autosave_v6 boolean true
EOF
fi

cd /etc/openvpn

# CA keys and certs
openssl genpkey -algorithm RSA -out ca-key.pem -pkeyopt rsa_keygen_bits:2048
openssl req -sha256 -new -key ca-key.pem -out ca-csr.pem -subj /CN=OpenVPN-CA/
openssl x509 -req -sha256 -in ca-csr.pem -signkey ca-key.pem -days 365 -out ca-cert.pem
echo 01 > ca-cert.srl

# server keys and certs
openssl genpkey -algorithm RSA -out server-key.pem -pkeyopt rsa_keygen_bits:2048
openssl req -sha256 -new -key server-key.pem -out server-csr.pem -subj /CN=OpenVPN-Server/
openssl x509 -sha256 -req -in server-csr.pem -CA ca-cert.pem -CAkey ca-key.pem -days 365 -out server-cert.pem

# client keys and certs
openssl genpkey -algorithm RSA -out client-key.pem -pkeyopt rsa_keygen_bits:2048
openssl req -sha256 -new -key client-key.pem -out client-csr.pem -subj /CN=OpenVPN-Client/
openssl x509 -req -sha256 -in client-csr.pem -CA ca-cert.pem -CAkey ca-key.pem -days 365 -out client-cert.pem

# Diffie-Hellman params
openssl dhparam -out dh.pem 2048

# perms on key files
chmod 600 *-key.pem

#  IP forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# NAT using iptables
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
if [ "$DISTRO" = "Debian" ]; then
  iptables-save > /etc/iptables/rules.v4
elif [ "$DISTRO" = "RedHat" ]; then
  service iptables save
fi

# Get the server's public IP
SERVER_IP=$(curl -s4 ifconfig.me || echo "<insert server IP here>")

# OpenVPN conf files
cat <<EOF > udp80.conf
server      10.8.0.0 255.255.255.0
verb        3
duplicate-cn
key         server-key.pem
ca          ca-cert.pem
cert        server-cert.pem
dh          dh.pem
keepalive   10 120
persist-key yes
persist-tun yes
comp-lzo    no
push        "dhcp-option DNS 8.8.8.8"
push        "dhcp-option DNS 8.8.4.4"
push        "redirect-gateway def1 bypass-dhcp"
user        nobody
group       nogroup
proto       udp
port        80
dev         tap80
status      openvpn-status-80.log
EOF

cat <<EOF > tcp443.conf
server      10.8.0.0 255.255.255.0
verb        3
duplicate-cn
key         server-key.pem
ca          ca-cert.pem
cert        server-cert.pem
dh          dh.pem
keepalive   10 120
persist-key yes
persist-tun yes
comp-lzo    no
push        "dhcp-option DNS 8.8.8.8"
push        "dhcp-option DNS 8.8.4.4"
push        "redirect-gateway def1 bypass-dhcp"
user        nobody
group       nogroup
proto       tcp
port        443
dev         tap443
status      openvpn-status-443.log
EOF

#client conf file
cat <<EOF > client.ovpn
client
nobind
dev tap
redirect-gateway def1 bypass-dhcp
remote $SERVER_IP 80 udp
comp-lzo no

<key>
$(cat client-key.pem)
</key>
<cert>
$(cat client-cert.pem)
</cert>
<ca>
$(cat ca-cert.pem)
</ca>
EOF

# restart
if [ "$DISTRO" = "Debian" ]; then
  systemctl restart openvpn
elif [ "$DISTRO" = "RedHat" ]; then
  systemctl restart openvpn@server
fi

cat client.ovpn
cd -
