// Stub functions for deprecated algo modules (texture references removed in CUDA 13+)
// C++ linkage (no extern "C") to match ccminer's declarations
#include <cstdint>
int x11_simd512_cpu_init(int t, uint32_t n) { return 0; }
void x11_simd512_cpu_hash_64(int t, uint32_t n, uint32_t s, uint32_t *d, uint32_t o) {}
void fugue256_cpu_hash(int t, uint32_t n, int o, void *d, uint32_t *r) {}
void fugue256_cpu_init(int t, uint32_t n) {}
void fugue256_cpu_setBlock(int t, void *e, void *k) {}
void groestl256_cpu_hash_32(int t, uint32_t n, uint32_t s, uint64_t *d, uint32_t *r) {}
void groestl256_cpu_init(int t, uint32_t n) {}
void groestl256_setTarget(int t, const void *d) {}
void x13_fugue512_cpu_hash_64(int t, uint32_t n, uint32_t s, uint32_t *d) {}
void x13_fugue512_cpu_hash_64_final(int t, uint32_t n, uint32_t s, uint32_t *d, uint32_t *r) {}
void x13_fugue512_cpu_init(int t, uint32_t n) {}
void x13_fugue512_cpu_setTarget(int t, const void *d) {}
int scanhash_neoscrypt(bool a, int t, uint32_t *d, uint32_t *tgt, uint32_t mn, uint32_t *hd) { return 0; }
