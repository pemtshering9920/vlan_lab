#!/bin/bash

# =============================================================================
# SMART VLAN ISOLATION LAB MANAGER (ENHANCED VM EDITION)
# =============================================================================
# Combines the best features of both versions with robust VM support
# =============================================================================

# --- CONFIGURATION ---
VLAN_ID="66"
LAB_IP_BASE="10.66.66"
CONFIG_FILE="${HOME}/.vlan_lab.conf"
LOG_FILE="/tmp/vlan_lab_$(date +%Y%m%d).log"

# Load user config if exists
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE" 2>/dev/null

# --- ENHANCED LOGGING ---
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="$*"
    echo -e "[$timestamp] $message" | tee -a "$LOG_FILE"
}

# --- SMART DETECTION ENGINE (ENHANCED) ---
detect_environment() {
    # Detect VM status first
    local vm_status="PHYSICAL"
    if [ -f "/sys/class/dmi/id/product_name" ]; then
        local product=$(cat /sys/class/dmi/id/product_name 2>/dev/null | tr '[:upper:]' '[:lower:]')
        [[ "$product" =~ (kvm|qemu|virtual|vmware|virtualbox|vbox) ]] && vm_status="VM"
    fi
    
    [ "$vm_status" = "PHYSICAL" ] && systemd-detect-virt 2>/dev/null | grep -q -v "none" && vm_status="VM"
    [ "$vm_status" = "PHYSICAL" ] && grep -q "hypervisor" /proc/cpuinfo 2>/dev/null && vm_status="VM"
    
    # Enhanced interface detection with VM optimization
    if [ "$vm_status" = "VM" ]; then
        # Try common VM interface names in priority order
        for iface in ens33 enp0s3 eth0 enp0s8 ens160 eth1; do
            if ip link show "$iface" >/dev/null 2>&1; then
                ACTIVE_IF="$iface"
                break
            fi
        done
        
        # Fallback: first non-special interface
        [ -z "$ACTIVE_IF" ] && ACTIVE_IF=$(ip -o link show | awk -F': ' '!/lo:/ && !/docker/ && !/veth/ && !/br-/ {print $2; exit}')
        
        log "[DETECT] Running in VM, using interface: $ACTIVE_IF"
    else
        # Physical host detection (multiple methods)
        ACTIVE_IF=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'dev \K\S+')
        [ -z "$ACTIVE_IF" ] && ACTIVE_IF=$(ip route | awk '/default/ {print $5; exit}')
        [ -z "$ACTIVE_IF" ] && ACTIVE_IF=$(route -n 2>/dev/null | awk '/^0.0.0.0/ {print $8; exit}')
    fi
    
    # Detect local subnet for isolation
    if [ -n "$ACTIVE_IF" ]; then
        LOCAL_NET=$(ip addr show "$ACTIVE_IF" 2>/dev/null | awk '/inet / {print $2}' | head -1 | cut -d'.' -f1-3)".0/24"
    fi
    
    # Determine system type with bridge detection
    if [ -d "/sys/class/net/br0" ]; then
        SYS_TYPE="HOST"
        if [ "$vm_status" = "VM" ]; then
            SYS_DESC="VM with existing bridge (unusual)"
        else
            SYS_DESC="Physical Host with bridge"
        fi
    elif [ "$vm_status" = "VM" ]; then
        SYS_TYPE="GUEST"
        if [ -f "/etc/kali-release" ] || hostnamectl 2>/dev/null | grep -qi kali || [ -f "/etc/kali_version" ]; then
            SYS_DESC="Kali Linux VM"
        else
            SYS_DESC="Linux VM"
        fi
    else
        SYS_TYPE="UNKNOWN"
        SYS_DESC="Physical Linux system"
    fi
    
    export ACTIVE_IF LOCAL_NET SYS_TYPE SYS_DESC VM_STATUS="$vm_status"
}

# --- VALIDATION (ENHANCED) ---
validate_environment() {
    local errors=0
    
    # Check root privileges
    if [ "$EUID" -ne 0 ]; then
        log "[!] Running without root privileges (some operations may fail)"
    fi
    
    # Validate VLAN ID
    if [[ ! "$VLAN_ID" =~ ^[0-9]{1,4}$ ]] || [ "$VLAN_ID" -lt 1 ] || [ "$VLAN_ID" -gt 4094 ]; then
        log "[-] ERROR: Invalid VLAN ID: $VLAN_ID (must be 1-4094)"
        errors=$((errors + 1))
    fi
    
    # Validate IP base
    if [[ ! "$LAB_IP_BASE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log "[-] ERROR: Invalid IP base format: $LAB_IP_BASE"
        errors=$((errors + 1))
    fi
    
    # Check for required tools
    for tool in ip iptables; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log "[-] ERROR: Required tool '$tool' not found"
            errors=$((errors + 1))
        fi
    done
    
    # Check network interface
    if [ -z "$ACTIVE_IF" ] || ! ip link show "$ACTIVE_IF" >/dev/null 2>&1; then
        log "[-] WARNING: Cannot detect valid network interface"
        log "[-] Interface '$ACTIVE_IF' not found"
        if [ "$VM_STATUS" = "VM" ]; then
            log "[-] VM TROUBLESHOOTING:"
            log "[-]   1. Check VM network is connected (not 'cable disconnected')"
            log "[-]   2. In QEMU: Use network mode 'Bridge' to 'br0'"
            log "[-]   3. Try: ip link show (to see all interfaces)"
        fi
        errors=$((errors + 1))
    fi
    
    return $errors
}

# --- SAFE EXECUTION (FIXED) ---
safe_exec() {
    local cmd="$*"
    local output status
    
    # Special handling for 'ip route del' to suppress expected errors
    if [[ "$cmd" == *"ip route del default"* ]]; then
        output=$(eval "$cmd" 2>&1)
        status=$?
        # 'No such process' is expected if no default route exists
        if [[ "$output" == *"No such process"* ]]; then
            return 0  # This is not an error for our use case
        fi
    else
        output=$(eval "$cmd" 2>&1)
        status=$?
    fi
    
    if [ $status -ne 0 ] && [ $status -ne 2 ]; then  # Allow exit code 2 for some commands
        log "[-] Command failed (status $status): $cmd"
        [ -n "$output" ] && log "    Output: $output"
        return $status
    fi
    
    echo "$output"
    return 0
}

# --- HOST SETUP (KEPT EXCELLENT VERSION) ---
setup_host() {
    log "[HOST] Starting setup..."
    
    if ! validate_environment; then
        log "[-] Environment validation failed"
        return 1
    fi
    
    # Warn if running in VM
    if [ "$VM_STATUS" = "VM" ]; then
        log "[!] WARNING: This appears to be a VM, not a physical host!"
        log "[!] Host setup should typically run on the PHYSICAL machine."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] || return 1
    fi
    
    # Check for existing setup
    if [ -d "/sys/class/net/br0" ]; then
        log "[!] Bridge br0 already exists. Reusing..."
    else
        # Load required kernel module
        safe_exec sudo modprobe 8021q || {
            log "[-] Failed to load 8021q module"
            return 1
        }
        
        # Create bridge
        safe_exec sudo ip link add br0 type bridge || {
            log "[-] Failed to create bridge"
            return 1
        }
        safe_exec sudo ip link set br0 up
        
        log "[+] Bridge br0 created and activated"
    fi
    
    # Create VLAN interface on bridge
    if [ -d "/sys/class/net/br0.$VLAN_ID" ]; then
        log "[!] VLAN interface br0.$VLAN_ID already exists"
        safe_exec sudo ip link set br0.$VLAN_ID down
        safe_exec sudo ip link delete br0.$VLAN_ID
    fi
    
    safe_exec sudo ip link add link br0 name br0.$VLAN_ID type vlan id $VLAN_ID
    safe_exec sudo ip addr add $LAB_IP_BASE.1/24 dev br0.$VLAN_ID
    safe_exec sudo ip link set br0.$VLAN_ID up
    
    # Enable IP forwarding
    safe_exec sudo sysctl -w net.ipv4.ip_forward=1
    echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-vlan-lab.conf >/dev/null
    
    # Configure NAT
    safe_exec sudo iptables -t nat -F
    safe_exec sudo iptables -t nat -A POSTROUTING -o "$ACTIVE_IF" -j MASQUERADE
    
    # Setup firewall isolation (The "Jail")
    safe_exec sudo iptables -F FORWARD
    if [ -n "$LOCAL_NET" ]; then
        safe_exec sudo iptables -A FORWARD -i br0.$VLAN_ID -d "$LOCAL_NET" -j REJECT
        log "[+] Local network isolation enabled: $LOCAL_NET"
    fi
    safe_exec sudo iptables -A FORWARD -i br0.$VLAN_ID -j ACCEPT
    safe_exec sudo iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    log "[+] HOST setup complete"
    log "[+] Gateway: $LAB_IP_BASE.1/24"
    log "[+] Bridge: br0 (VLAN $VLAN_ID tagged)"
    log "[+] NAT enabled via $ACTIVE_IF"
    log "[+] Configure VMs to use bridge 'br0' in QEMU/VirtualBox"
    
    return 0
}

# --- GUEST SETUP (FIXED FOR VMs) ---
setup_guest() {
    log "[GUEST] Starting setup..."
    
    if ! validate_environment; then
        log "[-] Environment validation failed"
        return 1
    fi
    
    # Check for existing VLAN interface
    local vlan_if="$ACTIVE_IF.$VLAN_ID"
    
    # Remove existing VLAN interface if exists (with force)
    if [ -d "/sys/class/net/$vlan_if" ]; then
        log "[!] VLAN interface $vlan_if already exists. Reconfiguring..."
        safe_exec sudo ip link set "$vlan_if" down
        safe_exec sudo ip link delete "$vlan_if"
        sleep 1
    fi
    
    # Load VLAN module
    safe_exec sudo modprobe 8021q || {
        log "[!] 8021q module might be built-in"
    }
    
    # Create tagged interface
    log "[*] Creating VLAN interface $vlan_if..."
    if ! safe_exec sudo ip link add link "$ACTIVE_IF" name "$vlan_if" type vlan id "$VLAN_ID"; then
        log "[-] FATAL: Failed to create VLAN interface"
        log "[-] Common causes:"
        log "[-]   1. Host bridge 'br0' not created yet"
        log "[-]   2. VM not configured for bridge networking"
        log "[-]   3. Interface $ACTIVE_IF doesn't exist"
        log "[-]"
        log "[-] SOLUTION:"
        log "[-]   1. Run 'Setup as HOST' on physical machine first"
        log "[-]   2. Configure VM to use 'Bridge' network with 'br0'"
        log "[-]   3. Ensure VM interface is connected"
        return 1
    fi
    
    # Configure IP
    safe_exec sudo ip addr add "$LAB_IP_BASE.2/24" dev "$vlan_if"
    safe_exec sudo ip link set "$vlan_if" up
    
    # Configure routing (with improved error handling)
    safe_exec sudo ip route del default 2>/dev/null
    safe_exec sudo ip route add default via "$LAB_IP_BASE.1"
    
    # Add direct route to prevent routing confusion
    safe_exec sudo ip route add "$LAB_IP_BASE.0/24" dev "$vlan_if" proto kernel scope link src "$LAB_IP_BASE.2"
    
    # Handle NetworkManager if present
    if command -v nmcli >/dev/null 2>&1 && systemctl is-active NetworkManager >/dev/null 2>&1; then
        log "[!] NetworkManager detected - taking control of $vlan_if"
        safe_exec sudo nmcli device set "$vlan_if" managed no 2>/dev/null
    fi
    
    # Configure DNS (with backup)
    if [ -f "/etc/resolv.conf" ]; then
        sudo cp /etc/resolv.conf /etc/resolv.conf.backup.vlan 2>/dev/null
    fi
    echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" | sudo tee /etc/resolv.conf >/dev/null
    
    log "[+] GUEST setup complete"
    log "[+] IP Address: $LAB_IP_BASE.2/24"
    log "[+] Gateway: $LAB_IP_BASE.1"
    log "[+] DNS: 8.8.8.8, 1.1.1.1"
    
    # Enhanced connectivity test with diagnostics
    log "[*] Testing connectivity..."
    
    # Wait for interface to settle
    sleep 2
    
    # Test 1: Interface status
    if ip link show "$vlan_if" | grep -q "state UP"; then
        log "[✓] Interface $vlan_if is UP"
    else
        log "[✗] Interface $vlan_if is DOWN"
    fi
    
    # Test 2: IP assignment
    if ip addr show "$vlan_if" | grep -q "inet $LAB_IP_BASE.2"; then
        log "[✓] IP address correctly assigned"
    else
        log "[✗] IP address not assigned"
    fi
    
    # Test 3: Gateway reachability (with retry)
    local gw_test_success=false
    for i in {1..3}; do
        log "[*] Gateway test attempt $i/3..."
        if ping -c 1 -W 2 "$LAB_IP_BASE.1" >/dev/null 2>&1; then
            gw_test_success=true
            log "[✓] Gateway $LAB_IP_BASE.1 is reachable"
            break
        fi
        sleep 1
    done
    
    if ! $gw_test_success; then
        log "[✗] Gateway NOT reachable - troubleshooting needed:"
        log "    1. Ensure HOST setup completed successfully"
        log "    2. Check VM is using 'Bridge' mode to 'br0'"
        log "    3. On HOST, verify: ip addr show br0.$VLAN_ID"
        log "    4. On GUEST, try: sudo arping -c 2 $LAB_IP_BASE.1"
    fi
    
    # Test 4: Internet connectivity (if gateway is up)
    if $gw_test_success; then
        if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            log "[✓] Internet connectivity OK"
        else
            log "[✗] No internet - check HOST NAT/firewall"
        fi
    fi
    
    # Show final configuration
    echo -e "\n=== FINAL NETWORK CONFIGURATION ==="
    ip -br addr show "$vlan_if"
    echo ""
    ip route show | grep -E "default|$LAB_IP_BASE"
    
    return 0
}

# --- SMART CLEANUP (IMPROVED) ---
smart_cleanup() {
    log "[*] Starting intelligent cleanup..."
    
    local cleaned_something=false
    
    # Clean HOST components
    if [ -d "/sys/class/net/br0.$VLAN_ID" ]; then
        log "[!] Removing VLAN interface: br0.$VLAN_ID"
        safe_exec sudo ip link delete br0.$VLAN_ID
        cleaned_something=true
    fi
    
    if [ -d "/sys/class/net/br0" ]; then
        log "[!] Removing bridge: br0"
        
        # Remove iptables rules related to br0
        safe_exec sudo iptables -F FORWARD
        safe_exec sudo iptables -t nat -F
        
        # Bring down and delete bridge
        safe_exec sudo ip link set br0 down
        safe_exec sudo ip link delete br0
        cleaned_something=true
    fi
    
    # Clean GUEST components (any interface with our VLAN ID)
    for iface in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep "\\.$VLAN_ID\$"); do
        log "[!] Removing VLAN interface: $iface"
        safe_exec sudo ip link delete "$iface"
        cleaned_something=true
    done
    
    # Restore original DNS if backup exists
    if [ -f "/etc/resolv.conf.backup.vlan" ]; then
        log "[!] Restoring original DNS configuration"
        sudo mv /etc/resolv.conf.backup.vlan /etc/resolv.conf
        cleaned_something=true
    fi
    
    # Disable IP forwarding if we enabled it
    if [ -f "/etc/sysctl.d/99-vlan-lab.conf" ]; then
        log "[!] Removing IP forwarding configuration"
        sudo rm -f /etc/sysctl.d/99-vlan-lab.conf
        safe_exec sudo sysctl -w net.ipv4.ip_forward=0
        cleaned_something=true
    fi
    
    # Re-enable NetworkManager management if we disabled it
    if command -v nmcli >/dev/null 2>&1; then
        for iface in $(nmcli -t -f DEVICE device status); do
            if [[ "$iface" == *".$VLAN_ID" ]]; then
                safe_exec sudo nmcli device set "$iface" managed yes 2>/dev/null
            fi
        done
    fi
    
    if $cleaned_something; then
        log "[+] Cleanup completed successfully"
    else
        log "[*] Nothing to clean up"
    fi
    
    return 0
}

# --- COMPREHENSIVE STATUS (ENHANCED) ---
show_status() {
    echo -e "\n=== VLAN LAB STATUS ==="
    echo "System Type:    $SYS_DESC"
    echo "VM Detection:   $VM_STATUS"
    echo "Active Interface: $ACTIVE_IF"
    echo "Local Network:  ${LOCAL_NET:-Not detected}"
    echo "VLAN ID:        $VLAN_ID"
    echo "Lab Network:    $LAB_IP_BASE.0/24"
    echo ""
    
    # Network interfaces
    echo "--- NETWORK INTERFACES ---"
    ip -br addr show | grep -E "(br0|\.$VLAN_ID|vlan)" | while read line; do
        echo "  $line"
    done
    
    # Bridges
    if command -v brctl >/dev/null 2>&1; then
        echo -e "\n--- BRIDGES ---"
        brctl show 2>/dev/null | grep -v "bridge name.*interfaces" | while read line; do
            echo "  $line"
        done
    fi
    
    # Routing
    echo -e "\n--- ROUTING TABLE ---"
    ip route | grep -E "(default|$LAB_IP_BASE|br0)" | while read line; do
        echo "  $line"
    done
    
    # Firewall rules
    echo -e "\n--- FIREWALL RULES (FORWARD chain) ---"
    sudo iptables -L FORWARD -n --line-numbers 2>/dev/null | tail -n+3 | while read line; do
        echo "  $line"
    done
    
    # Connectivity test
    echo -e "\n--- CONNECTIVITY ---"
    if ping -c 1 -W 1 "$LAB_IP_BASE.1" >/dev/null 2>&1; then
        echo "  ✓ Gateway ($LAB_IP_BASE.1) is reachable"
        
        # Test internet
        if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            echo "  ✓ Internet is reachable"
        else
            echo "  ✗ Internet is not reachable (NAT issue?)"
        fi
    else
        echo "  ✗ Gateway is not reachable"
        if [ "$SYS_TYPE" = "GUEST" ]; then
            echo "  ⚠  Ensure:"
            echo "     - HOST setup is complete"
            echo "     - VM uses 'Bridge' mode to 'br0'"
            echo "     - Run: sudo arping -c 2 $LAB_IP_BASE.1"
        fi
    fi
    
    # VLAN-specific info
    echo -e "\n--- VLAN DETAILS ---"
    ip -d link show 2>/dev/null | grep -A1 "vlan.*id $VLAN_ID" || echo "  No VLAN $VLAN_ID interfaces found"
    
    echo -e "\n=======================\n"
}

# --- HELP SCREEN WITH VM GUIDE ---
show_help() {
    clear
    cat << EOF
=== SMART VLAN LAB MANAGER ===

VM-SPECIFIC SETUP INSTRUCTIONS:
--------------------------------
1. ON PHYSICAL HOST (Mint/Ubuntu):
   $ sudo ./vlan_lab.sh
   → Select option 1 (Setup as HOST)

2. CONFIGURE QEMU/KVM VM:
   - Shutdown Kali VM
   - Set network to: BRIDGE mode
   - Bridge to: br0
   - Device model: virtio (recommended)
   - Start VM

3. INSIDE KALI VM:
   $ sudo ./vlan_lab.sh
   → Select option 2 (Setup as GUEST)

TROUBLESHOOTING COMMON ISSUES:
-----------------------------
1. "Interface not found" in VM:
   - Check VM network adapter is connected
   - Try: ip link show (list all interfaces)
   - In QEMU: Use '-netdev bridge,br=br0'

2. "Gateway not reachable":
   - Verify HOST br0.$VLAN_ID exists: ip addr show br0.$VLAN_ID
   - On GUEST: sudo arping -c 2 $LAB_IP_BASE.1
   - Check VM bridge settings

3. "No internet in VM":
   - On HOST: sudo iptables -t nat -L -n -v
   - Ensure: net.ipv4.ip_forward=1 on HOST

QUICK DIAGNOSTICS:
-----------------
On HOST:    ip addr show br0.$VLAN_ID
On GUEST:   ip addr show eth0.$VLAN_ID
Both:       ping $LAB_IP_BASE.1

CONFIGURATION:
-------------
Edit $CONFIG_FILE to change:
  VLAN_ID="66"
  LAB_IP_BASE="10.66.66"

LOGS: $LOG_FILE
EOF
    read -p "Press Enter to continue..."
}

# --- QEMU CONFIG GENERATOR ---
generate_qemu_config() {
    clear
    local vm_mac=$(date +%s | md5sum | head -c 6 | sed 's/../&:/g; s/:$//')
    vm_mac="52:54:00:$vm_mac"
    
    cat << EOF
=== QEMU CONFIGURATION ===

For QEMU command line:
----------------------
qemu-system-x86_64 \\
  -netdev bridge,br=br0,id=net0 \\
  -device virtio-net-pci,netdev=net0,mac=$vm_mac \\
  ...other options...

For libvirt XML (virt-manager):
-------------------------------
<interface type='bridge'>
  <mac address='$vm_mac'/>
  <source bridge='br0'/>
  <model type='virtio'/>
  <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
</interface>

For VirtualBox:
---------------
- Network: Bridged Adapter
- Name: br0
- Promiscuous Mode: Allow All
- Cable Connected: ✓

MAC Address: $vm_mac
Bridge: br0
VLAN Tag: $VLAN_ID (handled internally)
EOF
    
    echo -e "\nSave this MAC for your VM configuration."
    read -p "Press Enter to continue..."
}

# --- TROUBLESHOOT DIAGNOSTICS ---
run_diagnostics() {
    clear
    echo "=== SYSTEM DIAGNOSTICS ==="
    echo ""
    
    # 1. Basic system info
    echo "1. SYSTEM:"
    echo "   Hostname: $(hostname)"
    echo "   Distribution: $(lsb_release -ds 2>/dev/null || cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
    echo "   Kernel: $(uname -r)"
    echo ""
    
    # 2. All network interfaces
    echo "2. ALL NETWORK INTERFACES:"
    ip -br link show
    echo ""
    
    # 3. VLAN module
    echo "3. VLAN SUPPORT:"
    lsmod | grep -E "8021q|vlan" || echo "   No VLAN modules loaded"
    echo ""
    
    # 4. Current VLAN interfaces
    echo "4. EXISTING VLAN INTERFACES:"
    ip -d link show 2>/dev/null | grep -B1 "vlan" || echo "   None found"
    echo ""
    
    # 5. Routes
    echo "5. ROUTING TABLE:"
    ip route show
    echo ""
    
    # 6. ARP cache
    echo "6. ARP CACHE (relevant):"
    ip neigh show | grep -E "$LAB_IP_BASE|gateway" || echo "   No relevant entries"
    echo ""
    
    # 7. DNS
    echo "7. DNS CONFIGURATION:"
    cat /etc/resolv.conf 2>/dev/null | grep -v "^#"
    echo ""
    
    # 8. VM-specific checks
    if [ "$VM_STATUS" = "VM" ]; then
        echo "8. VM INFORMATION:"
        echo "   Detected as: $VM_STATUS"
        echo "   Primary interface: $ACTIVE_IF"
        echo "   MAC: $(ip link show $ACTIVE_IF 2>/dev/null | grep ether | awk '{print $2}')"
        echo ""
        echo "   RECOMMENDATION: Ensure VM is using Bridge to 'br0'"
    fi
    
    echo "=== END DIAGNOSTICS ==="
    read -p "Press Enter to continue..."
}

# --- MAIN MENU (ENHANCED) ---
main_menu() {
    while true; do
        clear
        echo "=========================================="
        echo "    SMART VLAN ISOLATION LAB MANAGER"
        echo "         (ENHANCED VM EDITION)"
        echo "=========================================="
        echo "  System: $SYS_DESC"
        echo "  Interface: $ACTIVE_IF"
        echo "  VM Status: $VM_STATUS"
        echo "  VLAN ID: $VLAN_ID"
        echo "------------------------------------------"
        
        # Show recommendation based on detection
        if [ "$VM_STATUS" = "VM" ]; then
            echo "  RECOMMENDED: 2 (Guest Setup)"
            echo "  Also useful: 6 (QEMU Config), 7 (Diagnose)"
        elif [ -d "/sys/class/net/br0" ]; then
            echo "  RECOMMENDED: 2 (Add Guest), 4 (Status)"
        else
            echo "  RECOMMENDED: 1 (Host Setup)"
        fi
        
        echo "------------------------------------------"
        echo "  1) Setup as HOST (Physical Bridge)"
        echo "  2) Setup as GUEST (VM Tagged Interface)"
        echo "  3) Smart Cleanup (Auto-detect)"
        echo "  4) Show Detailed Status"
        echo "  5) Save Current Configuration"
        echo "  6) QEMU/VirtualBox Config Generator"
        echo "  7) Run Diagnostics"
        echo "  8) Help / Instructions"
        echo "  9) View Logs"
        echo "  0) Exit"
        echo "=========================================="
        
        read -p "Select option [0-9]: " choice
        
        case $choice in
            1)
                if setup_host; then
                    read -p "Host setup complete. Press Enter to continue..."
                else
                    read -p "Host setup failed. Check logs. Press Enter..."
                fi
                ;;
            2)
                if setup_guest; then
                    read -p "Guest setup complete. Press Enter to continue..."
                else
                    read -p "Guest setup failed. Check logs. Press Enter..."
                fi
                ;;
            3)
                smart_cleanup
                read -p "Press Enter to continue..."
                ;;
            4)
                show_status
                read -p "Press Enter to continue..."
                ;;
            5)
                echo "Saving configuration to $CONFIG_FILE..."
                echo "VLAN_ID=\"$VLAN_ID\"" > "$CONFIG_FILE"
                echo "LAB_IP_BASE=\"$LAB_IP_BASE\"" >> "$CONFIG_FILE"
                echo "Configuration saved."
                read -p "Press Enter to continue..."
                ;;
            6)
                generate_qemu_config
                ;;
            7)
                run_diagnostics
                ;;
            8)
                show_help
                ;;
            9)
                echo "=== LOG FILE (last 30 lines) ==="
                tail -30 "$LOG_FILE" 2>/dev/null || echo "No log file found."
                read -p "Press Enter to continue..."
                ;;
            0)
                echo "Exiting. Goodbye!"
                exit 0
                ;;
            *)
                echo "Invalid option. Please try again."
                sleep 1
                ;;
        esac
    done
}

# --- INITIALIZATION ---
initialize() {
    # Create log file
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE" 2>/dev/null
    
    # Detect environment
    detect_environment
    
    # Log startup
    log "=== SMART VLAN LAB MANAGER STARTED ==="
    log "System: $SYS_DESC"
    log "VM Status: $VM_STATUS"
    log "Interface: $ACTIVE_IF"
    log "Local Network: ${LOCAL_NET:-Unknown}"
    
    # Check for existing configuration
    if [ -f "$CONFIG_FILE" ]; then
        log "Loaded configuration from $CONFIG_FILE"
    fi
}

# --- MAIN EXECUTION ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    initialize
    main_menu
fi