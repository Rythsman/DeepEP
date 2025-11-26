# NVIDIA ConnectX-7 网卡带宽查询指南

本指南介绍如何在 Linux 系统上查找 NVIDIA ConnectX-7 (CX7) 网卡的带宽相关数据。

## 目录
- [基础命令](#基础命令)
- [安装必要工具](#安装必要工具)
- [查询方法](#查询方法)
- [Python 脚本](#python-脚本)

---

## 基础命令

### 1. 使用 ethtool（以太网模式）

```bash
# 查看网卡速率和双工模式
ethtool eth0

# 查看支持的速率
ethtool eth0 | grep -i speed

# 查看详细统计信息
ethtool -S eth0

# 查看驱动信息
ethtool -i eth0
```

**典型输出示例：**
```
Speed: 200000Mb/s  # CX7 支持最高 400Gbps
Duplex: Full
Link detected: yes
```

### 2. 使用 lspci（查看硬件信息）

```bash
# 查找 Mellanox/NVIDIA 设备
lspci | grep -i mellanox

# 查看详细信息
lspci -vv | grep -A 20 Mellanox

# 查看链路速度和宽度
lspci -vv -s <PCI_ID> | grep -i "lnkcap\|lnksta"
```

**查找 PCIe 带宽：**
```bash
# PCIe Gen5 x16 理论带宽约为 128 GB/s
lspci -vv -s <PCI_ID> | grep "LnkCap:\|LnkSta:"
```

### 3. 使用 InfiniBand 工具

```bash
# 查看 IB 端口状态
ibstat

# 查看设备信息
ibv_devinfo

# 查看端口速率
ibv_devinfo -d mlx5_0 | grep -i rate
```

**CX7 支持的 InfiniBand 速率：**
- NDR (400 Gbps)
- HDR (200 Gbps)
- EDR (100 Gbps)

### 4. 使用 ip 命令

```bash
# 查看所有网络接口
ip link show

# 查看统计信息
ip -s link show eth0

# 持续监控流量
watch -n 1 "ip -s link show eth0"
```

### 5. 使用 /sys 文件系统

```bash
# 查看速率（Mbps）
cat /sys/class/net/eth0/speed

# 查看双工模式
cat /sys/class/net/eth0/duplex

# 查看 MTU
cat /sys/class/net/eth0/mtu

# 查看接口状态
cat /sys/class/net/eth0/operstate

# 查看 PCI vendor/device
cat /sys/class/net/eth0/device/vendor
cat /sys/class/net/eth0/device/device
```

### 6. 使用 Mellanox/NVIDIA 专用工具

```bash
# 启动 MST（Mellanox Software Tools）服务
mst start

# 查看设备
mst status

# 查看链路信息（重要！）
mlxlink -d /dev/mst/mt4125_pciconf0

# 查看配置
mlxconfig -d /dev/mst/mt4125_pciconf0 query

# 查看固件版本
mlxfwmanager --query
```

**mlxlink 输出解析：**
```
Operational Info
-----------------
State                           : Active
Physical state                  : LinkUp
Speed                           : NDR (400 Gb/s)  # 关键信息
Width                           : 4x
FEC                             : RS-FEC (544,514)
Loopback Mode                   : No Loopback
```

---

## 安装必要工具

### Debian/Ubuntu

```bash
# 基础网络工具
sudo apt update
sudo apt install -y ethtool pciutils iproute2 net-tools

# InfiniBand 工具
sudo apt install -y infiniband-diags libibverbs-dev ibverbs-utils

# 性能监控工具
sudo apt install -y iftop nethogs bmon nload
```

### RHEL/CentOS/Rocky Linux

```bash
# 基础网络工具
sudo yum install -y ethtool pciutils iproute net-tools

# InfiniBand 工具
sudo yum install -y infiniband-diags libibverbs ibverbs-utils

# 性能监控工具
sudo yum install -y iftop nethogs bmon nload
```

### MLNX_OFED 驱动（推荐用于 CX7）

```bash
# 下载最新版本
wget https://content.mellanox.com/ofed/MLNX_OFED-latest/MLNX_OFED_LINUX-*-ubuntu22.04-x86_64.tgz

# 解压
tar xzf MLNX_OFED_LINUX-*.tgz
cd MLNX_OFED_LINUX-*/

# 安装
sudo ./mlnxofedinstall --all

# 重启驱动
sudo /etc/init.d/openibd restart
```

### Mellanox Firmware Tools (MFT)

```bash
# 下载
wget https://www.mellanox.com/downloads/MFT/mft-latest-x86_64-deb.tgz

# 解压并安装
tar xzf mft-*.tgz
cd mft-*/
sudo ./install.sh

# 启动服务
sudo mst start
```

---

## 查询方法

### 方法 1：快速查看（推荐）

```bash
#!/bin/bash
# Quick check script

echo "=== Network Interfaces ==="
ip link show | grep -E "^[0-9]+:|state"

echo -e "\n=== Ethernet Speed (ethtool) ==="
for iface in $(ls /sys/class/net/ | grep -v lo); do
    echo "Interface: $iface"
    ethtool $iface 2>/dev/null | grep -E "Speed:|Duplex:|Link detected:" || echo "  ethtool not available or not supported"
done

echo -e "\n=== InfiniBand Devices ==="
ibstat 2>/dev/null || echo "No IB devices or ibstat not installed"

echo -e "\n=== PCI Devices ==="
lspci | grep -i "mellanox\|nvidia" || echo "No Mellanox/NVIDIA devices found"

echo -e "\n=== Current Traffic ==="
cat /proc/net/dev | grep -E "eth|ib" | awk '{print $1, "RX:", $2/1024/1024, "MB", "TX:", $10/1024/1024, "MB"}'
```

### 方法 2：使用 mlxlink（最准确）

```bash
#!/bin/bash
# Check CX7 link speed using mlxlink

# Start MST service
sudo mst start

# Get device list
devices=$(mst status -v | grep "pciconf" | awk '{print $1}')

for dev in $devices; do
    echo "=== Device: $dev ==="
    sudo mlxlink -d $dev | grep -E "Speed|Width|State|FEC"
    echo ""
done
```

### 方法 3：实时带宽监控

```bash
# 使用 iftop（需要 root 权限）
sudo iftop -i eth0

# 使用 nload
nload eth0

# 使用 bmon
bmon -p eth0

# 使用 sar（如果安装了 sysstat）
sar -n DEV 1 10

# 自定义脚本监控
while true; do
    RX1=$(cat /sys/class/net/eth0/statistics/rx_bytes)
    TX1=$(cat /sys/class/net/eth0/statistics/tx_bytes)
    sleep 1
    RX2=$(cat /sys/class/net/eth0/statistics/rx_bytes)
    TX2=$(cat /sys/class/net/eth0/statistics/tx_bytes)
    
    RX_RATE=$(echo "scale=2; ($RX2 - $RX1) * 8 / 1000000000" | bc)
    TX_RATE=$(echo "scale=2; ($TX2 - $TX1) * 8 / 1000000000" | bc)
    
    echo "$(date +%T) - RX: ${RX_RATE} Gbps | TX: ${TX_RATE} Gbps"
done
```

---

## Python 脚本

### 完整的带宽信息收集脚本

已创建在：`/workspace/check_nic_bandwidth.py`

运行方式：
```bash
python3 /workspace/check_nic_bandwidth.py
```

### 实时监控脚本

```python
#!/usr/bin/env python3
"""Real-time network bandwidth monitor for CX7 NICs."""

import time
import os
import sys


def get_bytes(interface):
    """Get current RX/TX bytes for an interface."""
    rx_file = f"/sys/class/net/{interface}/statistics/rx_bytes"
    tx_file = f"/sys/class/net/{interface}/statistics/tx_bytes"
    
    try:
        with open(rx_file, 'r') as f:
            rx = int(f.read().strip())
        with open(tx_file, 'r') as f:
            tx = int(f.read().strip())
        return rx, tx
    except:
        return None, None


def monitor_bandwidth(interface, interval=1):
    """Monitor bandwidth usage in real-time."""
    print(f"Monitoring {interface} (Press Ctrl+C to stop)")
    print(f"{'Time':<12} {'RX Rate':>15} {'TX Rate':>15} {'Total':>15}")
    print("-" * 60)
    
    try:
        while True:
            rx1, tx1 = get_bytes(interface)
            if rx1 is None:
                print(f"Error: Cannot read stats for {interface}")
                sys.exit(1)
            
            time.sleep(interval)
            
            rx2, tx2 = get_bytes(interface)
            
            # Calculate rates in Gbps
            rx_rate = (rx2 - rx1) * 8 / interval / 1e9
            tx_rate = (tx2 - tx1) * 8 / interval / 1e9
            total_rate = rx_rate + tx_rate
            
            timestamp = time.strftime("%H:%M:%S")
            print(f"{timestamp:<12} {rx_rate:>12.2f} Gb/s {tx_rate:>12.2f} Gb/s {total_rate:>12.2f} Gb/s")
            
    except KeyboardInterrupt:
        print("\nMonitoring stopped.")


if __name__ == "__main__":
    interface = sys.argv[1] if len(sys.argv) > 1 else "eth0"
    monitor_bandwidth(interface)
```

保存为 `monitor_bandwidth.py` 并运行：
```bash
python3 monitor_bandwidth.py eth0
```

---

## CX7 规格参考

### ConnectX-7 支持的速率

| 模式 | 速率 | 说明 |
|------|------|------|
| InfiniBand NDR | 400 Gbps | 单端口最高速率 |
| InfiniBand HDR | 200 Gbps | 向后兼容 |
| Ethernet | 400GbE | 单端口以太网 |
| Ethernet | 200GbE | 常用配置 |
| Ethernet | 100GbE | 向后兼容 |

### PCIe 接口

- PCIe Gen5 x16
- 理论带宽：128 GB/s (双向)
- 单向带宽：64 GB/s

### 关键特性

- RDMA (RoCE v2, InfiniBand)
- GPUDirect RDMA
- 硬件加速 (NVME-oF, TLS, IPsec)
- Adaptive Routing
- Congestion Control

---

## 故障排查

### 速率显示为 Unknown 或 -1

```bash
# 检查链路状态
ip link show eth0

# 检查驱动
ethtool -i eth0

# 重新加载驱动
sudo modprobe -r mlx5_core && sudo modprobe mlx5_core

# 检查 dmesg
dmesg | grep -i mlx5
```

### 无法检测到设备

```bash
# 检查 PCI 设备
lspci | grep -i mellanox

# 检查内核模块
lsmod | grep mlx5

# 加载模块
sudo modprobe mlx5_core mlx5_ib
```

### 性能不达预期

```bash
# 检查 MTU（建议 9000 for jumbo frames）
ip link set eth0 mtu 9000

# 检查环形缓冲区大小
ethtool -g eth0
sudo ethtool -G eth0 rx 8192 tx 8192

# 检查中断合并
ethtool -c eth0

# 检查 CPU 亲和性
cat /proc/interrupts | grep mlx5
```

---

## 推荐配置

### 优化网卡性能

```bash
# 1. 设置 MTU 为 9000（巨型帧）
sudo ip link set eth0 mtu 9000

# 2. 禁用 TCP offload（某些场景）
sudo ethtool -K eth0 gro off lro off

# 3. 增加环形缓冲区
sudo ethtool -G eth0 rx 8192 tx 8192

# 4. 设置中断合并
sudo ethtool -C eth0 adaptive-rx off adaptive-tx off rx-usecs 10 tx-usecs 10

# 5. 启用多队列
sudo ethtool -L eth0 combined 16
```

### 系统调优

```bash
# 添加到 /etc/sysctl.conf
net.core.rmem_max = 268435456
net.core.wmem_max = 268435456
net.core.rmem_default = 67108864
net.core.wmem_default = 67108864
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096

# 应用配置
sudo sysctl -p
```

---

## 总结

对于 **NVIDIA ConnectX-7 网卡**，推荐使用以下方法查询带宽：

1. **最简单**：`ethtool eth0`
2. **最准确**：`mlxlink -d /dev/mst/mt4125_pciconf0`（需要安装 MFT）
3. **InfiniBand**：`ibstat` 或 `ibv_devinfo`
4. **实时监控**：`iftop`、`nload` 或自定义 Python 脚本
5. **硬件信息**：`lspci -vv`

### 当前环境检测结果

运行 `check_nic_bandwidth.py` 后发现：
- ✅ 检测到 eth0 接口
- ❌ 缺少必要工具（ethtool, lspci, ibstat 等）
- 建议安装所需工具包以获取完整的带宽信息

### 下一步操作

```bash
# 如果有 sudo 权限，安装必要工具：
sudo apt install -y ethtool pciutils iproute2 infiniband-diags

# 然后再次运行检测脚本
python3 /workspace/check_nic_bandwidth.py
```
