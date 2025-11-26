#!/bin/bash
#
# Quick network interface bandwidth check script
# Works on Linux systems with or without specialized tools
#

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print section header
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to get interface list
get_interfaces() {
    ls /sys/class/net/ 2>/dev/null | grep -v "^lo$" || echo ""
}

# Main script
main() {
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Network Interface Bandwidth Check    ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    
    # Get interfaces
    interfaces=$(get_interfaces)
    
    if [ -z "$interfaces" ]; then
        echo -e "${RED}✗ No network interfaces found${NC}"
        exit 1
    fi
    
    # List interfaces
    print_header "Available Interfaces"
    echo "$interfaces" | while read -r iface; do
        operstate=$(cat /sys/class/net/"$iface"/operstate 2>/dev/null || echo "unknown")
        mtu=$(cat /sys/class/net/"$iface"/mtu 2>/dev/null || echo "unknown")
        mac=$(cat /sys/class/net/"$iface"/address 2>/dev/null || echo "unknown")
        
        if [ "$operstate" = "up" ]; then
            echo -e "  ${GREEN}●${NC} $iface (state: $operstate, mtu: $mtu, mac: $mac)"
        else
            echo -e "  ${RED}●${NC} $iface (state: $operstate, mtu: $mtu, mac: $mac)"
        fi
    done
    
    # Check /sys/class/net/ info
    print_header "Interface Details (from /sys/class/net/)"
    echo "$interfaces" | while read -r iface; do
        echo -e "\n${YELLOW}Interface: $iface${NC}"
        
        speed=$(cat /sys/class/net/"$iface"/speed 2>/dev/null || echo "N/A")
        if [ "$speed" = "-1" ] || [ "$speed" = "N/A" ]; then
            echo "  Speed       : Unknown (not connected or virtual interface)"
        else
            echo "  Speed       : ${speed} Mbps ($(echo "scale=1; $speed / 1000" | bc 2>/dev/null || echo "?") Gbps)"
        fi
        
        duplex=$(cat /sys/class/net/"$iface"/duplex 2>/dev/null || echo "N/A")
        echo "  Duplex      : $duplex"
        
        carrier=$(cat /sys/class/net/"$iface"/carrier 2>/dev/null || echo "0")
        if [ "$carrier" = "1" ]; then
            echo -e "  Carrier     : ${GREEN}Yes${NC}"
        else
            echo -e "  Carrier     : ${RED}No${NC}"
        fi
        
        # Device vendor/device ID
        if [ -e /sys/class/net/"$iface"/device/vendor ]; then
            vendor=$(cat /sys/class/net/"$iface"/device/vendor 2>/dev/null)
            device=$(cat /sys/class/net/"$iface"/device/device 2>/dev/null)
            echo "  PCI Vendor  : $vendor"
            echo "  PCI Device  : $device"
            
            # Try to identify Mellanox/NVIDIA
            if [ "$vendor" = "0x15b3" ]; then
                echo -e "  ${GREEN}✓ NVIDIA/Mellanox device detected${NC}"
            fi
        fi
    done
    
    # Check ethtool if available
    if command_exists ethtool; then
        print_header "ethtool Information"
        echo "$interfaces" | while read -r iface; do
            echo -e "\n${YELLOW}Interface: $iface${NC}"
            ethtool "$iface" 2>/dev/null | grep -E "Speed:|Duplex:|Link detected:|Supported link modes:" || echo "  No ethtool info available"
        done
    else
        print_header "ethtool"
        echo -e "${YELLOW}✗ ethtool not installed${NC}"
        echo "  Install: sudo apt install ethtool (Debian/Ubuntu)"
        echo "          sudo yum install ethtool (RHEL/CentOS)"
    fi
    
    # Check lspci if available
    if command_exists lspci; then
        print_header "PCI Network Devices (lspci)"
        lspci | grep -i "network\|ethernet\|infiniband" || echo "No network devices found"
        
        echo ""
        echo "Mellanox/NVIDIA devices:"
        if lspci | grep -qi "mellanox\|nvidia.*network"; then
            lspci | grep -i "mellanox\|nvidia" | grep -i "network\|infiniband"
        else
            echo "  None found"
        fi
    else
        print_header "lspci"
        echo -e "${YELLOW}✗ lspci not installed${NC}"
        echo "  Install: sudo apt install pciutils (Debian/Ubuntu)"
        echo "          sudo yum install pciutils (RHEL/CentOS)"
    fi
    
    # Check InfiniBand tools
    print_header "InfiniBand Devices"
    if command_exists ibstat; then
        ibstat 2>/dev/null || echo "No IB devices found or access denied"
    elif command_exists ibv_devinfo; then
        ibv_devinfo 2>/dev/null || echo "No IB devices found or access denied"
    else
        echo -e "${YELLOW}✗ InfiniBand tools not installed${NC}"
        echo "  Install: sudo apt install infiniband-diags (Debian/Ubuntu)"
        echo "          sudo yum install infiniband-diags (RHEL/CentOS)"
    fi
    
    # Check Mellanox tools
    print_header "Mellanox/NVIDIA Tools"
    tools_found=0
    
    if command_exists mst; then
        echo -e "${GREEN}✓ mst (Mellanox Software Tools)${NC}"
        tools_found=1
        
        # Try to show MST status
        if mst status 2>/dev/null | grep -q "pciconf"; then
            echo ""
            echo "MST devices:"
            mst status 2>/dev/null | grep "pciconf" | sed 's/^/  /'
        fi
    else
        echo -e "${YELLOW}✗ mst not found${NC}"
    fi
    
    if command_exists mlxlink; then
        echo -e "${GREEN}✓ mlxlink${NC}"
        tools_found=1
    else
        echo -e "${YELLOW}✗ mlxlink not found${NC}"
    fi
    
    if command_exists mlxconfig; then
        echo -e "${GREEN}✓ mlxconfig${NC}"
        tools_found=1
    else
        echo -e "${YELLOW}✗ mlxconfig not found${NC}"
    fi
    
    if [ $tools_found -eq 0 ]; then
        echo ""
        echo "Install Mellanox Firmware Tools (MFT):"
        echo "  https://network.nvidia.com/products/adapter-software/firmware-tools/"
    fi
    
    # Check current traffic
    print_header "Current Traffic Statistics"
    if [ -f /proc/net/dev ]; then
        echo ""
        printf "%-12s %15s %15s %15s %15s\n" "Interface" "RX Bytes" "RX Packets" "TX Bytes" "TX Packets"
        echo "--------------------------------------------------------------------------------"
        
        echo "$interfaces" | while read -r iface; do
            if grep -q "^ *$iface:" /proc/net/dev; then
                stats=$(grep "^ *$iface:" /proc/net/dev | awk '{print $2, $3, $10, $11}')
                read -r rx_bytes rx_pkts tx_bytes tx_pkts <<< "$stats"
                
                # Convert to human readable
                rx_mb=$(echo "scale=2; $rx_bytes / 1024 / 1024" | bc 2>/dev/null || echo "0")
                tx_mb=$(echo "scale=2; $tx_bytes / 1024 / 1024" | bc 2>/dev/null || echo "0")
                
                printf "%-12s %12s MB %15s %12s MB %15s\n" \
                    "$iface" "$rx_mb" "$rx_pkts" "$tx_mb" "$tx_pkts"
            fi
        done
    fi
    
    # Recommendations
    print_header "Recommendations for CX7"
    echo ""
    echo "For NVIDIA ConnectX-7 cards, use these tools for best results:"
    echo ""
    echo -e "  ${GREEN}1. mlxlink${NC} - Most accurate link speed and status"
    echo "     Example: sudo mlxlink -d /dev/mst/mt4125_pciconf0"
    echo ""
    echo -e "  ${GREEN}2. ibstat/ibv_devinfo${NC} - For InfiniBand mode"
    echo "     Example: ibstat"
    echo ""
    echo -e "  ${GREEN}3. ethtool${NC} - For Ethernet mode"
    echo "     Example: ethtool eth0"
    echo ""
    echo -e "  ${GREEN}4. Monitor bandwidth${NC} - Real-time monitoring"
    echo "     Example: python3 /workspace/monitor_bandwidth.py eth0"
    echo ""
    
    # Final summary
    print_header "Summary"
    echo ""
    
    active_count=$(echo "$interfaces" | wc -l)
    up_count=0
    
    echo "$interfaces" | while read -r iface; do
        state=$(cat /sys/class/net/"$iface"/operstate 2>/dev/null || echo "unknown")
        if [ "$state" = "up" ]; then
            up_count=$((up_count + 1))
        fi
    done
    
    echo "  Total interfaces: $active_count"
    echo "  Active interfaces: Run 'cat /sys/class/net/*/operstate | grep -c up' to count"
    echo ""
    echo -e "${GREEN}✓ Check complete!${NC}"
    echo ""
}

# Run main function
main
