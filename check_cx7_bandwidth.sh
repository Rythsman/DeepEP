#!/bin/bash
# Script to check CX7 network card bandwidth information on Linux

echo "=== Checking for CX7/Mellanox Network Cards ==="
echo ""

# Method 1: Check PCI devices
echo "1. PCI Device Information:"
if command -v lspci &> /dev/null; then
    lspci | grep -i -E "mellanox|cx7|network|ethernet"
else
    echo "   lspci not found, trying /sys/bus/pci/devices/"
    find /sys/bus/pci/devices/ -name "uevent" -exec grep -l -i "mellanox\|cx7" {} \; 2>/dev/null | head -5
fi
echo ""

# Method 2: List network interfaces
echo "2. Network Interfaces:"
if command -v ip &> /dev/null; then
    ip link show
elif command -v ifconfig &> /dev/null; then
    ifconfig
else
    ls -la /sys/class/net/
fi
echo ""

# Method 3: Check for Mellanox interfaces (typically named mlx5_* or ib*)
echo "3. Mellanox/InfiniBand Interfaces:"
for iface in /sys/class/net/*; do
    iface_name=$(basename "$iface")
    if [[ "$iface_name" == mlx* ]] || [[ "$iface_name" == ib* ]]; then
        echo "   Found interface: $iface_name"
        if [ -f "$iface/speed" ]; then
            echo "   Speed: $(cat $iface/speed) Mbps"
        fi
        if [ -f "$iface/duplex" ]; then
            echo "   Duplex: $(cat $iface/duplex)"
        fi
    fi
done
echo ""

# Method 4: Use ethtool if available
echo "4. Ethtool Information (if available):"
if command -v ethtool &> /dev/null; then
    for iface in /sys/class/net/*; do
        iface_name=$(basename "$iface")
        if [[ "$iface_name" != "lo" ]] && [[ "$iface_name" != "docker0" ]]; then
            echo "   Interface: $iface_name"
            ethtool "$iface_name" 2>/dev/null | grep -E "Speed|Duplex|Link detected|Supported link modes"
        fi
    done
else
    echo "   ethtool not installed. Install with: sudo apt-get install ethtool"
fi
echo ""

# Method 5: Check sysfs for speed information
echo "5. Speed Information from /sys/class/net/:"
for iface in /sys/class/net/*; do
    iface_name=$(basename "$iface")
    if [[ "$iface_name" != "lo" ]] && [[ "$iface_name" != "docker0" ]]; then
        if [ -f "$iface/speed" ]; then
            speed=$(cat "$iface/speed" 2>/dev/null)
            if [ "$speed" != "-1" ] && [ -n "$speed" ]; then
                echo "   $iface_name: $speed Mbps"
            fi
        fi
        if [ -f "$iface/device/device" ]; then
            device_id=$(cat "$iface/device/device" 2>/dev/null)
            vendor_id=$(cat "$iface/device/vendor" 2>/dev/null)
            echo "   $iface_name: Vendor ID: $vendor_id, Device ID: $device_id"
        fi
    fi
done
echo ""

# Method 6: Check for Mellanox-specific tools
echo "6. Mellanox-Specific Tools:"
if command -v mstflint &> /dev/null; then
    echo "   mstflint found"
    mstflint query 2>/dev/null | head -20
elif command -v mlxconfig &> /dev/null; then
    echo "   mlxconfig found"
    mlxconfig -d /dev/mst/mt* query 2>/dev/null | head -20
else
    echo "   Mellanox tools not found"
    echo "   Install with: sudo apt-get install mstflint"
fi
echo ""

# Method 7: Check InfiniBand information
echo "7. InfiniBand Information (if available):"
if command -v ibstat &> /dev/null; then
    ibstat
elif [ -d "/sys/class/infiniband" ]; then
    echo "   InfiniBand devices found:"
    ls -la /sys/class/infiniband/
    for ib_dev in /sys/class/infiniband/*; do
        dev_name=$(basename "$ib_dev")
        echo "   Device: $dev_name"
        if [ -f "$ib_dev/board_id" ]; then
            echo "     Board ID: $(cat $ib_dev/board_id)"
        fi
        if [ -f "$ib_dev/fw_ver" ]; then
            echo "     Firmware: $(cat $ib_dev/fw_ver)"
        fi
    done
else
    echo "   No InfiniBand devices found"
fi
