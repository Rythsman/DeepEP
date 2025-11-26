# 🚀 快速入门指南 - CX7 网卡带宽查询

本指南帮助你快速开始查询 NVIDIA ConnectX-7 网卡的带宽信息。

## 📦 工具包内容

本工具包包含以下文件：

| 文件名 | 用途 | 类型 |
|--------|------|------|
| `quick_check_nic.sh` | 快速检查网卡状态 | Bash 脚本 |
| `check_nic_bandwidth.py` | 完整的网卡信息检测 | Python 脚本 |
| `monitor_bandwidth.py` | 实时带宽监控 | Python 脚本 |
| `install_tools.sh` | 工具安装脚本 | Bash 脚本 |
| `CX7_NIC_BANDWIDTH_GUIDE.md` | 详细操作指南 | 文档 |
| `README_NIC_BANDWIDTH.md` | 完整说明文档 | 文档 |

## ⚡ 三步快速开始

### 步骤 1: 快速诊断

```bash
cd /workspace
./quick_check_nic.sh
```

这会显示：
- ✅ 当前所有网络接口
- ✅ 接口状态（up/down）
- ✅ 当前流量统计
- ⚠️ 缺少的工具列表

### 步骤 2: 安装工具（可选）

如果步骤 1 显示缺少工具，以 root 权限运行：

```bash
# 需要 root 权限
sudo /workspace/install_tools.sh
```

然后按提示选择：
- 选项 1: 只安装基础工具
- 选项 2: 基础 + InfiniBand 工具
- 选项 3: 基础 + InfiniBand + 监控工具
- **选项 4: 安装所有工具（推荐）**

### 步骤 3: 查看带宽信息

```bash
# 方法 1: 完整检测（推荐首次使用）
python3 check_nic_bandwidth.py

# 方法 2: 实时监控
python3 monitor_bandwidth.py eth0

# 方法 3: 列出所有接口
python3 monitor_bandwidth.py -l
```

## 📋 常用命令示例

### 1. 查看网卡速率

```bash
# 使用系统文件（无需额外工具）
cat /sys/class/net/eth0/speed
# 输出: 200000 (表示 200000 Mbps = 200 Gbps)

# 使用 ethtool（如果已安装）
ethtool eth0 | grep Speed
# 输出: Speed: 200000Mb/s
```

### 2. 实时监控带宽

```bash
# 默认模式（Gbps）
python3 monitor_bandwidth.py eth0

# 使用 Mbps 显示
python3 monitor_bandwidth.py eth0 -u mbps

# 显示包速率和错误
python3 monitor_bandwidth.py eth0 -p -e

# 自定义采样间隔（0.5秒）
python3 monitor_bandwidth.py eth0 -i 0.5
```

**输出示例：**
```
======================================================================
Interface: eth0
======================================================================
  MAC Address    : 82:2b:38:3d:bc:d0
  MTU            : 1500
  Operational    : up
  Link Speed     : 200000 Mbps (200.0 Gbps)
======================================================================

Time            RX Rate      TX Rate        Total
------------------------------------------------------------
14:30:01           2.34 Gb/s     1.56 Gb/s     3.90 Gb/s
14:30:02           5.67 Gb/s     3.21 Gb/s     8.88 Gb/s
14:30:03          12.45 Gb/s     8.90 Gb/s    21.35 Gb/s
...
```

### 3. 查找 CX7 设备

```bash
# 方法 1: 使用 lspci（如果已安装）
lspci | grep -i mellanox

# 方法 2: 检查系统日志
dmesg | grep -i mlx5

# 方法 3: 查看网络接口的 PCI 信息
cat /sys/class/net/eth0/device/vendor
# 输出: 0x15b3 (Mellanox/NVIDIA 的 vendor ID)
```

### 4. 检查 InfiniBand 设备

```bash
# 查看 IB 端口状态
ibstat

# 查看设备详细信息
ibv_devinfo

# 查看速率
ibv_devinfo -d mlx5_0 | grep rate
```

### 5. 使用高级工具（需要 MFT）

```bash
# 启动 MST 服务
sudo mst start

# 查看所有设备
sudo mst status

# 使用 mlxlink 查看链路信息（最准确）
sudo mlxlink -d /dev/mst/mt4125_pciconf0

# 查看配置
sudo mlxconfig -d /dev/mst/mt4125_pciconf0 query
```

## 🔍 不同场景的使用方法

### 场景 1: 我想快速了解网卡状态

```bash
# 运行快速检查脚本
./quick_check_nic.sh
```

### 场景 2: 我想知道当前网卡速率

```bash
# 如果已安装 ethtool
ethtool eth0 | grep Speed

# 或使用我们的脚本
python3 check_nic_bandwidth.py | grep -A 5 "Interface: eth0"
```

### 场景 3: 我想实时监控流量

```bash
# 使用我们的监控工具（推荐）
python3 monitor_bandwidth.py eth0

# 或使用 iftop（如果已安装）
sudo iftop -i eth0
```

### 场景 4: 我想进行性能测试

```bash
# 准备工作：确保两台机器都有 iperf3

# 在服务器端（192.168.1.100）
iperf3 -s

# 在客户端，同时在另一个终端监控带宽
# 终端 1: 监控
python3 monitor_bandwidth.py eth0

# 终端 2: 测试
iperf3 -c 192.168.1.100 -t 60 -P 10
# -t 60: 测试 60 秒
# -P 10: 使用 10 个并行流
```

### 场景 5: 我想诊断性能问题

```bash
# 1. 检查基本信息
python3 check_nic_bandwidth.py

# 2. 检查 MTU（应该是 9000 for jumbo frames）
ip link show eth0 | grep mtu

# 3. 检查错误和丢包
cat /sys/class/net/eth0/statistics/rx_errors
cat /sys/class/net/eth0/statistics/tx_errors
cat /sys/class/net/eth0/statistics/rx_dropped
cat /sys/class/net/eth0/statistics/tx_dropped

# 4. 查看 dmesg 日志
dmesg | grep -i mlx5 | tail -20

# 5. 使用监控工具查看错误
python3 monitor_bandwidth.py eth0 -e
```

## 📊 理解输出结果

### 速率单位转换

- **1 Gbps** = 1,000 Mbps = 125 MB/s
- **10 Gbps** = 10,000 Mbps = 1.25 GB/s
- **100 Gbps** = 100,000 Mbps = 12.5 GB/s
- **200 Gbps** = 200,000 Mbps = 25 GB/s
- **400 Gbps** = 400,000 Mbps = 50 GB/s

### CX7 常见速率

| 配置 | 速率 | 说明 |
|------|------|------|
| InfiniBand NDR | 400 Gbps | 最高性能 |
| InfiniBand HDR | 200 Gbps | 高性能 |
| InfiniBand EDR | 100 Gbps | 标准 |
| 400GbE | 400 Gbps | 以太网模式 |
| 200GbE | 200 Gbps | 以太网模式 |

### 速率显示为 Unknown 或 -1 的原因

1. **虚拟接口** (如 docker0, virbr0)
2. **未连接网线**
3. **网卡未初始化**
4. **需要使用专用工具** (如 ethtool, mlxlink)

解决方法：
```bash
# 检查网线连接
cat /sys/class/net/eth0/carrier
# 1 = 已连接, 0 = 未连接

# 使用 ethtool
sudo ethtool eth0

# 使用 mlxlink（最准确）
sudo mst start
sudo mlxlink -d /dev/mst/mt4125_pciconf0
```

## ⚙️ 性能优化建议

### 1. 设置正确的 MTU

```bash
# CX7 建议使用 9000（Jumbo frames）
sudo ip link set eth0 mtu 9000

# 验证
ip link show eth0 | grep mtu
```

### 2. 优化环形缓冲区

```bash
# 查看当前设置
ethtool -g eth0

# 设置为最大值
sudo ethtool -G eth0 rx 8192 tx 8192
```

### 3. 检查中断分配

```bash
# 查看网卡中断
cat /proc/interrupts | grep mlx5

# 查看 CPU 使用情况
mpstat -P ALL 1
```

## 🆘 常见问题解决

### 问题 1: 找不到 eth0

```bash
# 列出所有接口
ls /sys/class/net/

# 或使用我们的工具
python3 monitor_bandwidth.py -l
```

### 问题 2: 权限不足

```bash
# 使用 sudo 运行
sudo python3 check_nic_bandwidth.py
sudo ethtool eth0
```

### 问题 3: 工具未安装

```bash
# 运行安装脚本
sudo ./install_tools.sh
```

### 问题 4: 性能不达预期

1. 检查 MTU 设置
2. 检查网线质量和连接
3. 检查对端设备配置
4. 运行性能测试工具
5. 查看系统日志

详细故障排查请参考：`CX7_NIC_BANDWIDTH_GUIDE.md`

## 📚 更多信息

- **详细指南**: 阅读 `CX7_NIC_BANDWIDTH_GUIDE.md`
- **完整文档**: 阅读 `README_NIC_BANDWIDTH.md`
- **工具帮助**: 运行 `python3 monitor_bandwidth.py -h`

## 🔗 快速命令参考

```bash
# 快速检查
./quick_check_nic.sh

# 完整检测
python3 check_nic_bandwidth.py

# 列出接口
python3 monitor_bandwidth.py -l

# 监控 eth0
python3 monitor_bandwidth.py eth0

# 监控 eth0（详细模式）
python3 monitor_bandwidth.py eth0 -p -e

# 查看速率
cat /sys/class/net/eth0/speed

# 使用 ethtool
ethtool eth0

# 查看流量统计
cat /proc/net/dev | grep eth0

# 安装工具
sudo ./install_tools.sh
```

## ✅ 检查清单

完成以下步骤以确保正确设置：

- [ ] 运行了 `quick_check_nic.sh`
- [ ] 确认找到了 CX7 网卡
- [ ] 安装了必要的工具
- [ ] 能够查看网卡速率
- [ ] 能够实时监控带宽
- [ ] 理解了输出结果的含义
- [ ] （可选）安装了 MLNX_OFED 驱动
- [ ] （可选）安装了 MFT 工具

---

**需要帮助？** 请查看 `CX7_NIC_BANDWIDTH_GUIDE.md` 获取详细信息和故障排查步骤。

**更新时间**: 2025-11-26
