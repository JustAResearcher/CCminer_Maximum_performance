/*
 * Double-buffered smix2 kernel for yescryptR32
 *
 * Key optimization: while computing pwxform for V[j_current],
 * asynchronously prefetch V[j_next] into a second buffer.
 *
 * This overlaps the V-array read latency with pwxform computation.
 *
 * The trick: we maintain TWO x[] buffers:
 *   x_curr[64] — being processed by pwxform (current iteration)
 *   x_next[64] — being loaded from V (next iteration's data)
 *
 * After pwxform finishes, we swap buffers and start the next iteration
 * immediately since V data is already loaded.
 *
 * Challenge: j_next = integerify(x_curr[63]) which isn't known until
 * the current iteration's pwxform completes. So we CAN'T prefetch
 * the next V block early.
 *
 * BUT: we CAN overlap the V-WRITE (saving current x to V[j]) with
 * the V-READ (loading next iteration's V[j_next]). Currently these
 * are sequential. By interleaving write[k] and read[k] for different
 * iterations, we double the memory pipeline utilization.
 *
 * Actually the best approach: OVERLAP V-READ WITH PWXFORM.
 *
 * The V-read phase reads 64 entries sequentially:
 *   for (k = 0; k < 64; k++) x[k] ^= __ldL1(&Vdev(j, k));
 *
 * The pwxform phase processes 64 blocks sequentially:
 *   for (k = 0; k < 64; k++) { x3 ^= x[k]; pwxform(x3); x[k] = x3; }
 *
 * pwxform for block k only needs x[k], which was loaded in the V-read
 * phase at iteration k. So pwxform for block 0 can start AS SOON AS
 * V-read for block 0 completes, even while blocks 1-63 are still loading.
 *
 * MERGED LOOP:
 *   for (k = 0; k < 64; k++) {
 *       // Issue V-read for block k+PREFETCH_DIST (if available)
 *       if (k + PF < 64)
 *           prefetch x_temp[k+PF] = __ldL1(&Vdev(j, k+PF));
 *
 *       // V-write for block k
 *       __stL1(&Vdev(j, k), x[k]);
 *
 *       // pwxform for block k (uses x[k] which was read earlier)
 *       x3 ^= x[k]; pwxform(x3); x[k] = x3;
 *   }
 *
 * This requires the V-read to complete BEFORE pwxform uses x[k].
 * If we prefetch PF blocks ahead, we have PF iterations of pwxform
 * to hide the memory latency.
 *
 * With PF=8: 8 blocks * ~40 cycles/block = 320 cycles of compute
 * vs ~100-200 cycles V-read latency. Should fully overlap!
 */

/* This is a design document. The actual implementation would modify
 * the k2c1 kernel's inner loop. */
