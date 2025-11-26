# Linux CX7 网卡带宽信息查询指南

本文档介绍如何在Linux系统上查找CX7（ConnectX-7）网卡的带宽相关数据。

## 方法概览

### 1. 使用 ethtool（推荐）

`ethtool` 是最常用的查看网卡信息的工具，包括带宽、双工模式等。

```bash
# 安装 ethtool（如果未安装）
sudo apt-get install ethtool  # Debian/Ubuntu
sudo yum install ethtool      # CentOS/RHEL

# 查看所有网卡接口
ip link show

# 查看特定网卡的详细信息（假设网卡名为 ib0 或 mlx5_0）
ethtool ib0
ethtool mlx5_0

# 查看支持的速率
ethtool ib0 | grep -E "Speed|Supported link modes"

# 查看当前速率和双工模式
ethtool ib0 | grep -E "Speed|Duplex|Link detected"
```

### 2. 通过 sysfs 文件系统

Linux的 `/sys/class/net/` 目录包含了网卡的详细信息。

```bash
# 列出所有网络接口
ls -la /sys/class/net/

# 查看特定网卡的速率（以 ib0 为例）
cat /sys/class/net/ib0/speed        # 速率（Mbps）
cat /sys/class/net/ib0/duplex       # 双工模式
cat /sys/class/net/ib0/operstate    # 操作状态

# 查看网卡的PCI设备信息
cat /sys/class/net/ib0/device/vendor
cat /sys/class/net/ib0/device/device
```

### 3. 使用 lspci 查看PCI设备

```bash
# 安装 pciutils（如果未安装）
sudo apt-get install pciutils

# 查找Mellanox/CX7网卡
lspci | grep -i mellanox

# 查看详细信息
lspci -v | grep -A 20 -i mellanox
```

### 4. InfiniBand 特定工具

对于InfiniBand网卡（CX7通常用于InfiniBand），可以使用专门的工具：

```bash
# 使用 ibstat（如果安装了 InfiniBand 驱动）
ibstat

# 查看特定端口的详细信息
ibstat ib0

# 使用 ibdev2netdev 查看 InfiniBand 设备到网络接口的映射
ibdev2netdev

# 查看 InfiniBand 端口速率
ibstat ib0 | grep -E "Rate|Link layer|State"
```

### 5. Mellanox 专用工具

Mellanox提供了专门的工具来管理网卡：

```bash
# 安装 mstflint（Mellanox Firmware Tools）
sudo apt-get install mstflint

# 查询网卡信息
mstflint query

# 查看特定设备
mstflint -d /dev/mst/mt* query

# 使用 mlxconfig（如果可用）
mlxconfig -d /dev/mst/mt* query
```

### 6. 查看网络统计信息

```bash
# 查看网络接口统计（包括传输的字节数）
cat /proc/net/dev

# 使用 ip 命令查看统计
ip -s link show ib0

# 实时监控网络流量
iftop -i ib0  # 需要安装 iftop
```

## CX7 网卡特性

根据DeepEP项目的README，CX7是InfiniBand 400 Gb/s RDMA网卡，理论最大带宽约为50 GB/s。

### 典型信息示例

- **接口名称**: 通常是 `ib0`, `ib1` 或 `mlx5_0`, `mlx5_1` 等
- **速率**: 400 Gb/s (InfiniBand)
- **协议**: InfiniBand 或 RoCE (RDMA over Converged Ethernet)
- **最大带宽**: ~50 GB/s (实际测试值)

## 快速检查脚本

项目根目录下的 `check_cx7_bandwidth.sh` 脚本会自动执行上述多种方法：

```bash
bash check_cx7_bandwidth.sh
```

该脚本会：
1. 检查PCI设备中的Mellanox网卡
2. 列出所有网络接口
3. 查找Mellanox/InfiniBand接口
4. 使用ethtool查询信息（如果可用）
5. 从sysfs读取速率信息
6. 检查Mellanox专用工具
7. 显示InfiniBand设备信息

## 常见问题

### Q: 为什么看不到CX7网卡？

A: 可能的原因：
- 网卡驱动未安装
- 网卡未正确连接
- 在容器/虚拟机环境中（只能看到虚拟网卡）
- 需要使用 `sudo` 权限

### Q: 如何确认是CX7网卡？

A: 可以通过以下方式确认：
```bash
# 查看PCI设备ID
lspci -nn | grep -i mellanox

# 查看设备ID（CX7的设备ID通常是特定的）
cat /sys/class/net/ib0/device/device
```

### Q: 如何测试实际带宽？

A: 可以使用以下工具测试：
- `iperf3` - 网络性能测试工具
- `ib_write_bw` / `ib_read_bw` - InfiniBand带宽测试工具
- `qperf` - 网络性能基准测试

## 相关资源

- [Mellanox官方文档](https://www.nvidia.com/en-us/networking/products/ethernet-adapters/)
- [InfiniBand驱动文档](https://docs.nvidia.com/networking/)
- DeepEP项目README中提到的CX7性能数据
