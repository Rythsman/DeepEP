#!/bin/bash
# Example script demonstrating show_gids usage and GID information

echo "=========================================="
echo "GID Information for Mellanox Cards"
echo "=========================================="
echo ""

# Check if show_gids is available
if command -v show_gids &> /dev/null; then
    echo "Method 1: Using show_gids command"
    echo "-----------------------------------"
    show_gids
    echo ""
    
    # Show detailed information
    if command -v show_gids &> /dev/null; then
        echo "Detailed GID information:"
        show_gids -v 2>/dev/null || show_gids
        echo ""
    fi
else
    echo "show_gids not found. Install with:"
    echo "  Debian/Ubuntu: sudo apt-get install infiniband-diags"
    echo "  RHEL/CentOS:   sudo yum install infiniband-diags"
    echo ""
fi

# Alternative method: Using sysfs
echo "Method 2: Using sysfs (/sys/class/infiniband/)"
echo "-----------------------------------------------"
if [ -d /sys/class/infiniband ]; then
    for device in /sys/class/infiniband/*; do
        device_name=$(basename $device)
        echo "Device: $device_name"
        
        # Check for ports
        for port in $device/ports/*; do
            if [ -d "$port" ]; then
                port_num=$(basename $port)
                echo "  Port $port_num:"
                
                # List GIDs
                if [ -d "$port/gids" ]; then
                    gid_count=0
                    for gid_file in $port/gids/*; do
                        if [ -f "$gid_file" ]; then
                            gid=$(cat $gid_file 2>/dev/null)
                            if [ -n "$gid" ] && [ "$gid" != "0000:0000:0000:0000:0000:0000:0000:0000" ]; then
                                echo "    GID[$gid_count]: $gid"
                                gid_count=$((gid_count + 1))
                            fi
                        fi
                    done
                    if [ $gid_count -eq 0 ]; then
                        echo "    No GIDs configured"
                    fi
                fi
                
                # Show port state
                if [ -f "$port/state" ]; then
                    state=$(cat $port/state 2>/dev/null)
                    echo "    State: $state"
                fi
                
                # Show link layer
                if [ -f "$port/link_layer" ]; then
                    link_layer=$(cat $port/link_layer 2>/dev/null)
                    echo "    Link Layer: $link_layer"
                fi
            fi
        done
        echo ""
    done
else
    echo "No InfiniBand devices found in /sys/class/infiniband/"
    echo ""
fi

# Method 3: Using ibstat (if available)
echo "Method 3: Using ibstat"
echo "----------------------"
if command -v ibstat &> /dev/null; then
    ibstat 2>/dev/null | head -50
    echo ""
elif command -v ibstatus &> /dev/null; then
    ibstatus 2>/dev/null | head -50
    echo ""
else
    echo "ibstat/ibstatus not found"
    echo ""
fi

# Method 4: Using ibdev2netdev (if available)
echo "Method 4: InfiniBand to Network Device Mapping"
echo "-----------------------------------------------"
if command -v ibdev2netdev &> /dev/null; then
    ibdev2netdev
    echo ""
else
    echo "ibdev2netdev not found"
    echo ""
fi

# Summary
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "GID (Global Identifier) is a 128-bit identifier used in InfiniBand networks."
echo ""
echo "Key points:"
echo "  1. Each InfiniBand port can have multiple GIDs"
echo "  2. GID format: <Subnet Prefix (64-bit)>:<GUID (64-bit)>"
echo "  3. GIDs are used for:"
echo "     - Port identification"
echo "     - RDMA connection establishment"
echo "     - Routing and multipath support"
echo "     - Fault tolerance"
echo ""
echo "For Mellanox ConnectX-7 cards:"
echo "  - Each port typically has at least one Link Local GID"
echo "  - Additional GIDs can be configured for multipath"
echo "  - GIDs are essential for NVSHMEM/RDMA communication"
echo ""
echo "See GID_EXPLANATION.md for detailed information."
