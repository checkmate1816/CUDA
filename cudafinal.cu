#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include "timer.h"
#include "check.h"

#define SOFTENING 1e-9f
#define BLOCK_SIZE 32
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

__global__ void bodyForce(Body *p, float dt, int n)
 {
   int i=threadIdx.x+blockDim.x*(blockIdx.x%128);
   float tempx=p[(blockIdx.x%128)*blockDim.x+threadIdx.x].x;
   float tempy=p[(blockIdx.x%128)*blockDim.x+threadIdx.x].y;
   float tempz=p[(blockIdx.x%128)*blockDim.x+threadIdx.x].z;
   
    float Fx = 0.0f; float Fy = 0.0f; float Fz = 0.0f;
     __shared__ float3 spos[BLOCK_SIZE];
      Body tpos = p[(blockIdx.x/128) * blockDim.x + threadIdx.x];
      spos[threadIdx.x] = make_float3(tpos.x, tpos.y, tpos.z);
      __syncthreads();
    for (int j = 0; j < BLOCK_SIZE; j++) 
    {
      float dx = spos[j].x - tempx;
      float dy = spos[j].y - tempy;
      float dz = spos[j].z - tempz;
      float distSqr = dx*dx + dy*dy + dz*dz + SOFTENING;
      float invDist = rsqrtf(distSqr);
      float invDist3 = invDist * invDist * invDist;

      Fx += dx * invDist3; Fy += dy * invDist3; Fz += dz * invDist3;
    }
    __syncthreads();
   
    atomicAdd(&p[i].vx, dt*Fx); 
    atomicAdd(&p[i].vy, dt*Fy); 
    atomicAdd(&p[i].vz, dt*Fz);
 }

__global__ void add(Body *p,float dt,int n)
{
int i=threadIdx.x+blockDim.x*blockIdx.x;
int stride=gridDim.x*blockDim.x;
for(;i<n;i+=stride)
{
      p[i].x += p[i].vx*dt;
      p[i].y += p[i].vy*dt;
      p[i].z += p[i].vz*dt;
}

}





int main(const int argc, const char** argv) {

  /*
   * Do not change the value for `nBodies` here. If you would like to modify it,
   * pass values into the command line.
   */

  int nBodies = 2<<11;
  int salt = 0;
  int numberOfSMs;
  if (argc > 1) nBodies = 2<<atoi(argv[1]);

  /*
   * This salt is for assessment reasons. Tampering with it will result in automatic failure.
   */

  if (argc > 2) salt = atoi(argv[2]);

  const float dt = 0.01f; // time step
  const int nIters = 10;  // simulation iterations

  int bytes = nBodies * sizeof(Body);
  float *buf;

  cudaMallocManaged(&buf, bytes);

  Body *p = (Body*)buf;
  int deviceId;
  cudaGetDevice(&deviceId);
  cudaDeviceGetAttribute(&numberOfSMs, cudaDevAttrMultiProcessorCount, deviceId);
  
  /*
   * As a constraint of this exercise, `randomizeBodies` must remain a host function.
   */

  randomizeBodies(buf, 6 * nBodies); // Init pos / vel data
  cudaMemPrefetchAsync(p, bytes, deviceId);
  double totalTime = 0.0;
  int blocknum=(nBodies+BLOCK_SIZE-1)/BLOCK_SIZE;
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
   
    bodyForce<<<blocknum*128,BLOCK_SIZE>>>(p, dt, nBodies); // compute interbody forces
    add<<<blocknum,BLOCK_SIZE>>>(p,dt,nBodies);
    cudaDeviceSynchronize();
  /*
   * This position integration cannot occur until this round of `bodyForce` has completed.
   * Also, the next round of `bodyForce` cannot begin until the integration is complete.
   */
 
    
  /*******************************************************************/
  // Do not modify the code in this section.
    const double tElapsed = GetTimer() / 1000.0;
    totalTime += tElapsed;
  }
 cudaMemPrefetchAsync(p, bytes, cudaCpuDeviceId);
 
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
   * Feel free to modify code below.
   */

  cudaFree(buf);
}