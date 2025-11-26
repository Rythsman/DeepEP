# CX7 网卡带宽查询工具集

本工具集提供了在 Linux 系统上查询 NVIDIA ConnectX-7 (CX7) 网卡带宽相关数据的完整解决方案。

## 📋 文件说明

### 1. `check_nic_bandwidth.py`
**完整的网卡信息检测脚本**

- 检查所有可用的网络接口
- 尝试使用多种工具获取带宽信息
- 提供工具安装建议
- 适合首次诊断使用

```bash
python3 check_nic_bandwidth.py
```

### 2. `monitor_bandwidth.py`
**实时带宽监控工具**

功能特性：
- 实时监控网络带宽使用情况
- 支持 Gbps 和 Mbps 单位切换
- 可显示包速率和错误统计
- 支持自定义采样间隔
- 累计统计信息展示

使用示例：
```bash
# 列出所有接口
python3 monitor_bandwidth.py -l

# 监控 eth0（默认 Gbps）
python3 monitor_bandwidth.py eth0

# 使用 Mbps 显示，0.5 秒间隔
python3 monitor_bandwidth.py eth0 -u mbps -i 0.5

# 显示包速率和错误信息
python3 monitor_bandwidth.py eth0 -p -e

# 查看帮助
python3 monitor_bandwidth.py -h
```

输出示例：
```
======================================================================
Interface: eth0
======================================================================
  MAC Address    : 82:2b:38:3d:bc:d0
  MTU            : 1500
  Operational    : up
  Link Speed     : Unknown
======================================================================

Time            RX Rate      TX Rate        Total
------------------------------------------------------------
14:23:45           0.45 Gb/s     0.23 Gb/s     0.68 Gb/s
14:23:46           1.23 Gb/s     0.89 Gb/s     2.12 Gb/s
```

### 3. `quick_check_nic.sh`
**快速检查脚本（Bash）**

- 无需额外依赖即可运行
- 彩色输出，易于阅读
- 检测已安装的工具
- 提供针对性的安装建议

```bash
./quick_check_nic.sh
```

### 4. `CX7_NIC_BANDWIDTH_GUIDE.md`
**完整的操作指南**

包含内容：
- 所有可用的查询命令
- 工具安装方法
- 配置优化建议
- 故障排查步骤
- CX7 规格参考

## 🚀 快速开始

### 第一步：运行快速检查

```bash
# 查看当前系统状态
./quick_check_nic.sh
```

这会告诉你：
- 有哪些网络接口
- 缺少哪些工具
- 如何安装需要的工具

### 第二步：安装必要工具

根据第一步的输出，安装所需工具：

**Debian/Ubuntu:**
```bash
sudo apt update
sudo apt install -y ethtool pciutils iproute2 infiniband-diags libibverbs-dev
```

**RHEL/CentOS:**
```bash
sudo yum install -y ethtool pciutils iproute infiniband-diags libibverbs
```

### 第三步：查询带宽信息

```bash
# 方法 1：使用 ethtool（以太网模式）
ethtool eth0 | grep Speed

# 方法 2：使用 ibstat（InfiniBand 模式）
ibstat

# 方法 3：使用完整检测脚本
python3 check_nic_bandwidth.py

# 方法 4：实时监控
python3 monitor_bandwidth.py eth0
```

## 🔧 常用命令速查

### 查看链路速度

```bash
# 方法 1: 通过 /sys 文件系统
cat /sys/class/net/eth0/speed

# 方法 2: 使用 ethtool
ethtool eth0 | grep Speed

# 方法 3: 使用 mlxlink（最准确，需要 MFT）
sudo mst start
sudo mlxlink -d /dev/mst/mt4125_pciconf0 | grep Speed

# 方法 4: 使用 ibstat（InfiniBand）
ibstat | grep Rate
```

### 查看实时流量

```bash
# 方法 1: 使用本工具
python3 monitor_bandwidth.py eth0

# 方法 2: 使用 iftop（需要安装）
sudo iftop -i eth0

# 方法 3: 使用 nload
nload eth0

# 方法 4: 手动计算
watch -n 1 "cat /proc/net/dev | grep eth0"
```

### 查看硬件信息

```bash
# 查看 PCI 设备
lspci | grep -i mellanox

# 查看详细信息
lspci -vv | grep -A 20 Mellanox

# 查看 PCIe 速度
lspci -vv -s <PCI_ID> | grep -i "lnkcap\|lnksta"
```

## 📊 CX7 网卡规格

### 支持的速率

| 模式 | 最大速率 | 说明 |
|------|---------|------|
| InfiniBand NDR | 400 Gbps | 最新标准 |
| InfiniBand HDR | 200 Gbps | 高性能 |
| InfiniBand EDR | 100 Gbps | 向后兼容 |
| Ethernet | 400GbE | 单端口 |
| Ethernet | 2×200GbE | 双端口 |

### PCIe 接口

- **标准**: PCIe Gen5 x16
- **理论带宽**: 128 GB/s（双向）
- **单向带宽**: 64 GB/s

### 典型用途

- 高性能计算 (HPC)
- AI/ML 训练
- 数据中心互联
- 存储网络 (NVMe-oF)
- GPU Direct RDMA

## 🔍 诊断流程

### 问题：无法检测到网卡

```bash
# 1. 检查 PCI 设备
lspci | grep -i mellanox

# 2. 检查内核模块
lsmod | grep mlx5

# 3. 加载模块
sudo modprobe mlx5_core mlx5_ib

# 4. 检查 dmesg
dmesg | grep -i mlx5
```

### 问题：速率显示为 Unknown

```bash
# 1. 检查链路状态
ip link show eth0

# 2. 检查网线是否连接
cat /sys/class/net/eth0/carrier

# 3. 尝试重新启动接口
sudo ip link set eth0 down
sudo ip link set eth0 up

# 4. 使用 ethtool 查看
sudo ethtool eth0
```

### 问题：性能不达预期

```bash
# 1. 检查 MTU（建议 9000）
ip link show eth0 | grep mtu
sudo ip link set eth0 mtu 9000

# 2. 检查环形缓冲区
ethtool -g eth0
sudo ethtool -G eth0 rx 8192 tx 8192

# 3. 检查 CPU 中断分配
cat /proc/interrupts | grep mlx5

# 4. 运行性能测试
iperf3 -s  # 服务端
iperf3 -c <server_ip> -t 30  # 客户端
```

## 🛠️ 高级工具：Mellanox/NVIDIA 专用

### 安装 Mellanox Firmware Tools (MFT)

```bash
# 下载最新版本
wget https://www.mellanox.com/downloads/MFT/mft-latest-x86_64-deb.tgz

# 解压
tar xzf mft-*.tgz
cd mft-*/

# 安装
sudo ./install.sh

# 启动服务
sudo mst start

# 查看设备
sudo mst status
```

### 使用 mlxlink 查看链路详情

```bash
# 启动 MST
sudo mst start

# 查看所有设备
sudo mst status

# 查看链路信息
sudo mlxlink -d /dev/mst/mt4125_pciconf0

# 查看详细状态
sudo mlxlink -d /dev/mst/mt4125_pciconf0 --json
```

### 使用 mlxconfig 配置网卡

```bash
# 查询当前配置
sudo mlxconfig -d /dev/mst/mt4125_pciconf0 query

# 查看特定参数
sudo mlxconfig -d /dev/mst/mt4125_pciconf0 query | grep LINK_TYPE

# 修改配置（示例：设置为 InfiniBand 模式）
sudo mlxconfig -d /dev/mst/mt4125_pciconf0 set LINK_TYPE_P1=1
```

## 📈 性能监控最佳实践

### 1. 持续监控

```bash
# 使用本工具，带包统计和错误信息
python3 monitor_bandwidth.py eth0 -p -e

# 或使用 watch + cat
watch -n 1 'cat /sys/class/net/eth0/statistics/{rx,tx}_bytes'
```

### 2. 日志记录

```bash
# 记录到文件
python3 monitor_bandwidth.py eth0 | tee -a bandwidth_log_$(date +%Y%m%d).txt

# 使用 sar（需要 sysstat）
sar -n DEV 1 > network_stats.log &
```

### 3. 性能基准测试

```bash
# 使用 iperf3
iperf3 -c <server> -t 60 -P 10  # 10 并行流，60 秒

# 使用 qperf（RDMA）
qperf <server> tcp_bw tcp_lat

# 使用 perftest（InfiniBand）
ib_write_bw -a -d mlx5_0
```

## 🌐 相关资源

- [NVIDIA Networking Documentation](https://docs.nvidia.com/networking/)
- [MLNX_OFED 下载](https://network.nvidia.com/products/infiniband-drivers/linux/mlnx_ofed/)
- [Mellanox Community](https://enterprise-support.nvidia.com/s/)
- [Linux Network Performance Tuning](https://fasterdata.es.net/network-tuning/)

## ❓ FAQ

**Q: CX7 支持的最大带宽是多少？**
A: 单端口最高 400 Gbps (InfiniBand NDR 或 400GbE)。

**Q: 如何确认我的 CX7 工作在哪个模式？**
A: 使用 `ibstat`（IB 模式）或 `ethtool eth0`（以太网模式）。

**Q: 为什么 speed 显示 -1？**
A: 通常是虚拟接口或未连接网线。对于物理接口，安装 ethtool 后使用 `ethtool <iface>` 查看。

**Q: 如何从以太网模式切换到 InfiniBand 模式？**
A: 需要使用 `mlxconfig` 修改固件配置，然后重启系统。

**Q: 实际测试达不到理论带宽怎么办？**
A: 检查 MTU、环形缓冲区、CPU 中断分配、系统调优参数等。参考指南中的性能优化部分。

## 📝 许可证

本工具集遵循项目根目录的 LICENSE 文件。

---

**作者**: Generated for CX7 bandwidth monitoring
**最后更新**: 2025-11-26
