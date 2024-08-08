### OpenVPN endpoint script

This script sets up an OpenVPN server on Debian-based (Ubuntu) or Red Hat-based (CentOS, RHEL, Fedora) distributions. It installs necessary packages, generates keys and certificates, configures IP forwarding and NAT, and creates server and client configuration files.

#### Usage

1. **Run the Script as Root**:
   ```bash
   sudo ./setup_openvpn.sh
   ```

2. **Client Configuration**:
   Use the generated `client.ovpn` file to connect to the VPN server using an OpenVPN client.

#### Script Actions

- **Identifies Distribution**
- **Installs Required Packages**
- **Configures IPTables Persistence (Debian)**
- **Generates Keys and Certs**:
  - CA
  - Server
  - Client
- **Enable IP Forwarding**
- **Configure NAT with IPTables**
- **Creates OpenVPN Server Configurations**:
  - `udp80.conf` for UDP on port 80
  - `tcp443.conf` for TCP on port 443
- **Creates OpenVPN Client Configuration (`client.ovpn`)**

#### Client Setup

- Download the OpenVPN client from [OpenVPN Connect](https://openvpn.net/client/).
- Import the `client.ovpn` file into the OpenVPN client to connect.

### Notes

- Ensure the script is executable:
   ```bash
   chmod +x setup_openvpn.sh
   ```
- Modify network interface (`eth0`) if different.
- Manually insert server IP in `client.ovpn` if not auto-detected.
    `
