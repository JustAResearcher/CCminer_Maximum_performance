/*
 * k2c1_regvars.cuh - smix2 kernel with register-tiled pwxform
 *
 * blockDim=(16,2), same V/B/S layout as original k2c1.
 * Innovation: pwxform processes x[] in 4 passes of 16 blocks each,
 * keeping 16 values in registers per pass instead of 64 in local memory.
 * This reduces local memory traffic by ~4x during the pwxform phase.
 *
 * Register budget per pass: 16 (tile) + ~20 (compute) = ~36
 * x[64] local array still used for V-read/V-write phases.
 *
 * Include after WarpShuffle/SALSA_CORE definitions and before host functions.
 * Requires: Vdev, Bdev, Sdev, Shared macros already defined.
 */

#define REGVARS_LOAD16(base) \
	uint32_t r0  = x[(base)+0],  r1  = x[(base)+1],  r2  = x[(base)+2],  r3  = x[(base)+3],  \
	         r4  = x[(base)+4],  r5  = x[(base)+5],  r6  = x[(base)+6],  r7  = x[(base)+7],  \
	         r8  = x[(base)+8],  r9  = x[(base)+9],  r10 = x[(base)+10], r11 = x[(base)+11], \
	         r12 = x[(base)+12], r13 = x[(base)+13], r14 = x[(base)+14], r15 = x[(base)+15];

#define REGVARS_STORE16(base) \
	x[(base)+0]  = r0;  x[(base)+1]  = r1;  x[(base)+2]  = r2;  x[(base)+3]  = r3;  \
	x[(base)+4]  = r4;  x[(base)+5]  = r5;  x[(base)+6]  = r6;  x[(base)+7]  = r7;  \
	x[(base)+8]  = r8;  x[(base)+9]  = r9;  x[(base)+10] = r10; x[(base)+11] = r11; \
	x[(base)+12] = r12; x[(base)+13] = r13; x[(base)+14] = r14; x[(base)+15] = r15;

#define REGVARS_GET(k, dst) \
	switch (k) { \
		case 0:  dst = r0;  break; case 1:  dst = r1;  break; \
		case 2:  dst = r2;  break; case 3:  dst = r3;  break; \
		case 4:  dst = r4;  break; case 5:  dst = r5;  break; \
		case 6:  dst = r6;  break; case 7:  dst = r7;  break; \
		case 8:  dst = r8;  break; case 9:  dst = r9;  break; \
		case 10: dst = r10; break; case 11: dst = r11; break; \
		case 12: dst = r12; break; case 13: dst = r13; break; \
		case 14: dst = r14; break; case 15: dst = r15; break; \
	}

#define REGVARS_SET(k, val) \
	switch (k) { \
		case 0:  r0  = val; break; case 1:  r1  = val; break; \
		case 2:  r2  = val; break; case 3:  r3  = val; break; \
		case 4:  r4  = val; break; case 5:  r5  = val; break; \
		case 6:  r6  = val; break; case 7:  r7  = val; break; \
		case 8:  r8  = val; break; case 9:  r9  = val; break; \
		case 10: r10 = val; break; case 11: r11 = val; break; \
		case 12: r12 = val; break; case 13: r13 = val; break; \
		case 14: r14 = val; break; case 15: r15 = val; break; \
	}

/* Inline pwxform pass over 16 register-resident blocks */
#define REGVARS_PWXFORM_PASS(base) \
	{ \
		REGVARS_LOAD16(base) \
		_Pragma("unroll") \
		for (uint32_t kk = 0; kk < 16; kk++) { \
			uint32_t xk; \
			REGVARS_GET(kk, xk) \
			x3 ^= xk; \
			WarpShuffle2(buf.x, buf.y, x3, x3, 0, 1, 2); \
			_Pragma("unroll 3") \
			for (j = 0; j < 6; j++) { \
				WarpShuffle2(x0, x1, buf.x, buf.y, 0, 0, 4); \
				x0 = ((x0 >> 4) & 255) + 0; \
				x1 = ((x1 >> 4) & 255) + 256; \
				buf = mad64(buf.x, buf.y, RV_Shared(x0)); \
				buf ^= RV_Shared(x1); \
			} \
			if (threadIdx.x & 1) x3 = buf.y; \
			else x3 = buf.x; \
			REGVARS_SET(kk, x3) \
		} \
		REGVARS_STORE16(base) \
	}

/* Re-define macros needed by this kernel (parent file #undef'd them) */
#define RV_Vdev(a, b)  v[((a) * r*2 + (b)) * 32]
#define RV_Bdev(a)     B[((a) * threads + thread) * 16 + threadIdx.x]
#define RV_Sdev(a)     S[(thread_part_4 * 128 + (a)) * 16 + threadIdx.x]
#define RV_Shared(a)   *(uint2*)&sbase[(a) * 4]

__global__ __launch_bounds__(32, 16)
void yescrypt_gpu_hash_k2c1_regvars(int threads, uint32_t startNonce,
	uint32_t offset1, uint32_t offset2,
	uint32_t start, uint32_t end,
	const uint32_t N, const uint32_t r, const uint32_t p)
{
	uint32_t thread_part_16 = (2 * blockIdx.x + threadIdx.y);
	uint32_t thread_part_4 = thread_part_16 + offset1;
	uint32_t thread = thread_part_16 + offset2;
	extern __shared__ uint32_t shared_mem[];

	uint32_t *v = &V[blockIdx.x * N * r * 2 * 32 + threadIdx.y * 16 + threadIdx.x];

	{
		uint32_t j, k;
		uint32_t x0, x1, x2, x3;
		uint2 buf;
		uint32_t x[64];

		/* Load S-boxes into shared memory */
		for (k = 0; k < 128; k++)
			shared_mem[(threadIdx.y * 128 + k) * 16 + threadIdx.x] = RV_Sdev(k);

		/* sbase pointer for pwxform S-box lookups */
		uint32_t *sbase = &shared_mem[threadIdx.y * 2048 + (threadIdx.x & 2)];

		/* Load B[] into x[] */
		for (k = 0; k < 64; k++) {
			x3 = RV_Bdev(k);
			x[k] = x3;
		}

		for (uint32_t z = start; z < end; z++)
		{
			/* j = x[63] lane 0, masked to N-1 */
			j = WarpShuffle(x3, 0, 16) & (N - 1);

			/* x[k] ^= V[j][k] */
			for (k = 0; k < 64; k++)
				x[k] ^= __ldL1(&RV_Vdev(j, k));

			/* V[j][k] = x[k] */
			for (k = 0; k < 64; k++)
				__stL1(&RV_Vdev(j, k), x[k]);

			/* Register-tiled pwxform: 4 passes of 16 blocks */
			x3 = x[63];
			REGVARS_PWXFORM_PASS(0)
			REGVARS_PWXFORM_PASS(16)
			REGVARS_PWXFORM_PASS(32)
			REGVARS_PWXFORM_PASS(48)

			/* Salsa20/8 core on last block */
			WarpShuffle4(x0, x1, x2, x3, x3, x3, x3, x3,
				0 + (threadIdx.x & 3), 4 + (threadIdx.x & 3),
				8 + (threadIdx.x & 3), 12 + (threadIdx.x & 3), 16);
			SALSA_CORE(x0, x1, x2, x3);
			if (threadIdx.x < 4) x3 = x0;
			else if (threadIdx.x < 8) x3 = x1;
			else if (threadIdx.x < 12) x3 = x2;

			x[63] = x3;
		}

		/* Write back to B[] */
		for (k = 0; k < 64; k++)
			RV_Bdev(k) = x[k];
	}
}

__global__ __launch_bounds__(32, 16)
void yescrypt_gpu_hash_k2c1_r8_regvars(int threads, uint32_t startNonce,
	uint32_t offset1, uint32_t offset2,
	uint32_t start, uint32_t end,
	const uint32_t N)
{
	uint32_t thread_part_16 = (2 * blockIdx.x + threadIdx.y);
	uint32_t thread_part_4 = thread_part_16 + offset1;
	uint32_t thread = thread_part_16 + offset2;
	extern __shared__ uint32_t shared_mem[];

	const uint32_t r = 8;

	uint32_t *v = &V[blockIdx.x * N * r * 2 * 32 + threadIdx.y * 16 + threadIdx.x];

	{
		uint32_t j, k;
		uint32_t x0, x1, x2, x3;
		uint2 buf;
		uint32_t x[r * 2]; /* 16 blocks for r=8 */

		/* Load S-boxes */
		for (k = 0; k < 128; k++)
			shared_mem[(threadIdx.y * 128 + k) * 16 + threadIdx.x] = RV_Sdev(k);

		uint32_t *sbase = &shared_mem[threadIdx.y * 2048 + (threadIdx.x & 2)];

#pragma unroll 1
		for (k = 0; k < r * 2; k++)
			x[k] = RV_Bdev(k);

		for (uint32_t z = start; z < end; z++)
		{
			j = WarpShuffle(x[r * 2 - 1], 0, 16) & (N - 1);

#pragma unroll 1
			for (k = 0; k < r * 2; k++)
				x[k] ^= __ldL1(&RV_Vdev(j, k));

#pragma unroll 1
			for (k = 0; k < r * 2; k++)
				__stL1(&RV_Vdev(j, k), x[k]);

			/* r=8: only 16 blocks, fits in one register tile */
			x3 = x[r * 2 - 1];
			REGVARS_PWXFORM_PASS(0)

			/* Salsa20/8 core */
			WarpShuffle4(x0, x1, x2, x3, x3, x3, x3, x3,
				0 + (threadIdx.x & 3), 4 + (threadIdx.x & 3),
				8 + (threadIdx.x & 3), 12 + (threadIdx.x & 3), 16);
			SALSA_CORE(x0, x1, x2, x3);
			if (threadIdx.x < 4) x3 = x0;
			else if (threadIdx.x < 8) x3 = x1;
			else if (threadIdx.x < 12) x3 = x2;

			x[r * 2 - 1] = x3;
		}

#pragma unroll 1
		for (k = 0; k < r * 2; k++)
			RV_Bdev(k) = x[k];
	}
}

#undef REGVARS_LOAD16
#undef REGVARS_STORE16
#undef REGVARS_GET
#undef REGVARS_SET
#undef REGVARS_PWXFORM_PASS
