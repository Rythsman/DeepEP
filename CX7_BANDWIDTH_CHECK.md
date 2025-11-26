# CX7 网卡带宽查询指南

本文档介绍如何在Linux系统上查询Mellanox ConnectX-7网卡的带宽相关信息。

## 快速查询方法

### 1. 使用 ethtool（推荐，适用于以太网模式）

```bash
# 查看所有网卡接口
ip link show

# 查看指定网卡的详细信息（包括速度）
ethtool <interface_name>

# 例如：
ethtool eth0
ethtool ib0
```

**输出示例：**
```
Settings for eth0:
    Supported link modes:   40000baseKR4/Full
                            40000baseCR4/Full
                            ...
    Speed: 40000Mb/s
    Duplex: Full
    Link detected: yes
```

### 2. 使用 sysfs 文件系统（最简单，无需额外工具）

```bash
# 查看网卡速度（单位：Mbps）
cat /sys/class/net/<interface_name>/speed

# 查看双工模式
cat /sys/class/net/<interface_name>/duplex

# 查看操作状态
cat /sys/class/net/<interface_name>/operstate

# 列出所有网卡接口
ls /sys/class/net/
```

**示例：**
```bash
# 查看所有网卡的速度
for iface in $(ls /sys/class/net/ | grep -v lo); do
    echo "$iface: $(cat /sys/class/net/$iface/speed 2>/dev/null || echo 'N/A') Mbps"
done
```

### 3. 使用 InfiniBand 工具（适用于IB模式）

```bash
# 查看InfiniBand设备状态
ibstat

# 或使用
ibstatus

# 查看IB设备到网络设备的映射
ibdev2netdev
```

**输出示例：**
```
CA 'mlx5_0'
    CA type: MT4123
    Number of ports: 1
    Firmware version: 24.35.2000
    Hardware version: 0
    Node GUID: 0x...
    System image GUID: 0x...
    Port 1:
        State: Active
        Physical state: LinkUp
        Rate: 400
        Base lid: ...
        LMC: 0
        SM lid: ...
```

### 4. 使用 Mellanox 专用工具 mstconfig

```bash
# 列出所有Mellanox设备
mstconfig -d

# 查询指定设备的配置
mstconfig -d <device> q

# 查询链路速度相关信息
mstconfig -d <device> q | grep -i "link.*speed\|max_link_speed"
```

### 5. 使用 lspci 识别网卡

```bash
# 查找Mellanox设备
lspci | grep -i mellanox

# 查看详细信息
lspci -v | grep -A 10 -i mellanox
```

## CX7 网卡规格

根据Mellanox ConnectX-7的规格：
- **最大带宽**: 400 Gb/s（约50 GB/s）
- **支持模式**: 以太网（Ethernet）和InfiniBand（IB）
- **端口数**: 通常为单端口或双端口

## 实际带宽测试

查询到的速度是**链路协商速度**，实际可用带宽可能受以下因素影响：
- 网络拓扑和交换机配置
- 数据包大小
- 网络拥塞情况
- 应用层协议开销

### 使用 iperf3 测试实际带宽

```bash
# 服务器端
iperf3 -s

# 客户端（在另一台机器上）
iperf3 -c <server_ip> -t 60 -P 4
```

### 使用 qperf 测试 InfiniBand 带宽

```bash
# 服务器端
qperf

# 客户端
qperf <server_ip> tcp_bw udp_bw
```

## 常见问题排查

### 1. 速度显示为 -1 或不可用

可能原因：
- 网卡未正确连接
- 驱动未正确安装
- 网卡处于down状态

解决方法：
```bash
# 检查网卡状态
ip link show <interface>

# 如果down，尝试up
sudo ip link set <interface> up

# 检查驱动
lsmod | grep mlx
```

### 2. 速度低于预期（如显示10000而不是400000）

可能原因：
- 交换机端口速度限制
- 网线/光缆不支持更高速度
- 驱动或固件版本过旧

解决方法：
- 检查交换机配置
- 更新网卡驱动和固件
- 检查物理连接

## 自动化脚本

项目根目录提供了 `check_cx7_bandwidth.sh` 脚本，可以自动执行上述所有检查方法：

```bash
bash check_cx7_bandwidth.sh
```

## 相关资源

- [Mellanox OFED驱动下载](https://www.mellanox.com/products/infiniband-drivers/linux/mlnx_ofed)
- [ethtool手册](https://man7.org/linux/man-pages/man8/ethtool.8.html)
- [InfiniBand诊断工具](https://linux.die.net/man/8/ibstat)
