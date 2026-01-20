VLAN Isolation Lab Manager

<div align="center">
https://img.shields.io/badge/Network-Isolated%2520Lab-blue
https://img.shields.io/badge/Platform-Linux%2520%257C%2520Kali%2520VM-green
https://img.shields.io/badge/License-MIT-orange

Create secure, isolated VLAN lab environments for cybersecurity training

</div>


Complete Setup Guide
Step 1: Install QEMU/KVM and Dependencies
For Arch-based Systems:

bash
sudo pacman -S qemu-full virt-manager virt-viewer dnsmasq vde2 bridge-utils openbsd-netcat libvirt libguestfs ebtables spice-vdagent virtiofsd
For Debian/Ubuntu Systems:

bash
sudo apt install qemu-system qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager virt-viewer dnsmasq vde2 ebtables iptables qemu-guest-agent spice-vdagent virtiofsd
Common Configuration:

bash
# Enable and start libvirtd
sudo systemctl enable libvirtd
sudo systemctl start libvirtd

# Add user to groups
sudo usermod -aG libvirt $(whoami)
sudo usermod -aG kvm $(whoami)
newgrp libvirt

# Configure default network
sudo virsh net-start default
sudo virsh net-autostart default

# Set firewall backend to iptables
sudo bash -c 'echo "firewall_backend = \"iptables\"" > /etc/libvirt/network.conf'
sudo systemctl restart libvirtd
Step 2: Run Host Setup
On your physical machine:

bash
# Download and make executable
wget https://raw.githubusercontent.com/yourusername/vlan-lab/main/vlan_lab.sh
chmod +x vlan_lab.sh

# Run as host
sudo ./vlan_lab.sh
Select option: 1 (Setup as HOST)

Step 3: Configure VM Network
Shutdown your Kali VM

Open VM Settings → Network

Set to: Bridge mode

Bridge to: br0

Start VM

Step 4: Run Guest Setup
Inside Kali VM:

bash
# Get the script in VM
wget https://raw.githubusercontent.com/yourusername/vlan-lab/main/vlan_lab.sh
chmod +x vlan_lab.sh

# Run as guest
sudo ./vlan_lab.sh
Select option: 2 (Setup as GUEST)

Step 5: Test Connectivity
In Kali VM:

bash
ping 10.66.66.1    # Should work (host gateway)
ping 8.8.8.8       # Should work (internet)
ping 192.168.1.1   # Should FAIL (home network isolated)
Cleanup (When Done)
On both systems:

bash
sudo ./vlan_lab.sh
Select option: 3 (Smart Cleanup)

Troubleshooting
If internet doesn't work in VM:

Check ip addr show br0.66 on host

Verify VM uses "Bridge to br0"

Run sudo iptables -t nat -L on host

If script shows "Interface not found":

Run ip link show to see interface names

Ensure VM network adapter is connected

Network Layout
text
Host: 10.66.66.1/24 (gateway)
VM:   10.66.66.2/24
VLAN: 66
Note: Your home network (192.168.x.x) is automatically blocked for safety.
