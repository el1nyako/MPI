#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include "timer.h"
#include "check.h"
#include <cuda_runtime.h>
 
#define SOFTENING 1e-9f
 
/*
 * Each body contains x, y, and z coordinate positions,
 * as well as velocities in the x, y, and z directions.
 */
 
typedef struct { float x, y, z, vx, vy, vz; } Body;
 
/*
 * Do not modify this function. A constraint of this exercise is
 * that it remain a host function.
 */
 
void randomizeBodies(float *data, int n) {
  for (int i = 0; i < n; i++) {
    data[i] = 2.0f * (rand() / (float)RAND_MAX) - 1.0f;
  }
}

 
/*
 * This function calculates the gravitational impact of all bodies in the system
 * on all others, but does not update their positions.
 */
 
__global__ void bodyForceKernel(Body *p, float dt, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;

    float Fx = 0.0f, Fy = 0.0f, Fz = 0.0f;
    float x = p[i].x, y = p[i].y, z = p[i].z;

    for (int j = 0; j < n; j++) {
        float dx = p[j].x - x;
        float dy = p[j].y - y;
        float dz = p[j].z - z;
        float distSqr = dx*dx + dy*dy + dz*dz + SOFTENING;
        float invDist = rsqrtf(distSqr);
        float invDist3 = invDist * invDist * invDist;

        Fx += dx * invDist3;
        Fy += dy * invDist3;
        Fz += dz * invDist3;
    }

    p[i].vx += dt * Fx;
    p[i].vy += dt * Fy;
    p[i].vz += dt * Fz;
}


__global__ void integrateKernel(Body *p, float dt, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;

    p[i].x += p[i].vx * dt;
    p[i].y += p[i].vy * dt;
    p[i].z += p[i].vz * dt;
}


 
int main(const int argc, const char** argv) {
 
  /*
   * Do not change the value for `nBodies` here. If you would like to modify it,
   * pass values into the command line.
   */
  
  int nBodies = 2<<11;
  int salt = 0;
  if (argc > 1) nBodies = 2<<atoi(argv[1]);
 
  /*
   * This salt is for assessment reasons. Tampering with it will result in automatic failure.
   */
 
  if (argc > 2) salt = atoi(argv[2]);
 
  const float dt = 0.01f; // time step
  const int nIters = 10;  // simulation iterations
 
  int bytes = nBodies * sizeof(Body);
  float *buf;
  buf = (float *)malloc(bytes);
  Body *p = (Body*)buf;
  Body *d_p;

 
  /*
   * As a constraint of this exercise, `randomizeBodies` must remain a host function.
   */
 
  randomizeBodies(buf, 6 * nBodies); // Init pos / vel data

  cudaMalloc((void**)&d_p, bytes);
  cudaMemcpy(d_p, p, bytes, cudaMemcpyHostToDevice);
  
  int block_size = 256;
  int grid_size = (nBodies + block_size - 1) / block_size;
 
  double totalTime = 0.0;
 
  /*
   * This simulation will run for 10 cycles of time, calculating gravitational
   * interaction amongst bodies, and adjusting their positions to reflect.
   */
 
  /*******************************************************************/
  // Do not modify these 2 lines of code.
  for (int iter = 0; iter < nIters; iter++) {
    StartTimer();
  /*******************************************************************/
 
  /*
   * You will likely wish to refactor the work being done in `bodyForce`,
   * as well as the work to integrate the positions.
   */
 
    bodyForceKernel<<<grid_size, block_size>>>(d_p, dt, nBodies); // compute interbody forces
 
  /*
   * This position integration cannot occur until this round of `bodyForce` has completed.
   * Also, the next round of `bodyForce` cannot begin until the integration is complete.
   */
    cudaDeviceSynchronize();
    // for (int i = 0 ; i < nBodies; i++) { // integrate position
      // p[i].x += p[i].vx*dt;
      // p[i].y += p[i].vy*dt;
      // p[i].z += p[i].vz*dt;
    // }

    integrateKernel<<<grid_size, block_size>>>(d_p, dt, nBodies);


    cudaDeviceSynchronize();
    cudaMemcpy(p, d_p, bytes, cudaMemcpyDeviceToHost);

  /*******************************************************************/
  // Do not modify the code in this section.
    const double tElapsed = GetTimer() / 1000.0;
    totalTime += tElapsed;
  }
 
  double avgTime = totalTime / (double)(nIters);
  float billionsOfOpsPerSecond = 1e-9 * nBodies * nBodies / avgTime;
 
#ifdef ASSESS
  checkPerformance(buf, billionsOfOpsPerSecond, salt);
#else
  checkAccuracy(buf, nBodies);
  printf("%d Bodies: average %0.3f Billion Interactions / second\n", nBodies, billionsOfOpsPerSecond);
  salt += 1;
#endif
  /*******************************************************************/
 
  /*
   *  Feel free to modify code below.
   */
  cudaFree(d_p);

  free(buf);
}
