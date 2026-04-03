# CCminer Maximum Performance

Optimized ccminer for **yescryptR32** GPU mining. **+41% hashrate** over stock ccminer on NVIDIA RTX GPUs.

## Benchmarks

| GPU | Stock ccminer | This build | Improvement |
|-----|--------------|------------|-------------|
| RTX 5090 | 9,550 H/s | **13,500 H/s** | **+41%** |
| RTX 4090 | ~8,300 H/s | ~11,700 H/s | ~+41% |
| RTX 4070 Ti Super | ~6,200 H/s | ~8,800 H/s | ~+42% |

## Optimizations

1. **x[256] to x[64]**: 75% less local memory traffic
2. **Thread count unlock**: Max VRAM utilization
3. **launch_bounds(32,16)**: 128 regs, 16 blocks/SM occupancy
4. **nounroll**: Prevents register pressure from inner loop
5. **ld.global.cg + st.global.cs**: L2-only V caching, streaming writes
6. **Auto-detection**: SM >= 890 (Ada Lovelace+) enables all optimizations

## HiveOS Installation

1. Download `ccminer-yescrypt.tar.gz` from [Releases](https://github.com/JustAResearcher/CCminer_Maximum_performance/releases)
2. HiveOS Dashboard -> Flight Sheets -> Custom Miner
3. Installation URL: the release tar.gz URL
4. Hash algorithm: `yescryptR32`
5. Wallet template: `%WAL%.%WORKER_NAME%`
6. Extra config: `-i 14.66` (RTX 5090) or `-i 13.9` (RTX 4070 Ti Super)

## Intensity Per GPU

| GPU | Intensity |
|-----|-----------|
| RTX 5090 (32GB) | `-i 14.66` |
| RTX 4090 (24GB) | `-i 14.3` |
| RTX 4070 Ti Super (16GB) | `-i 13.9` |

## Building from Source (Linux)

```bash
sudo apt-get install build-essential automake autoconf libcurl4-openssl-dev libjansson-dev libssl-dev
git clone https://github.com/JustAResearcher/CCminer_Maximum_performance.git
cd CCminer_Maximum_performance
./autogen.sh
./configure --with-cuda=/usr/local/cuda CFLAGS="-O3" CXXFLAGS="-O3"
make -j$(nproc)
strip ccminer
cp ccminer hiveos/ && cd hiveos && ./package.sh
```

## Credits

Based on [Kudaraidee/ccmineryescrypt](https://github.com/Kudaraidee/ccmineryescrypt).
