# DeepEP SM数量控制与多机Dispatch/Combine流程详解

## 1. SM数量控制的实现

### 1.1 Python层设置

**位置**: `deep_ep/buffer.py`

```python
class Buffer:
    num_sms: int = 20  # 默认值，类静态变量
    
    @staticmethod
    def set_num_sms(new_num_sms: int) -> None:
        """
        Set the number of SMs to use in high-throughput kernels.
        
        Arguments:
            new_num_sms: the new number to be set.
        """
        assert new_num_sms % 2 == 0, 'The SM count must be even'
        Buffer.num_sms = new_num_sms
```

**关键点**:
- `num_sms`是类静态变量，所有Buffer实例共享
- 必须是偶数（因为通道化设计，每个通道需要2个SM）
- 通过`Buffer.set_num_sms()`全局设置

### 1.2 Config类传递

**位置**: `deep_ep/buffer.py`

```python
class Config:
    def __init__(self, num_sms, ...):
        self.num_sms = num_sms
        
# 使用示例
config = deep_ep.Config(Buffer.num_sms, ...)
```

Config对象在调用dispatch/combine时传入，将SM数量传递给C++层。

### 1.3 CUDA Kernel启动配置

**位置**: `csrc/kernels/launch.cuh`

#### SM90架构（Hopper, H800等）

```cpp
#ifndef DISABLE_SM90_FEATURES
#define SETUP_LAUNCH_CONFIG(num_sms, num_threads, stream)                       \
    cudaLaunchConfig_t cfg = {(num_sms), (num_threads), 0, stream, nullptr, 0}; \
    cudaLaunchAttribute attr[2];                                                \
    attr[0].id = cudaLaunchAttributeCooperative;                                \
    attr[0].val.cooperative = 1;                                                \
    attr[1].id = cudaLaunchAttributeClusterDimension;                           \
    attr[1].val.clusterDim.x = (num_sms % 2 == 0 ? 2 : 1);                      \
    attr[1].val.clusterDim.y = 1;                                               \
    attr[1].val.clusterDim.z = 1;                                               \
    cfg.attrs = attr;                                                           \
    cfg.numAttrs = 2
```

**关键点**:
- 使用`cudaLaunchConfig_t`结构体配置kernel启动
- `cfg.gridDim.x = num_sms`：直接设置grid维度为SM数量
- `clusterDim.x = 2`：如果SM数量是偶数，使用cluster维度为2（用于TMA优化）
- 使用`cudaLaunchKernelEx`启动kernel

#### SM80架构（Ampere, A100等）

```cpp
#else
#define SETUP_LAUNCH_CONFIG(sms, threads, stream) \
    int __num_sms = (sms);                        \
    int __num_threads = (threads);                \
    auto __stream = (stream)
#endif
```

```cpp
#define LAUNCH_KERNEL(config, kernel, ...)                                                 \
    do {                                                                                   \
        kernel<<<__num_sms, __num_threads, 0, __stream>>>(__VA_ARGS__);                    \
        cudaError_t e = cudaGetLastError();                                                \
        if (e != cudaSuccess) {                                                            \
            EPException cuda_exception("CUDA", __FILE__, __LINE__, cudaGetErrorString(e)); \
            fprintf(stderr, "%s\n", cuda_exception.what());                                \
            throw cuda_exception;                                                          \
        }                                                                                  \
    } while (0)
```

**关键点**:
- 使用传统的`<<<gridDim, blockDim>>>`语法
- `gridDim.x = __num_sms`：直接设置为SM数量

### 1.4 Kernel内部使用

**位置**: `csrc/kernels/intranode.cu`, `csrc/kernels/internode.cu`

```cpp
// 示例：intranode dispatch kernel启动
void notify_dispatch(..., int num_channels) {
    constexpr int kNumThreads = 128;
    SETUP_LAUNCH_CONFIG(1 + num_ranks, kNumThreads, stream);
    // num_channels = num_sms / 2
    // 实际启动的block数量 = 1 + num_ranks
}

// 示例：dispatch kernel启动
void dispatch(..., const Config& config) {
    int num_channels = config.num_sms / 2;  // 通道数 = SM数 / 2
    SETUP_LAUNCH_CONFIG(num_channels * 2, kNumThreads, stream);
    // 启动 num_channels * 2 = num_sms 个blocks
}
```

**关键点**:
- 每个SM对应一个CUDA block
- `num_channels = num_sms / 2`：通道化设计，每个通道需要2个SM（一个用于发送，一个用于接收）
- Kernel内部通过`blockIdx.x`获取当前SM ID

### 1.5 完整调用链

```
Python: Buffer.set_num_sms(24)
    ↓
Python: config = Config(Buffer.num_sms, ...)  # num_sms = 24
    ↓
Python: buffer.dispatch(..., config=config)
    ↓
C++: Buffer::intranode_dispatch(..., config)
    ↓
C++: intranode::dispatch(..., config.num_sms)
    ↓
C++: SETUP_LAUNCH_CONFIG(num_channels * 2, ...)  # num_channels * 2 = 24
    ↓
CUDA: cudaLaunchKernelEx(&cfg, kernel, ...)  # gridDim.x = 24
    ↓
GPU: 24个blocks并行执行，每个block在一个SM上运行
```

## 2. 多机Dispatch和Combine完整流程

### 2.1 测试用例概览

**文件**: `tests/test_internode.py`

**测试场景**:
- 多节点（num_nodes > 1）
- 每节点8个GPU（num_local_ranks = 8）
- 总rank数 = num_nodes * 8
- 使用RDMA进行节点间通信，NVLink进行节点内通信

### 2.2 初始化阶段

```python
# 1. 初始化分布式环境
rank, num_ranks, group = init_dist(local_rank, num_local_ranks)

# 2. 创建Buffer
buffer = deep_ep.Buffer(
    group,
    int(2e9),      # num_nvl_bytes: NVLink buffer大小
    int(1e9),      # num_rdma_bytes: RDMA buffer大小
    low_latency_mode=False,
    num_qps_per_rank=num_qps_per_rank,
    explicitly_destroy=True
)

# 3. Buffer内部初始化（C++层）
# - 分配NVLink共享内存（IPC）
# - 初始化NVSHMEM（RDMA）
# - 创建通信stream
# - 分配host端计数器（用于CPU-GPU同步）
```

### 2.3 数据准备阶段

```python
# 1. 准备输入数据
num_tokens = 4096
hidden = 7168
x = torch.ones((num_tokens, hidden), dtype=torch.bfloat16, device='cuda') * rank

# 2. 计算top-k专家选择
scores = torch.randn((num_tokens, num_experts), dtype=torch.float32, device='cuda')
topk_idx = torch.topk(scores, k=num_topk, dim=-1)[1]  # [num_tokens, num_topk]
topk_weights = torch.ones((num_tokens, num_topk), dtype=torch.float32, device='cuda')

# 3. 计算路由信息
rank_idx = topk_idx // (num_experts // num_ranks)  # 每个token应该发送到哪个rank
rdma_rank_idx = rank_idx // num_local_ranks        # 每个token应该发送到哪个RDMA rank（节点）
```

### 2.4 Layout计算阶段

```python
# 调用get_dispatch_layout计算通信布局
num_tokens_per_rank, num_tokens_per_rdma_rank, num_tokens_per_expert, is_token_in_rank, _ = \
    buffer.get_dispatch_layout(topk_idx, num_experts)
```

**C++实现**: `csrc/kernels/layout.cu`

```cpp
// Kernel: get_dispatch_layout
// 1. 计算每个rank接收的token数量
// 2. 计算每个RDMA rank接收的token数量
// 3. 计算每个expert接收的token数量
// 4. 计算is_token_in_rank矩阵 [num_tokens, num_ranks]

// 启动配置
int num_sms = ((num_experts + kNumExpertsPerSM - 1) / kNumExpertsPerSM) + 
              (num_ranks + kNumRanksPerSM - 1) / kNumRanksPerSM;
SETUP_LAUNCH_CONFIG(num_sms, kNumThreads, stream);
```

**输出**:
- `num_tokens_per_rank`: [num_ranks] - 每个rank接收的token数
- `num_tokens_per_rdma_rank`: [num_rdma_ranks] - 每个RDMA rank接收的token数
- `num_tokens_per_expert`: [num_experts] - 每个expert接收的token数
- `is_token_in_rank`: [num_tokens, num_ranks] - token到rank的映射矩阵

### 2.5 Dispatch阶段 - Notify（元数据同步）

**Python调用**:
```python
recv_x, recv_topk_idx, recv_topk_weights, recv_num_tokens_per_expert_list, handle, event = \
    buffer.dispatch(
        x=x,
        topk_idx=topk_idx,
        topk_weights=topk_weights,
        num_tokens_per_rank=num_tokens_per_rank,
        num_tokens_per_rdma_rank=num_tokens_per_rdma_rank,
        is_token_in_rank=is_token_in_rank,
        num_tokens_per_expert=num_tokens_per_expert,
        config=config
    )
```

**C++实现**: `csrc/kernels/internode.cu` - `notify_dispatch`

#### 2.5.1 Notify Kernel执行流程

```cpp
template <bool kLowLatencyMode, int kNumRDMARanks>
__global__ void notify_dispatch(...) {
    auto sm_id = blockIdx.x;
    auto rdma_rank = rank / NUM_MAX_NVL_PEERS;
    auto nvl_rank = rank % NUM_MAX_NVL_PEERS;
    
    if (sm_id == 0) {
        // SM 0: 协调节点
        
        // Step 1: 等待所有in-flight的RDMA操作完成
        for (int i = thread_id; i < qps_per_rdma_rank * (kNumRDMARanks - 1); i += num_threads) {
            auto dst_rdma_rank = (i / qps_per_rdma_rank + rdma_rank + 1) % kNumRDMARanks;
            nvshmemi_ibgda_quiet(dst_rdma_rank, qp_id);
        }
        __syncthreads();
        
        // Step 2: RDMA barrier（节点间同步）
        if (thread_id == 32)
            nvshmem_sync(rdma_team);
        
        // Step 3: NVLink barrier（节点内同步）
        barrier_block<NUM_MAX_NVL_PEERS>(barrier_signal_ptrs, nvl_rank);
        
        // Step 4: 清理RDMA buffer
        for (int i = thread_id; i < rdma_num_int_clean; i += num_threads)
            rdma_buffer_ptr_int[rdma_clean_offset + i] = 0;
        
        // Step 5: 将token数量信息复制到RDMA发送buffer
        // - num_tokens_per_rank: [num_ranks]
        // - num_tokens_per_expert: [num_experts]
        // - num_tokens_per_rdma_rank: [num_rdma_ranks]
        for (int i = thread_id; i < num_ranks; i += num_threads)
            rdma_recv_num_tokens_mixed.send_buffer(i / NUM_MAX_NVL_PEERS)[i % NUM_MAX_NVL_PEERS] = 
                num_tokens_per_rank[i];
        
        // Step 6: 通过RDMA发送元数据到其他节点
        for (int i = warp_id; i < kNumRDMARanks; i += num_warps) {
            if (i != rdma_rank) {
                nvshmemi_ibgda_put_nbi_warp(
                    recv_buffer_addr,
                    send_buffer_addr,
                    size,
                    dst_rdma_rank,
                    qp_id
                );
            }
        }
        __syncthreads();
        
        // Step 7: 等待RDMA发送完成
        for (int i = thread_id; i < kNumRDMARanks; i += num_threads) {
            if (i != rdma_rank)
                nvshmemi_ibgda_quiet(dst_rdma_rank, 0);
        }
        __syncthreads();
        
        // Step 8: RDMA barrier，确保所有节点都收到元数据
        if (thread_id == 0)
            nvshmem_sync(rdma_team);
        __syncthreads();
        
        // Step 9: 从RDMA buffer读取其他节点发送的元数据
        // 计算prefix sum，确定每个rank接收的token数量
        // 更新moe_recv_counter（CPU可见的计数器）
        *moe_recv_counter_mapped = total_recv_tokens;
        
        // Step 10: NVLink barrier
        barrier_block<NUM_MAX_NVL_PEERS>(barrier_signal_ptrs, nvl_rank);
        
    } else if (sm_id <= num_rdma_ranks) {
        // SM 1-N: 计算channel prefix matrix
        // 用于后续数据发送的负载均衡
        int dst_rdma_rank = sm_id - 1;
        for (int channel_id = warp_id; channel_id < num_channels; channel_id += num_warps) {
            // 计算每个channel需要发送到dst_rdma_rank的token数量
            int count = 0;
            for (int i = token_start_idx + lane_id; i < token_end_idx; i += 32)
                count += is_token_in_rank[i * num_ranks + dst_rank];
            count = warp_reduce_sum(count);
            if (elect_one_sync())
                rdma_channel_prefix_matrix[dst_rdma_rank * num_channels + channel_id] = count;
        }
        // 计算prefix sum
        if (thread_id == 0) {
            for (int i = 1; i < num_channels; ++i)
                rdma_channel_prefix_matrix[dst_rdma_rank * num_channels + i] += 
                    rdma_channel_prefix_matrix[dst_rdma_rank * num_channels + i - 1];
        }
    }
}
```

**关键点**:
- SM 0负责协调和RDMA通信
- SM 1-N负责计算channel prefix matrix
- 使用RDMA barrier确保所有节点同步
- CPU通过`moe_recv_counter`等待GPU完成元数据计算

#### 2.5.2 CPU等待GPU完成

**C++实现**: `csrc/deep_ep.cpp` - `Buffer::internode_dispatch`

```cpp
// CPU busy-wait等待GPU完成元数据计算
auto start_time = std::chrono::high_resolution_clock::now();
while (true) {
    num_recv_tokens = static_cast<int>(*moe_recv_counter);
    num_rdma_recv_tokens = static_cast<int>(*moe_recv_rdma_counter);
    
    bool ready = (num_recv_tokens >= 0) and (num_rdma_recv_tokens >= 0);
    for (int i = 0; i < num_local_experts and ready; ++i)
        ready &= moe_recv_expert_counter[i] >= 0;
    
    if (ready)
        break;
    
    // 超时检查
    if (timeout)
        throw std::runtime_error("DeepEP error: timeout");
}
```

### 2.6 Dispatch阶段 - 数据发送

**C++实现**: `csrc/kernels/internode.cu` - `dispatch`

#### 2.6.1 Kernel结构

```cpp
template <bool kLowLatencyMode, int kNumRDMARanks, ...>
__global__ void dispatch(...) {
    const auto sm_id = blockIdx.x;
    const auto num_channels = num_sms / 2;
    const auto channel_id = sm_id / 2;
    const bool is_forwarder = sm_id % 2 == 0;  // 偶数SM是forwarder
    
    enum class WarpRole { 
        kRDMASender,           // RDMA发送warp
        kRDMASenderCoordinator, // RDMA发送协调warp
        kRDMAAndNVLForwarder,   // RDMA到NVLink转发warp
        kForwarderCoordinator,   // 转发协调warp
        kNVLReceivers           // NVLink接收warp
    };
    
    // 根据SM ID和warp ID分配角色
    if (is_forwarder) {
        if (warp_id < NUM_MAX_NVL_PEERS) {
            role = WarpRole::kRDMAAndNVLForwarder;
            target_nvl_rank = (warp_id + channel_id) % NUM_MAX_NVL_PEERS;
        } else {
            role = WarpRole::kForwarderCoordinator;
        }
    } else {
        if (warp_id < kNumDispatchRDMASenderWarps) {
            role = WarpRole::kRDMASender;
        } else if (warp_id == kNumDispatchRDMASenderWarps) {
            role = WarpRole::kRDMASenderCoordinator;
        } else {
            role = WarpRole::kNVLReceivers;
            target_nvl_rank = (warp_id + channel_id - kNumDispatchRDMASenderWarps) % NUM_MAX_NVL_PEERS;
        }
    }
}
```

#### 2.6.2 RDMA发送流程（奇数SM）

```cpp
if (warp_role == WarpRole::kRDMASender) {
    // 1. 从输入tensor读取token数据
    // 2. 根据is_token_in_rank判断token应该发送到哪个RDMA rank
    // 3. 将token打包到RDMA buffer
    // 4. 使用nvshmemi_ibgda_put_nbi发送数据
    
    for (int token_idx = token_start_idx; token_idx < token_end_idx; ++token_idx) {
        if (is_token_in_rank[token_idx * num_ranks + dst_rdma_rank]) {
            // 计算在RDMA buffer中的位置
            int buffer_offset = rdma_channel_prefix_matrix[dst_rdma_rank * num_channels + channel_id];
            
            // 复制token数据到RDMA buffer
            copy_token_to_rdma_buffer(
                rdma_buffer_ptr + buffer_offset,
                x + token_idx * hidden,
                hidden
            );
            
            // 发送RDMA数据
            nvshmemi_ibgda_put_nbi_warp(
                remote_recv_buffer_addr,
                local_send_buffer_addr,
                token_size,
                dst_rdma_rank,
                qp_id
            );
        }
    }
}
```

#### 2.6.3 RDMA到NVLink转发流程（偶数SM）

```cpp
if (warp_role == WarpRole::kRDMAAndNVLForwarder) {
    // 1. 从RDMA buffer接收数据
    // 2. 转发到目标NVLink rank（节点内的其他GPU）
    
    // 等待RDMA数据到达
    wait_for_rdma_data(rdma_buffer_ptr, channel_id);
    
    // 从RDMA buffer读取数据
    read_token_from_rdma_buffer(rdma_buffer_ptr, token_data, hidden);
    
    // 转发到NVLink buffer
    copy_token_to_nvl_buffer(
        nvl_buffer_ptr + nvl_offset,
        token_data,
        hidden
    );
    
    // 更新NVLink队列头指针
    atomic_add(&nvl_queue_head[target_nvl_rank][channel_id], 1);
}
```

#### 2.6.4 NVLink接收流程（奇数SM的后半部分warp）

```cpp
if (warp_role == WarpRole::kNVLReceivers) {
    // 1. 从NVLink buffer接收数据
    // 2. 写入到最终的recv_x tensor
    
    // 等待NVLink数据到达
    wait_for_nvl_data(nvl_buffer_ptr, target_nvl_rank, channel_id);
    
    // 从NVLink buffer读取数据
    read_token_from_nvl_buffer(nvl_buffer_ptr, token_data, hidden);
    
    // 写入到recv_x
    copy_token_to_output(
        recv_x + recv_offset,
        token_data,
        hidden
    );
}
```

### 2.7 Combine阶段 - Notify（元数据同步）

**Python调用**:
```python
combined_x, combined_topk_weights, event = buffer.combine(
    x=recv_x,
    handle=handle,
    topk_weights=recv_topk_weights,
    bias=(bias_0, bias_1),
    config=config
)
```

**C++实现**: `csrc/kernels/internode.cu` - `cached_notify` (combine版本)

```cpp
template <bool kLowLatencyMode, int kNumTMABytesPerWarp>
__global__ void cached_notify(...) {
    if (sm_id == 0) {
        // Step 1: 等待所有in-flight RDMA操作
        // Step 2: RDMA barrier
        // Step 3: NVLink barrier
        // Step 4: 清理RDMA和NVLink buffer
        // Step 5: 再次barrier
    } else if (sm_id == 1) {
        // 计算combined_rdma_head（反向遍历）
        // 确定每个token在combine后应该发送到哪个RDMA rank
    }
}
```

### 2.8 Combine阶段 - 数据聚合

**C++实现**: `csrc/kernels/internode.cu` - `combine`

#### 2.8.1 Kernel结构

```cpp
template <bool kLowLatencyMode, int kNumRDMARanks, ...>
__global__ void combine(...) {
    const auto sm_id = blockIdx.x;
    const auto num_channels = num_sms / 2;
    const auto channel_id = sm_id / 2;
    const bool is_forwarder = sm_id % 2 == 0;
    
    enum class WarpRole {
        kNVLSender,           // NVLink发送warp
        kNVLSenderCoordinator, // NVLink发送协调warp
        kNVLAndRDMAForwarder, // NVLink到RDMA转发warp
        kForwarderCoordinator, // 转发协调warp
        kRDMAReceivers        // RDMA接收warp
    };
}
```

#### 2.8.2 NVLink发送流程（奇数SM）

```cpp
if (warp_role == WarpRole::kNVLSender) {
    // 1. 从recv_x读取token数据
    // 2. 根据src_meta确定token应该发送到哪个NVLink rank
    // 3. 发送到NVLink buffer
    
    for (int token_idx = token_start_idx; token_idx < token_end_idx; ++token_idx) {
        SourceMeta meta = recv_src_meta[token_idx];
        
        // 确定目标NVLink rank
        for (int nvl_rank = 0; nvl_rank < NUM_MAX_NVL_PEERS; ++nvl_rank) {
            if (meta.is_token_in_nvl_rank(nvl_rank)) {
                // 计算在NVLink buffer中的位置
                int buffer_offset = nvl_channel_prefix_matrix[nvl_rank * num_channels + channel_id];
                
                // 复制token数据到NVLink buffer
                copy_token_to_nvl_buffer(
                    nvl_buffer_ptr + buffer_offset,
                    recv_x + token_idx * hidden,
                    hidden
                );
                
                // 更新队列头指针
                atomic_add(&nvl_queue_head[nvl_rank][channel_id], 1);
            }
        }
    }
}
```

#### 2.8.3 NVLink到RDMA转发流程（偶数SM）

```cpp
if (warp_role == WarpRole::kNVLAndRDMAForwarder) {
    // 1. 从NVLink buffer接收数据
    // 2. 聚合来自不同NVLink rank的数据
    // 3. 转发到RDMA buffer
    
    // 等待NVLink数据到达
    wait_for_nvl_data(nvl_buffer_ptr, src_nvl_rank, channel_id);
    
    // 从NVLink buffer读取数据
    read_token_from_nvl_buffer(nvl_buffer_ptr, token_data, hidden);
    
    // 聚合数据（累加）
    if (topk_weights) {
        aggregated_data = token_data * topk_weights[token_idx];
    } else {
        aggregated_data += token_data;
    }
    
    // 转发到RDMA buffer
    copy_token_to_rdma_buffer(
        rdma_buffer_ptr + rdma_offset,
        aggregated_data,
        hidden
    );
}
```

#### 2.8.4 RDMA接收和最终聚合（偶数SM的后半部分warp）

```cpp
if (warp_role == WarpRole::kRDMAReceivers) {
    // 1. 从RDMA buffer接收数据
    // 2. 聚合来自不同节点的数据
    // 3. 写入到最终的combined_x tensor
    
    // 等待RDMA数据到达
    wait_for_rdma_data(rdma_buffer_ptr, dst_rdma_rank, channel_id);
    
    // 从RDMA buffer读取数据
    read_token_from_rdma_buffer(rdma_buffer_ptr, token_data, hidden);
    
    // 聚合数据
    combined_data += token_data;
    
    // 应用bias
    if (bias_0) combined_data += bias_0[token_idx];
    if (bias_1) combined_data += bias_1[token_idx];
    
    // 写入到combined_x
    copy_token_to_output(
        combined_x + combined_offset,
        combined_data,
        hidden
    );
}
```

### 2.9 完整数据流图

```
Dispatch阶段:
┌─────────────┐
│  Input x    │ [num_tokens, hidden]
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│  RDMA Sender    │ (奇数SM, 前半warp)
│  - 读取token    │
│  - RDMA发送     │
└──────┬──────────┘
       │ RDMA网络
       ▼
┌─────────────────┐
│ RDMA Forwarder  │ (偶数SM)
│ - RDMA接收      │
│ - NVLink转发    │
└──────┬──────────┘
       │ NVLink
       ▼
┌─────────────────┐
│  NVL Receiver   │ (奇数SM, 后半warp)
│  - NVLink接收   │
│  - 写入recv_x   │
└──────┬──────────┘
       │
       ▼
┌─────────────┐
│   recv_x    │ [num_recv_tokens, hidden]
└─────────────┘

Combine阶段:
┌─────────────┐
│   recv_x    │ [num_recv_tokens, hidden]
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│  NVL Sender     │ (奇数SM, 前半warp)
│  - 读取token    │
│  - NVLink发送   │
└──────┬──────────┘
       │ NVLink
       ▼
┌─────────────────┐
│ NVL Forwarder   │ (偶数SM)
│ - NVLink接收    │
│ - 聚合数据      │
│ - RDMA转发      │
└──────┬──────────┘
       │ RDMA网络
       ▼
┌─────────────────┐
│ RDMA Receiver   │ (偶数SM, 后半warp)
│ - RDMA接收      │
│ - 最终聚合      │
│ - 写入combined_x│
└──────┬──────────┘
       │
       ▼
┌─────────────┐
│ combined_x  │ [num_combined_tokens, hidden]
└─────────────┘
```

### 2.10 关键优化点

1. **通道化设计**: 每个通道使用2个SM（一个forwarder，一个sender/receiver），实现流水线并行
2. **异步通信**: 使用RDMA和NVLink的异步API，实现通信-计算重叠
3. **负载均衡**: 通过channel prefix matrix将token均匀分配到不同通道
4. **零拷贝**: 尽可能减少数据拷贝，直接在buffer间传递指针
5. **SM资源控制**: 通过`set_num_sms`控制使用的SM数量，为计算留出资源

### 2.11 性能指标

根据README，在H800 + CX7 InfiniBand 400 Gb/s环境下：

**Dispatch性能**:
- 16 EP: 43 GB/s (RDMA瓶颈)
- 32 EP: 58 GB/s (RDMA瓶颈)
- 64 EP: 51 GB/s (RDMA瓶颈)

**Combine性能**:
- 16 EP: 43 GB/s (RDMA瓶颈)
- 32 EP: 57 GB/s (RDMA瓶颈)
- 64 EP: 50 GB/s (RDMA瓶颈)

RDMA带宽成为瓶颈，说明kernel已经充分利用了网络带宽。
