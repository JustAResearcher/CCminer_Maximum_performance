/*
 * yescrypt_gpu_hash_k2c1_32t - 32-thread-per-nonce variant of k2c1
 *
 * Uses blockDim=(32,1) with 1 nonce per block (full warp).
 * Threads 0-15 and 16-31 compute identically (redundant halves).
 * All shuffle operations use width<=16 so both halves are independent.
 *
 * Include this file from cuda_yescrypt.cu after the WarpShuffle/SALSA_CORE
 * definitions and before the host functions.
 */

#define Vdev32(a, b) v32[((a) * 64 + (b)) * 32]
#define Bdev32(a) B[((a) * threads + nonce_idx) * 16 + lane]
#define Sdev32(a) S[(nonce_part4 * 128 + (a)) * 16 + lane]
#define Shared32(a) *(uint2*)&shared_mem[((a)) * 4 + (lane & 2)]

__global__ __launch_bounds__(32, 16)
void yescrypt_gpu_hash_k2c1_32t(int threads, uint32_t startNonce,
	uint32_t offset1, uint32_t offset2,
	uint32_t start, uint32_t end,
	const uint32_t N, const uint32_t r, const uint32_t p)
{
	const uint32_t lane = threadIdx.x & 15;
	const uint32_t nonce_part16 = blockIdx.x;
	const uint32_t nonce_part4 = nonce_part16 + offset1;
	const uint32_t nonce_idx = nonce_part16 + offset2;
	extern __shared__ uint32_t shared_mem[];

	/* V layout is shared with 16-thread k2c kernel:
	 * V is organized as (threads/32) V-blocks, each containing 2 nonces.
	 * blockIdx.x in 32t mode = nonce_part16, so V block = blockIdx.x / 2.
	 * Within that V block, the nonce at offset 0 uses lanes 0-15,
	 * and nonce at offset 1 uses lanes 16-31 (= lanes 0-15 + 16).
	 * Since our 32t kernel has 1 nonce per block, we need to map:
	 *   v_block = blockIdx.x / 2
	 *   v_offset = (blockIdx.x & 1) * 16  (0 or 16)
	 * Then: v = &V[v_block * N * 64 * 32 + v_offset + lane]
	 */
	uint32_t *v32 = (uint32_t*)&V[(blockIdx.x / 2) * N * 64 * 32 + (blockIdx.x & 1) * 16 + lane];

	{
		uint32_t j, k;
		uint32_t x0, x1, x2, x3;
		uint2 buf;
		uint32_t x[64];

		for (k = 0; k < 128; k++)
			shared_mem[k * 16 + lane] = Sdev32(k);

		// Duplicate store from both halves is harmless (same value, same address)
		__syncwarp(0xFFFFFFFF);

		for (k = 0; k < 64; k++) {
			x3 = Bdev32(k);
			x[k] = x3;
		}

		for (uint32_t z = start; z < end; z++)
		{
			j = WarpShuffle(x3, 0, 16) & (N - 1);

			for (k = 0; k < 64; k++)
				x[k] ^= __ldL1(&Vdev32(j, k));

			for (k = 0; k < 64; k++) {
				x3 = x[k];
				__stL1(&Vdev32(j, k), x3);
			}

			for (k = 0; k < 64; k++) {
				x3 ^= x[k];
				WarpShuffle2(buf.x, buf.y, x3, x3, 0, 1, 2);
#pragma nounroll
				for (j = 0; j < 6; j++) {
					WarpShuffle2(x0, x1, buf.x, buf.y, 0, 0, 4);
					x0 = ((x0 >> 4) & 255) + 0;
					x1 = ((x1 >> 4) & 255) + 256;
					buf = mad64(buf.x, buf.y, Shared32(x0));
					buf ^= Shared32(x1);
				}
				if (lane & 1) x3 = buf.y;
				else x3 = buf.x;

				x[k] = x3;
			}
			WarpShuffle4(x0, x1, x2, x3, x3, x3, x3, x3,
				0 + (lane & 3), 4 + (lane & 3), 8 + (lane & 3), 12 + (lane & 3), 16);
			SALSA_CORE(x0, x1, x2, x3);
			if (lane < 4) x3 = x0;
			else if (lane < 8) x3 = x1;
			else if (lane < 12) x3 = x2;

			x[64 - 1] = x3;
		}

		for (k = 0; k < 64; k++)
			Bdev32(k) = x[k];
	}
}

__global__ __launch_bounds__(32, 16)
void yescrypt_gpu_hash_k2c1_r8_32t(int threads, uint32_t startNonce,
	uint32_t offset1, uint32_t offset2,
	uint32_t start, uint32_t end,
	const uint32_t N)
{
	const uint32_t lane = threadIdx.x & 15;
	const uint32_t nonce_part16 = blockIdx.x;
	const uint32_t nonce_part4 = nonce_part16 + offset1;
	const uint32_t nonce_idx = nonce_part16 + offset2;
	extern __shared__ uint32_t shared_mem[];

	const uint32_t r = 8;

	uint32_t *v32 = (uint32_t*)&V[(blockIdx.x / 2) * N * r * 2 * 32 + (blockIdx.x & 1) * 16 + lane];

	{
		uint32_t j, k;
		uint32_t x0, x1, x2, x3;
		uint2 buf;
		uint32_t x[r * 2];

		for (k = 0; k < 128; k++)
			shared_mem[k * 16 + lane] = Sdev32(k);

		__syncwarp(0xFFFFFFFF);

#pragma nounroll
		for (k = 0; k < r * 2; k++)
			x[k] = Bdev32(k);

		for (uint32_t z = start; z < end; z++)
		{
			j = WarpShuffle(x[r * 2 - 1], 0, 16) & (N - 1);

#pragma nounroll
			for (k = 0; k < r * 2; k++)
				x[k] ^= __ldL1(&Vdev32(j, k));

#pragma nounroll
			for (k = 0; k < r * 2; k++) {
				x3 = x[k];
				__stL1(&Vdev32(j, k), x3);
			}

#pragma nounroll
			for (k = 0; k < r * 2; k++) {
				x3 ^= x[k];
				WarpShuffle2(buf.x, buf.y, x3, x3, 0, 1, 2);
#pragma nounroll
				for (j = 0; j < 6; j++) {
					WarpShuffle2(x0, x1, buf.x, buf.y, 0, 0, 4);
					x0 = ((x0 >> 4) & 255) + 0;
					x1 = ((x1 >> 4) & 255) + 256;
					buf = mad64(buf.x, buf.y, Shared32(x0));
					buf ^= Shared32(x1);
				}
				if (lane & 1) x3 = buf.y;
				else x3 = buf.x;

				x[k] = x3;
			}
			WarpShuffle4(x0, x1, x2, x3, x3, x3, x3, x3,
				0 + (lane & 3), 4 + (lane & 3), 8 + (lane & 3), 12 + (lane & 3), 16);
			SALSA_CORE(x0, x1, x2, x3);
			if (lane < 4) x3 = x0;
			else if (lane < 8) x3 = x1;
			else if (lane < 12) x3 = x2;

			x[r * 2 - 1] = x3;
		}

#pragma nounroll
		for (k = 0; k < r * 2; k++)
			Bdev32(k) = x[k];
	}
}

#undef Vdev32
#undef Bdev32
#undef Sdev32
#undef Shared32
