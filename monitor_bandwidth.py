#!/usr/bin/env python3
"""
Real-time network bandwidth monitor for Linux.
Particularly useful for monitoring NVIDIA ConnectX-7 (CX7) NICs.
"""

import time
import os
import sys
import argparse


def get_interface_stats(interface):
    """Get current network statistics for an interface."""
    stats = {}
    stats_path = f"/sys/class/net/{interface}/statistics"
    
    if not os.path.exists(stats_path):
        return None
    
    try:
        # Read RX/TX bytes
        with open(f"{stats_path}/rx_bytes", 'r') as f:
            stats['rx_bytes'] = int(f.read().strip())
        with open(f"{stats_path}/tx_bytes", 'r') as f:
            stats['tx_bytes'] = int(f.read().strip())
        
        # Read packets
        with open(f"{stats_path}/rx_packets", 'r') as f:
            stats['rx_packets'] = int(f.read().strip())
        with open(f"{stats_path}/tx_packets", 'r') as f:
            stats['tx_packets'] = int(f.read().strip())
        
        # Read errors
        with open(f"{stats_path}/rx_errors", 'r') as f:
            stats['rx_errors'] = int(f.read().strip())
        with open(f"{stats_path}/tx_errors", 'r') as f:
            stats['tx_errors'] = int(f.read().strip())
        
        # Read drops
        with open(f"{stats_path}/rx_dropped", 'r') as f:
            stats['rx_dropped'] = int(f.read().strip())
        with open(f"{stats_path}/tx_dropped", 'r') as f:
            stats['tx_dropped'] = int(f.read().strip())
        
        return stats
    except Exception as e:
        print(f"Error reading stats: {e}")
        return None


def get_interface_info(interface):
    """Get interface configuration information."""
    info = {}
    iface_path = f"/sys/class/net/{interface}"
    
    try:
        # Speed (Mbps)
        with open(f"{iface_path}/speed", 'r') as f:
            speed = f.read().strip()
            info['speed'] = int(speed) if speed != "-1" else "Unknown"
        
        # MTU
        with open(f"{iface_path}/mtu", 'r') as f:
            info['mtu'] = int(f.read().strip())
        
        # Operational state
        with open(f"{iface_path}/operstate", 'r') as f:
            info['operstate'] = f.read().strip()
        
        # MAC address
        with open(f"{iface_path}/address", 'r') as f:
            info['mac'] = f.read().strip()
        
        return info
    except Exception as e:
        print(f"Error reading interface info: {e}")
        return None


def format_bytes(bytes_val):
    """Format bytes into human readable format."""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_val < 1024.0:
            return f"{bytes_val:7.2f} {unit}"
        bytes_val /= 1024.0
    return f"{bytes_val:7.2f} PB"


def format_rate_gbps(bytes_per_sec):
    """Format rate in Gbps."""
    gbps = bytes_per_sec * 8 / 1e9
    return f"{gbps:8.2f}"


def format_rate_mbps(bytes_per_sec):
    """Format rate in Mbps."""
    mbps = bytes_per_sec * 8 / 1e6
    return f"{mbps:10.2f}"


def print_interface_info(interface):
    """Print interface configuration."""
    info = get_interface_info(interface)
    if info:
        print(f"\n{'='*70}")
        print(f"Interface: {interface}")
        print(f"{'='*70}")
        print(f"  MAC Address    : {info['mac']}")
        print(f"  MTU            : {info['mtu']}")
        print(f"  Operational    : {info['operstate']}")
        
        if isinstance(info['speed'], int):
            print(f"  Link Speed     : {info['speed']} Mbps ({info['speed']/1000:.1f} Gbps)")
        else:
            print(f"  Link Speed     : {info['speed']}")
        print(f"{'='*70}\n")


def monitor_bandwidth(interface, interval=1, unit='gbps', show_packets=False, show_errors=False):
    """
    Monitor bandwidth usage in real-time.
    
    Args:
        interface: Network interface name
        interval: Sampling interval in seconds
        unit: 'gbps' or 'mbps'
        show_packets: Show packet rates
        show_errors: Show errors and drops
    """
    # Print interface info
    print_interface_info(interface)
    
    # Print header
    header = f"{'Time':<12}"
    if unit == 'gbps':
        header += f"{'RX Rate':>12} {'TX Rate':>12} {'Total':>12}"
    else:
        header += f"{'RX Rate':>14} {'TX Rate':>14} {'Total':>14}"
    
    if show_packets:
        header += f"{'RX pps':>12} {'TX pps':>12}"
    
    if show_errors:
        header += f"{'RX Err':>10} {'TX Err':>10}"
    
    print(header)
    print("-" * len(header))
    
    # Get initial stats
    prev_stats = get_interface_stats(interface)
    if prev_stats is None:
        print(f"Error: Cannot read stats for interface {interface}")
        sys.exit(1)
    
    prev_time = time.time()
    
    try:
        while True:
            time.sleep(interval)
            
            # Get current stats
            curr_stats = get_interface_stats(interface)
            curr_time = time.time()
            
            if curr_stats is None:
                continue
            
            # Calculate elapsed time
            elapsed = curr_time - prev_time
            
            # Calculate rates
            rx_bytes_diff = curr_stats['rx_bytes'] - prev_stats['rx_bytes']
            tx_bytes_diff = curr_stats['tx_bytes'] - prev_stats['tx_bytes']
            
            rx_rate = rx_bytes_diff / elapsed
            tx_rate = tx_bytes_diff / elapsed
            total_rate = rx_rate + tx_rate
            
            # Format output
            timestamp = time.strftime("%H:%M:%S")
            output = f"{timestamp:<12}"
            
            if unit == 'gbps':
                output += f"{format_rate_gbps(rx_rate):>12} {format_rate_gbps(tx_rate):>12} {format_rate_gbps(total_rate):>12}"
            else:
                output += f"{format_rate_mbps(rx_rate):>14} {format_rate_mbps(tx_rate):>14} {format_rate_mbps(total_rate):>14}"
            
            # Packet rates
            if show_packets:
                rx_pkts_diff = curr_stats['rx_packets'] - prev_stats['rx_packets']
                tx_pkts_diff = curr_stats['tx_packets'] - prev_stats['tx_packets']
                
                rx_pps = rx_pkts_diff / elapsed
                tx_pps = tx_pkts_diff / elapsed
                
                output += f"{rx_pps:>12.0f} {tx_pps:>12.0f}"
            
            # Errors
            if show_errors:
                rx_errors = curr_stats['rx_errors']
                tx_errors = curr_stats['tx_errors']
                
                output += f"{rx_errors:>10} {tx_errors:>10}"
            
            print(output)
            
            # Update previous stats
            prev_stats = curr_stats
            prev_time = curr_time
            
    except KeyboardInterrupt:
        print("\n\nMonitoring stopped.")
        
        # Print summary
        final_stats = get_interface_stats(interface)
        if final_stats:
            print(f"\n{'='*70}")
            print("Cumulative Statistics:")
            print(f"{'='*70}")
            print(f"  RX Bytes       : {format_bytes(final_stats['rx_bytes'])}")
            print(f"  TX Bytes       : {format_bytes(final_stats['tx_bytes'])}")
            print(f"  RX Packets     : {final_stats['rx_packets']:,}")
            print(f"  TX Packets     : {final_stats['tx_packets']:,}")
            print(f"  RX Errors      : {final_stats['rx_errors']:,}")
            print(f"  TX Errors      : {final_stats['tx_errors']:,}")
            print(f"  RX Dropped     : {final_stats['rx_dropped']:,}")
            print(f"  TX Dropped     : {final_stats['tx_dropped']:,}")
            print(f"{'='*70}")


def list_interfaces():
    """List all available network interfaces."""
    net_path = "/sys/class/net"
    interfaces = []
    
    for iface in os.listdir(net_path):
        if iface != "lo":  # Skip loopback
            info = get_interface_info(iface)
            if info:
                interfaces.append((iface, info))
    
    if not interfaces:
        print("No network interfaces found.")
        return
    
    print("\nAvailable Network Interfaces:")
    print(f"{'='*70}")
    print(f"{'Interface':<12} {'State':<10} {'Speed':<20} {'MAC Address':<20}")
    print(f"{'-'*70}")
    
    for iface, info in interfaces:
        speed_str = f"{info['speed']} Mbps" if isinstance(info['speed'], int) else info['speed']
        print(f"{iface:<12} {info['operstate']:<10} {speed_str:<20} {info['mac']:<20}")
    
    print(f"{'='*70}\n")


def main():
    """Main function with argument parsing."""
    parser = argparse.ArgumentParser(
        description='Real-time network bandwidth monitor for Linux',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Monitor eth0 with default settings (Gbps)
  %(prog)s eth0
  
  # Monitor with 0.5 second interval
  %(prog)s eth0 -i 0.5
  
  # Show rates in Mbps
  %(prog)s eth0 -u mbps
  
  # Show packets and errors
  %(prog)s eth0 -p -e
  
  # List available interfaces
  %(prog)s -l
        """
    )
    
    parser.add_argument('interface', nargs='?', default=None,
                        help='Network interface to monitor (e.g., eth0, ib0)')
    parser.add_argument('-i', '--interval', type=float, default=1.0,
                        help='Sampling interval in seconds (default: 1.0)')
    parser.add_argument('-u', '--unit', choices=['gbps', 'mbps'], default='gbps',
                        help='Rate unit: gbps or mbps (default: gbps)')
    parser.add_argument('-p', '--packets', action='store_true',
                        help='Show packet rates')
    parser.add_argument('-e', '--errors', action='store_true',
                        help='Show errors and drops')
    parser.add_argument('-l', '--list', action='store_true',
                        help='List available network interfaces')
    
    args = parser.parse_args()
    
    # List interfaces if requested
    if args.list:
        list_interfaces()
        return
    
    # Check if interface is provided
    if args.interface is None:
        print("Error: Please specify a network interface or use -l to list available interfaces.")
        parser.print_help()
        sys.exit(1)
    
    # Check if interface exists
    if not os.path.exists(f"/sys/class/net/{args.interface}"):
        print(f"Error: Interface '{args.interface}' not found.")
        print("\nUse -l to list available interfaces.")
        sys.exit(1)
    
    # Start monitoring
    try:
        monitor_bandwidth(
            args.interface,
            interval=args.interval,
            unit=args.unit,
            show_packets=args.packets,
            show_errors=args.errors
        )
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
