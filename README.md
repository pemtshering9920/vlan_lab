<div align="center">
<h1>🔐 VLAN Isolation Lab Manager</h1>
<p><strong>Create an isolated networking environment for safe cybersecurity practice</strong></p>
</div>

<hr>

<h2>📋 Overview</h2>
<p>This tool creates a secure, isolated VLAN network between your physical host and Kali Linux VM. Your Kali VM gets internet access but <strong>cannot access your home network</strong> - perfect for safe penetration testing practice.</p>

<p><strong>Network Layout:</strong></p>
<ul>
<li>Host: <code>10.66.66.1/24</code> (gateway)</li>
<li>Kali VM: <code>10.66.66.2/24</code></li>
<li>VLAN ID: <code>66</code></li>
<li>Home network: <strong>BLOCKED</strong></li>
</ul>

<hr>

<h2>🛠️ Prerequisites: QEMU/KVM Installation</h2>

<h3>For Arch-based Systems (Arch, Manjaro, EndeavourOS):</h3>

<pre><code># Install all the Tools & Dependencies
sudo pacman -S qemu-full virt-manager virt-viewer dnsmasq vde2 bridge-utils openbsd-netcat libvirt libguestfs ebtables spice-vdagent virtiofsd</code></pre>

<p><strong>Note:</strong> Some new systems come pre-installed with iptables-nft instead of legacy iptables. Installing 'iptables' is optional, only include if you want.</p>

<h3>For Debian/Ubuntu based System:</h3>

<pre><code>sudo apt install qemu-system qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager virt-viewer dnsmasq vde2 ebtables iptables qemu-guest-agent spice-vdagent virtiofsd</code></pre>

<hr>

<h2>⚙️ Common Configuration Steps</h2>

<h3>STEP 1: Enable libvirtd</h3>
<pre><code>sudo systemctl enable libvirtd
sudo systemctl start libvirtd</code></pre>

<h3>STEP 2: Add user to libvirt group</h3>
<pre><code>sudo usermod -aG libvirt $(whoami)
sudo usermod -aG kvm $(whoami)
newgrp libvirt</code></pre>

<h3>STEP 3: Check virtual network status</h3>
<pre><code>sudo EDITOR=vim virsh net-edit default
sudo systemctl status libvirtd</code></pre>

<p><strong>For Ubuntu/Debian:</strong></p>
<pre><code>sudo systemctl start libvirtd
sudo systemctl enable libvirtd</code></pre>

<h3>STEP 4: Start and configure autostart for the default network</h3>
<pre><code>sudo virsh net-start default
sudo virsh net-autostart default</code></pre>

<h3>STEP 5: Configure firewall_backend on libvirt network config</h3>
<pre><code>sudo vim /etc/libvirt/network.conf</code></pre>
<p>Edit this config and add:</p>
<pre><code>firewall_backend = "iptables"</code></pre>
<p><strong>Note:</strong> It will not work without setting this up to iptables in new systems.</p>

<h3>STEP 6: Restart libvirtd</h3>
<pre><code>sudo systemctl restart libvirtd</code></pre>

<h3>STEP 7: Start Virtual Machine Manager</h3>
<pre><code>virt-manager</code></pre>

<hr>

<h2>🚀 Using VLAN Isolation Lab Manager</h2>

<h3>Step 1: Download the Script</h3>
<pre><code>wget https://github.com/pemtshering9920/vlan_lab/blob/main/isolated_vlan_lab.sh
chmod +x isolated_vlan_lab.sh</code></pre>

<h3>Step 2: Run as HOST (Physical Machine)</h3>
<pre><code>sudo ./isolated_vlan_lab.sh</code></pre>
<p>Select option: <code>1</code> (Setup as HOST)</p>

<h3>Step 3: Configure QEMU VM</h3>
<ol>
<li>Open QEMU VM in Bridge mode</li>
<li>Set device name to: <code>br0</code></li>
<li>Save and start the VM</li>
</ol>

<h3>Step 4: Run as GUEST (Inside VM)</h3>
<pre><code>sudo ./isolated_vlan_lab.sh</code></pre>
<p>Select option: <code>2</code> (Setup as GUEST)</p>

<h3>Step 5: Check Internet Connection</h3>
<pre><code>ping 8.8.8.8</code></pre>

<hr>

<h2>🔄 Cleanup</h2>
<pre><code>sudo ./isolated_vlan_lab.sh</code></pre>
<p>Select option: <code>3</code> (Smart Cleanup)</p>

<hr>

<h2>❓ Troubleshooting</h2>

<h3>If internet doesn't work:</h3>
<ol>
<li>Check <code>ip addr show br0.66</code> on host</li>
<li>Verify VM uses "Bridge to br0" not NAT</li>
<li>Run <code>sudo iptables -t nat -L</code> on host</li>
</ol>

<h3>If interface not found:</h3>
<pre><code>ip link show</code></pre>
<p>Check your interface name (eth0, ens33, enp0s3, etc.)</p>

<hr>

<div align="center">
<p><strong>Happy and safe penetration testing! 🎯</strong></p>
</div>
