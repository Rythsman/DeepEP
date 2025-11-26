#!/bin/bash
# Script to check CX7 network card bandwidth information on Linux
# This script provides multiple methods to query Mellanox ConnectX-7 bandwidth data

echo "=========================================="
echo "CX7 Network Card Bandwidth Information"
echo "=========================================="
echo ""

# Method 1: Using ethtool (for Ethernet mode)
echo "Method 1: Using ethtool"
echo "----------------------"
if command -v ethtool &> /dev/null; then
    # Find all network interfaces
    for iface in $(ls /sys/class/net/ | grep -v lo | grep -v docker); do
        echo "Interface: $iface"
        ethtool $iface 2>/dev/null | grep -E "Speed|Duplex|Link detected|Supported link modes" || echo "  Not available via ethtool"
        echo ""
    done
else
    echo "ethtool not found. Install with: sudo apt-get install ethtool (Debian/Ubuntu) or sudo yum install ethtool (RHEL/CentOS)"
fi
echo ""

# Method 2: Using sysfs (always available)
echo "Method 2: Using sysfs (/sys/class/net/)"
echo "----------------------------------------"
for iface in $(ls /sys/class/net/ | grep -v lo | grep -v docker); do
    echo "Interface: $iface"
    if [ -f /sys/class/net/$iface/speed ]; then
        speed=$(cat /sys/class/net/$iface/speed 2>/dev/null)
        if [ "$speed" != "-1" ] && [ -n "$speed" ]; then
            echo "  Speed: ${speed} Mbps"
        else
            echo "  Speed: Not available"
        fi
    else
        echo "  Speed: Not available"
    fi
    
    if [ -f /sys/class/net/$iface/duplex ]; then
        duplex=$(cat /sys/class/net/$iface/duplex 2>/dev/null)
        echo "  Duplex: $duplex"
    fi
    
    if [ -f /sys/class/net/$iface/operstate ]; then
        operstate=$(cat /sys/class/net/$iface/operstate 2>/dev/null)
        echo "  Operational State: $operstate"
    fi
    echo ""
done
echo ""

# Method 3: Using lspci to identify Mellanox cards
echo "Method 3: PCI Device Information"
echo "---------------------------------"
if command -v lspci &> /dev/null; then
    echo "Mellanox devices:"
    lspci | grep -i mellanox || echo "  No Mellanox devices found"
    echo ""
    echo "Network controllers:"
    lspci | grep -i "network\|ethernet\|infiniband" || echo "  No network controllers found"
else
    echo "lspci not found. Install with: sudo apt-get install pciutils (Debian/Ubuntu) or sudo yum install pciutils (RHEL/CentOS)"
fi
echo ""

# Method 4: Using InfiniBand tools (for IB mode)
echo "Method 4: Using InfiniBand Tools"
echo "---------------------------------"
if command -v ibstat &> /dev/null; then
    echo "InfiniBand device status:"
    ibstat 2>/dev/null || echo "  ibstat not available"
elif command -v ibstatus &> /dev/null; then
    echo "InfiniBand device status:"
    ibstatus 2>/dev/null || echo "  ibstatus not available"
else
    echo "InfiniBand tools not found. Install with: sudo apt-get install infiniband-diags (Debian/Ubuntu) or sudo yum install infiniband-diags (RHEL/CentOS)"
fi
echo ""

# Method 5: Using mstconfig (Mellanox specific tool)
echo "Method 5: Using mstconfig (Mellanox Tool)"
echo "-----------------------------------------"
if command -v mstconfig &> /dev/null; then
    echo "Mellanox device configuration:"
    for device in $(mstconfig -d 2>/dev/null | grep -o "^[0-9]*:[0-9]*:[0-9]*\.[0-9]*"); do
        echo "Device: $device"
        mstconfig -d $device q 2>/dev/null | grep -i "link_type\|link_width\|max_link_speed\|link_speed" || echo "  Configuration query failed"
        echo ""
    done
else
    echo "mstconfig not found. Install Mellanox OFED drivers to get this tool."
    echo "Download from: https://www.mellanox.com/products/infiniband-drivers/linux/mlnx_ofed"
fi
echo ""

# Method 6: Using ibdev2netdev (if available)
echo "Method 6: Using ibdev2netdev"
echo "-----------------------------"
if command -v ibdev2netdev &> /dev/null; then
    echo "InfiniBand to network device mapping:"
    ibdev2netdev 2>/dev/null || echo "  Not available"
else
    echo "ibdev2netdev not found. Usually comes with InfiniBand drivers."
fi
echo ""

# Method 7: Check /proc/net/dev for statistics
echo "Method 7: Network Statistics (/proc/net/dev)"
echo "---------------------------------------------"
cat /proc/net/dev | head -2
cat /proc/net/dev | grep -v "lo\|docker" | tail -n +3
echo ""

# Method 8: Check dmesg for link speed information
echo "Method 8: Kernel Messages (dmesg)"
echo "----------------------------------"
echo "Recent network link speed messages:"
dmesg | grep -i "link.*speed\|speed.*link\|mellanox" | tail -10 || echo "  No relevant messages found"
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo "For CX7 cards, typical bandwidth specifications:"
echo "  - Ethernet mode: 400 Gb/s (50 GB/s)"
echo "  - InfiniBand mode: 400 Gb/s (50 GB/s)"
echo ""
echo "To get the most accurate information:"
echo "  1. Use 'ethtool <interface>' for Ethernet interfaces"
echo "  2. Use 'ibstat' or 'ibstatus' for InfiniBand interfaces"
echo "  3. Use 'mstconfig' for detailed Mellanox-specific information"
echo "  4. Check /sys/class/net/<interface>/speed for current link speed"
