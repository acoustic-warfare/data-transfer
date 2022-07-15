#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include "cuda_runtime.h"
#include <math.h>
#include <stdio.h>

// Thread block size
#define BLOCK_SIZE 256

extern "C" void cudaBeamWrapper(int *res, const int *first, const int *last, int n_bytes);

// // Allocates an array with random integer entries.
// void randomInit(int *data, int size)
// {
//     for (int i = 0; i < size; ++i)
//         data[i] = rand();
// }

// __global__ void deviceDiffKernel(int *in_1, int *in_2, int *out, int N)
// {

//     int idx = blockIdx.x * blockDim.x + threadIdx.x + 1;
//     int idy = blockIdx.y * blockDim.y + threadIdx.y + 1;

//     out[idy * N + idx] = fabs((double)(in_1[idy * N + idx] - in_2[idy * N + idx]));
// }

// __global__ void r_vecKernel(double *phi, double *theta, int *out, int n_bytes, int N) {
//     int i = blockIdx.x * blockDim.x + threadIdx.x;
//     if (i < N)
//     {
//         float *cosVal;
//         float *sinsinVal;
//         float *sincosVal;
//         out[i] = {sincosVal, sinsinVal, cosVal};
//         sinsinVal = sinf((double)(&theta)) * sinf((double)(&phi));
//     }
// }

// // Manage Thread Divergence
// __global__ void reductionKernel(int *input, int *results, int n) 
// {
//     extern __shared__ int sdata[];
//     unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;
//     unsigned int tx = threadIdx.x;

//     // load input into __shared__ memory
//     int x = INT_MIN;
//     if (i < n)
//         x = input[i];
//     sdata[tx] = x;
//     __syncthreads();

//     // block-wide reduction
//     for (unsigned int offset = blockDim.x >> 1; offset > 0; offset >>= 1)
//     {
//         __syncthreads();
//         if (tx < offset)
//         {
//             if (sdata[tx + offset] > sdata[tx])
//                 sdata[tx] = sdata[tx + offset];
//         }
//     }

//     // finally, thread 0 writes the result
//     if (threadIdx.x == 0)
//     {
//         // the result is per-block
//         results[blockIdx.x] = sdata[0];
//     }
// }

//     int r_vec(double phi, double theta, int n_bytes)
// {
//     int r[3];
//     double cosVal;
//     double sinVal;
//     double sincosVal;
//     // sincos(twopit * f, &sinVal, &cosVal);

//     return 0
// }

__global__ void beamKernel(int *res, const int *a, const int *b, int size)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < size)
    {
        res[i] = a[i] * b[i];
    }
}

// Cuda Wrapper for `beamKernel` used by C or Cython code
void cudaBeamWrapper(int *res, const int *first, const int *last, int n_bytes)
{
    // Setup buffers for GPU
    int *dev_res = nullptr;
    int *dev_first = nullptr;
    int *dev_last = nullptr;

    // Allocate memory on GPU for three vectors
    cudaMalloc((void **)&dev_res, n_bytes * sizeof(int));
    cudaMalloc((void **)&dev_first, n_bytes * sizeof(int));
    cudaMalloc((void **)&dev_last, n_bytes * sizeof(int));

    // Copy allocated host memory to device
    cudaMemcpy(dev_first, first, n_bytes * sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(dev_last, last, n_bytes * sizeof(int), cudaMemcpyHostToDevice);

    // Compute the result using one thread per element in vector
    // 2 is number of computational blocks and (n_bytes + 1) / 2 is a number of threads in a block
    beamKernel<<<2, (n_bytes + 1) / 2>>>(dev_res, dev_first, dev_last, n_bytes);

    // cudaDeviceSynchronize waits for the kernel to finish, and returns
    // any errors encountered during the launch.
    cudaDeviceSynchronize();

    // Copy output vector from GPU buffer to host memory.
    cudaMemcpy(res, dev_res, n_bytes * sizeof(int), cudaMemcpyDeviceToHost);

    // Release allocated memory
    cudaFree(dev_res);
    cudaFree(dev_first);
    cudaFree(dev_last);

    cudaDeviceReset();
}



// int main(int argc, char **argv)
// {
//     const int arraySize = BYTES;
//     int res[arraySize] = {0};
//     int first[arraySize];
//     int last[arraySize];

//     // Inititate random values
//     int i;
//     for (i = 0; i < BYTES; i++)
//     {
//         first[i] = rand();
//     }
//     for (i = 0; i < BYTES; i++)
//     {
//         last[i] = rand();
//     }
    
//     cudaBeamWrapper(res, first, last, arraySize);
//     int loop;
//     for (loop = 0; loop < BYTES; loop++)
//         printf("%d ", res[loop]);
//     printf("\n");
//     cudaDeviceReset();

//     return 0;
// }