#!/bin/bash

# DO NOT KNOW IF THIS VERSION IS WORKING

set -e

if [[ $EUID -ne 0 ]]; then
  echo "You must be a root user" 1>&2
  exit 1
fi

apt-get update -q
debconf-set-selections <<EOF
iptables-persistent iptables-persistent/autosave_v4 boolean true
iptables-persistent iptables-persistent/autosave_v6 boolean true
EOF
apt-get install -qy openvpn curl iptables-persistent

cd /etc/openvpn

# authority
openssl genpkey -algorithm RSA -out ca-key.pem -pkeyopt rsa_keygen_bits:2048
openssl req -sha256 -new -key ca-key.pem -out ca-csr.pem -subj /CN=OpenVPN-CA/
openssl x509 -req -sha256 -in ca-csr.pem -signkey ca-key.pem -days 365 -out ca-cert.pem
echo 01 > ca-cert.srl

# server
openssl genpkey -algorithm RSA -out server-key.pem -pkeyopt rsa_keygen_bits:2048
openssl req -sha256 -new -key server-key.pem -out server-csr.pem -subj /CN=OpenVPN-Server/
openssl x509 -sha256 -req -in server-csr.pem -CA ca-cert.pem -CAkey ca-key.pem -days 365 -out server-cert.pem

# client
openssl genpkey -algorithm RSA -out client-key.pem -pkeyopt rsa_keygen_bits:2048
openssl req -sha256 -new -key client-key.pem -out client-csr.pem -subj /CN=OpenVPN-Client/
openssl x509 -req -sha256 -in client-csr.pem -CA ca-cert.pem -CAkey ca-key.pem -days 365 -out client-cert.pem

openssl dhparam -out dh.pem 2048

chmod 600 *-key.pem

echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
iptables-save > /etc/iptables/rules.v4

SERVER_IP=$(curl -s4 ifconfig.me || echo "<insert server IP here>")

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

systemctl restart openvpn
cat client.ovpn
cd -
