#!/usr/bin/env python3
"""
Script to check network interface bandwidth information on Linux.
Particularly useful for NVIDIA ConnectX-7 (CX7) NICs.
"""

import os
import subprocess
import glob
import re


def run_command(cmd):
    """Execute shell command and return output."""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=5
        )
        return result.returncode, result.stdout, result.stderr
    except Exception as e:
        return -1, "", str(e)


def check_sys_class_net():
    """Check network interfaces via /sys/class/net/."""
    print("=" * 60)
    print("Network Interfaces from /sys/class/net/")
    print("=" * 60)
    
    net_path = "/sys/class/net/"
    if not os.path.exists(net_path):
        print("❌ /sys/class/net/ not found")
        return
    
    interfaces = [d for d in os.listdir(net_path) if d != "lo"]
    
    for iface in interfaces:
        print(f"\n📡 Interface: {iface}")
        iface_path = os.path.join(net_path, iface)
        
        # Read basic properties
        properties = ["speed", "duplex", "mtu", "operstate", "carrier", "address"]
        for prop in properties:
            prop_file = os.path.join(iface_path, prop)
            if os.path.exists(prop_file):
                try:
                    with open(prop_file, "r") as f:
                        value = f.read().strip()
                        if prop == "speed" and value == "-1":
                            value = "Unknown (not connected or not supported)"
                        elif prop == "speed" and value != "-1":
                            value = f"{value} Mbps"
                        print(f"  {prop:12s}: {value}")
                except:
                    print(f"  {prop:12s}: Unable to read")
        
        # Check device info
        device_path = os.path.join(iface_path, "device")
        if os.path.exists(device_path):
            for info in ["vendor", "device", "subsystem_vendor", "subsystem_device"]:
                info_file = os.path.join(device_path, info)
                if os.path.exists(info_file):
                    try:
                        with open(info_file, "r") as f:
                            print(f"  {info:12s}: {f.read().strip()}")
                    except:
                        pass


def check_ethtool():
    """Check network bandwidth using ethtool."""
    print("\n" + "=" * 60)
    print("Checking with ethtool")
    print("=" * 60)
    
    ret, stdout, stderr = run_command("which ethtool")
    if ret != 0:
        print("❌ ethtool not installed")
        print("   Install: sudo apt install ethtool  (Debian/Ubuntu)")
        print("           sudo yum install ethtool  (RHEL/CentOS)")
        return
    
    # Get all interfaces except lo
    interfaces = [d for d in os.listdir("/sys/class/net/") if d != "lo"]
    
    for iface in interfaces:
        print(f"\n📡 Interface: {iface}")
        ret, stdout, stderr = run_command(f"ethtool {iface}")
        if ret == 0:
            # Parse relevant information
            for line in stdout.split("\n"):
                line = line.strip()
                if any(keyword in line.lower() for keyword in 
                       ["speed", "duplex", "link detected", "supported link modes"]):
                    print(f"  {line}")
        else:
            print(f"  ❌ Error: {stderr}")


def check_infiniband():
    """Check InfiniBand devices (common for CX7)."""
    print("\n" + "=" * 60)
    print("Checking InfiniBand Devices")
    print("=" * 60)
    
    # Check ibstat
    ret, stdout, stderr = run_command("which ibstat")
    if ret == 0:
        print("\n📊 ibstat output:")
        ret, stdout, stderr = run_command("ibstat")
        if ret == 0:
            print(stdout)
        else:
            print(f"❌ Error running ibstat: {stderr}")
    else:
        print("❌ ibstat not installed (part of infiniband-diags)")
    
    # Check ibv_devinfo
    ret, stdout, stderr = run_command("which ibv_devinfo")
    if ret == 0:
        print("\n📊 ibv_devinfo output:")
        ret, stdout, stderr = run_command("ibv_devinfo")
        if ret == 0:
            print(stdout)
        else:
            print(f"❌ Error running ibv_devinfo: {stderr}")
    else:
        print("❌ ibv_devinfo not installed (part of libibverbs)")


def check_lspci():
    """Check PCI devices for Mellanox/NVIDIA cards."""
    print("\n" + "=" * 60)
    print("Checking PCI Devices (lspci)")
    print("=" * 60)
    
    ret, stdout, stderr = run_command("which lspci")
    if ret != 0:
        print("❌ lspci not installed")
        print("   Install: sudo apt install pciutils  (Debian/Ubuntu)")
        print("           sudo yum install pciutils  (RHEL/CentOS)")
        return
    
    print("\n🔍 Searching for Mellanox/NVIDIA network adapters:")
    ret, stdout, stderr = run_command("lspci | grep -i 'mellanox\\|nvidia'")
    if ret == 0 and stdout:
        print(stdout)
        
        # Get detailed info for each device
        for line in stdout.split("\n"):
            if line.strip():
                pci_id = line.split()[0]
                print(f"\n📋 Detailed info for {pci_id}:")
                ret2, stdout2, stderr2 = run_command(f"lspci -vv -s {pci_id}")
                if ret2 == 0:
                    # Filter for relevant lines
                    for detail_line in stdout2.split("\n"):
                        if any(keyword in detail_line.lower() for keyword in
                               ["speed", "width", "capabilities", "link"]):
                            print(f"  {detail_line.strip()}")
    else:
        print("❌ No Mellanox/NVIDIA devices found")


def check_ip_link():
    """Check network interfaces using ip command."""
    print("\n" + "=" * 60)
    print("Checking with ip link")
    print("=" * 60)
    
    ret, stdout, stderr = run_command("which ip")
    if ret != 0:
        print("❌ ip command not available")
        print("   Install: sudo apt install iproute2  (Debian/Ubuntu)")
        return
    
    ret, stdout, stderr = run_command("ip -s link show")
    if ret == 0:
        print(stdout)
    else:
        print(f"❌ Error: {stderr}")


def check_proc_net_dev():
    """Check /proc/net/dev for network statistics."""
    print("\n" + "=" * 60)
    print("Network Statistics from /proc/net/dev")
    print("=" * 60)
    
    proc_file = "/proc/net/dev"
    if os.path.exists(proc_file):
        with open(proc_file, "r") as f:
            content = f.read()
            print(content)
    else:
        print("❌ /proc/net/dev not found")


def check_mlx_tools():
    """Check for Mellanox/NVIDIA specific tools."""
    print("\n" + "=" * 60)
    print("Checking Mellanox/NVIDIA Specific Tools")
    print("=" * 60)
    
    tools = ["mst", "mlxconfig", "mlxlink", "mlxfwmanager"]
    found_any = False
    
    for tool in tools:
        ret, stdout, stderr = run_command(f"which {tool}")
        if ret == 0:
            print(f"✅ {tool} found at: {stdout.strip()}")
            found_any = True
        else:
            print(f"❌ {tool} not installed")
    
    if not found_any:
        print("\n💡 To install Mellanox/NVIDIA tools:")
        print("   Download MLNX_OFED from: https://network.nvidia.com/products/infiniband-drivers/linux/mlnx_ofed/")
        print("   Or Mellanox Firmware Tools (MFT) from: https://network.nvidia.com/products/adapter-software/firmware-tools/")


def main():
    """Main function to run all checks."""
    print("🔍 Network Interface Bandwidth Information Check")
    print("=" * 60)
    
    # Run all checks
    check_sys_class_net()
    check_ip_link()
    check_proc_net_dev()
    check_ethtool()
    check_lspci()
    check_infiniband()
    check_mlx_tools()
    
    print("\n" + "=" * 60)
    print("✅ Check complete!")
    print("=" * 60)


if __name__ == "__main__":
    main()
