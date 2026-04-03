/*
 * k2c1_smem.cuh - smix2 kernel with x[64] in shared memory
 *
 * Same blockDim=(16,2) as original k2c1 (2 nonces per block).
 * x[64] stored in shared memory with transposed layout for zero bank conflicts.
 *
 * Shared memory layout:
 *   [0 .. 4095]        S-boxes: 2 warps * 128 entries * 16 words = 4096 uint32 (16KB)
 *   [4096 .. 6143]     x[] array: 2 warps * 64 blocks * 16 threads = 2048 uint32 (8KB)
 *   Total: 6144 uint32 = 24576 bytes
 *
 * x[] layout: smem[X_BASE + warp*1024 + k*16 + threadIdx.x]
 *   Bank for thread tx accessing x[k]: (X_BASE + warp*1024 + k*16 + tx) % 32
 *   Since X_BASE=4096 (mod 32 = 0), warp*1024 (mod 32 = 0):
 *     bank = (k*16 + tx) % 32
 *     k even: bank = tx          (16 distinct banks for tx=0..15)
 *     k odd:  bank = (16+tx)%32  (16 distinct banks, shifted by 16)
 *   => ZERO bank conflicts for any access pattern.
 *
 * Include after WarpShuffle/SALSA_CORE definitions and before host functions.
 */

#define SMEM_SBOX_SIZE 4096
#define SMEM_X_BASE    SMEM_SBOX_SIZE

#define X_s(k)        x_smem[(k) * 16 + threadIdx.x]
#define Vdev_s(a, b)  v_s[((a) * r * 2 + (b)) * 32]
#define Bdev_s(a)     B[((a) * threads + thread) * 16 + threadIdx.x]
#define Sdev_s(a)     S[(thread_part_4 * 128 + (a)) * 16 + threadIdx.x]
#define Shared_s(a)   *(uint2*)&shared_mem[(threadIdx.y * 512 + (a)) * 4 + (threadIdx.x & 2)]

__global__ __launch_bounds__(32, 4)
void yescrypt_gpu_hash_k2c1_smem(int threads, uint32_t startNonce,
	uint32_t offset1, uint32_t offset2,
	uint32_t start, uint32_t end,
	const uint32_t N, const uint32_t r, const uint32_t p)
{
	uint32_t thread_part_16 = (2 * blockIdx.x + threadIdx.y);
	uint32_t thread_part_4 = thread_part_16 + offset1;
	uint32_t thread = thread_part_16 + offset2;
	extern __shared__ uint32_t shared_mem[];

	uint32_t *v_s = &V[blockIdx.x * N * r * 2 * 32 + threadIdx.y * 16 + threadIdx.x];

	/* Pointer to this warp's x[] region in shared memory */
	uint32_t *x_smem = &shared_mem[SMEM_X_BASE + threadIdx.y * 1024];

	{
		uint32_t j, k;
		uint32_t x0, x1, x2, x3;
		uint2 buf;

		/* Load S-boxes into shared memory (same layout as original) */
		for (k = 0; k < 128; k++)
			shared_mem[(threadIdx.y * 128 + k) * 16 + threadIdx.x] = Sdev_s(k);

		/* Load B[] into shared memory x[] */
		for (k = 0; k < 64; k++) {
			x3 = Bdev_s(k);
			X_s(k) = x3;
		}

		/* Ensure shared memory is visible to all threads in the warp */
		__syncwarp(0xFFFFFFFF);

		for (uint32_t z = start; z < end; z++)
		{
			/* j = x[63] word 0, masked to N-1 */
			x3 = X_s(63);
			j = WarpShuffle(x3, 0, 16) & (N - 1);

			/* x[k] ^= V[j][k] */
			for (k = 0; k < 64; k++)
				X_s(k) ^= __ldL1(&Vdev_s(j, k));

			__syncwarp(0xFFFFFFFF);

			/* V[j][k] = x[k] */
			for (k = 0; k < 64; k++)
				__stL1(&Vdev_s(j, k), X_s(k));

			/* pwxform: x3 is running state, XOR with each x[k], apply 6 rounds */
			x3 = X_s(63);
			for (k = 0; k < 64; k++) {
				x3 ^= X_s(k);
				WarpShuffle2(buf.x, buf.y, x3, x3, 0, 1, 2);
#pragma unroll 1
				for (j = 0; j < 6; j++) {
					WarpShuffle2(x0, x1, buf.x, buf.y, 0, 0, 4);
					x0 = ((x0 >> 4) & 255) + 0;
					x1 = ((x1 >> 4) & 255) + 256;
					buf = mad64(buf.x, buf.y, Shared_s(x0));
					buf ^= Shared_s(x1);
				}
				if (threadIdx.x & 1) x3 = buf.y;
				else x3 = buf.x;

				X_s(k) = x3;
			}

			/* Salsa20/8 core on the last block */
			WarpShuffle4(x0, x1, x2, x3, x3, x3, x3, x3,
				0 + (threadIdx.x & 3), 4 + (threadIdx.x & 3), 8 + (threadIdx.x & 3), 12 + (threadIdx.x & 3), 16);
			SALSA_CORE(x0, x1, x2, x3);
			if (threadIdx.x < 4) x3 = x0;
			else if (threadIdx.x < 8) x3 = x1;
			else if (threadIdx.x < 12) x3 = x2;

			X_s(63) = x3;
			__syncwarp(0xFFFFFFFF);
		}

		/* Write back x[] from shared memory to B[] */
		for (k = 0; k < 64; k++)
			Bdev_s(k) = X_s(k);
	}
}

__global__ __launch_bounds__(32, 4)
void yescrypt_gpu_hash_k2c1_r8_smem(int threads, uint32_t startNonce,
	uint32_t offset1, uint32_t offset2,
	uint32_t start, uint32_t end,
	const uint32_t N)
{
	uint32_t thread_part_16 = (2 * blockIdx.x + threadIdx.y);
	uint32_t thread_part_4 = thread_part_16 + offset1;
	uint32_t thread = thread_part_16 + offset2;
	extern __shared__ uint32_t shared_mem[];

	const uint32_t r = 8;

	uint32_t *v_s = &V[blockIdx.x * N * r * 2 * 32 + threadIdx.y * 16 + threadIdx.x];

	/* x[] region: only r*2=16 blocks, so 16*16=256 uint32 per warp */
	uint32_t *x_smem = &shared_mem[SMEM_SBOX_SIZE + threadIdx.y * (r * 2 * 16)];

	{
		uint32_t j, k;
		uint32_t x0, x1, x2, x3;
		uint2 buf;

		/* Load S-boxes into shared memory */
		for (k = 0; k < 128; k++)
			shared_mem[(threadIdx.y * 128 + k) * 16 + threadIdx.x] = Sdev_s(k);

		/* Load B[] into shared memory x[] */
#pragma unroll 1
		for (k = 0; k < r * 2; k++)
			X_s(k) = Bdev_s(k);

		__syncwarp(0xFFFFFFFF);

		for (uint32_t z = start; z < end; z++)
		{
			x3 = X_s(r * 2 - 1);
			j = WarpShuffle(x3, 0, 16) & (N - 1);

			/* x[k] ^= V[j][k] */
#pragma unroll 1
			for (k = 0; k < r * 2; k++)
				X_s(k) ^= __ldL1(&Vdev_s(j, k));

			__syncwarp(0xFFFFFFFF);

			/* V[j][k] = x[k] */
#pragma unroll 1
			for (k = 0; k < r * 2; k++)
				__stL1(&Vdev_s(j, k), X_s(k));

			/* pwxform */
			x3 = X_s(r * 2 - 1);
#pragma unroll 1
			for (k = 0; k < r * 2; k++) {
				x3 ^= X_s(k);
				WarpShuffle2(buf.x, buf.y, x3, x3, 0, 1, 2);
#pragma unroll 1
				for (j = 0; j < 6; j++) {
					WarpShuffle2(x0, x1, buf.x, buf.y, 0, 0, 4);
					x0 = ((x0 >> 4) & 255) + 0;
					x1 = ((x1 >> 4) & 255) + 256;
					buf = mad64(buf.x, buf.y, Shared_s(x0));
					buf ^= Shared_s(x1);
				}
				if (threadIdx.x & 1) x3 = buf.y;
				else x3 = buf.x;

				X_s(k) = x3;
			}

			/* Salsa20/8 core */
			WarpShuffle4(x0, x1, x2, x3, x3, x3, x3, x3,
				0 + (threadIdx.x & 3), 4 + (threadIdx.x & 3), 8 + (threadIdx.x & 3), 12 + (threadIdx.x & 3), 16);
			SALSA_CORE(x0, x1, x2, x3);
			if (threadIdx.x < 4) x3 = x0;
			else if (threadIdx.x < 8) x3 = x1;
			else if (threadIdx.x < 12) x3 = x2;

			X_s(r * 2 - 1) = x3;
			__syncwarp(0xFFFFFFFF);
		}

		/* Write back */
#pragma unroll 1
		for (k = 0; k < r * 2; k++)
			Bdev_s(k) = X_s(k);
	}
}

#undef SMEM_SBOX_SIZE
#undef SMEM_X_BASE
#undef X_s
#undef Vdev_s
#undef Bdev_s
#undef Sdev_s
#undef Shared_s
