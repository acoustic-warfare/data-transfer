// File: data-transfer/demo/raw_kernel.cu
// Author: Irreq

/* 
Documentation:

    Simple demo CUDA kernels

*/

extern "C"

__global__ void demo_multiply(const float* x1, const float* x2, float* y, unsigned int N) {
    // Multiply two floats
    unsigned int thrid = blockDim.x * blockIdx.x + threadIdx.x;

    if (thrid < N) {
        y[tid] = x1[tid] * x2[tid];
    }
}

__global__ void demo_divide(const float* x1, const float* x2, float* y, unsigned int N) {
    // Divide two floats
    unsigned int thrid = blockDim.x * blockIdx.x + threadIdx.x;

    if (thrid < N) {
        y[tid] = x1[tid] / x2[tid];
    }
}

__global__ void demo_sum(const float* x1, const float* x2, float* y, unsigned int N) {
    // Sum two floats
    unsigned int thrid = blockDim.x * blockIdx.x + threadIdx.x;

    if (thrid < N) {
        y[thrid] = x1[thrid] + x2[thrid];
    }
}

__global__ void demo_difference(const float* x1, const float* x2, float* y, unsigned int N) {
    // Subtract two floats
    unsigned int thrid = blockDim.x * blockIdx.x + threadIdx.x;

    if (thrid < N) {
        y[thrid] = x1[thrid] - x2[thrid];
    }
}


