#include <stdio.h>
#include "beam.h"
#include "common.h"

// Dummy param for creating a simple array of BYTES size
#define BYTES 64

extern void cudaBeamWrapper(const int *res, const int *first, const int *last, int n_bytes);

void say_hello(int times)
{
    for (int i = 0; i < times; ++i)
    {
        printf("%d. Hello, Python. I am C!\n", i + 1);
    }
}


void pythonCudaBridgeWrapper(int n_bytes) {
    test();
    const int arraySize = BYTES;
    // const int res[arraySize] = {0};
    int res[arraySize];
    memset(res, 0, arraySize * sizeof(int));
    int first[arraySize];
    int last[arraySize];

    // Inititate random values
    int i;
    for (i = 0; i < BYTES; i++)
    {
        // first[i] = rand();
        first[i] = i;
    }
    for (i = 0; i < BYTES; i++)
    {
        // last[i] = rand();
        last[i] = 2;
    }

    cudaBeamWrapper(res, first, last, arraySize);
    int loop;
    for (loop = 0; loop < BYTES; loop++)
        printf("%d ", res[loop]);
    printf("\n");
    printf("Your input: %d", n_bytes);
}

// int main(int argc, char **argv)
// {
//     const int arraySize = BYTES;
//     // const int res[arraySize] = {0};
//     int res[arraySize];
//     memset(res, 0, arraySize * sizeof(int));
//     int first[arraySize];
//     int last[arraySize];

//     // Inititate random values
//     int i;
//     for (i = 0; i < BYTES; i++)
//     {
//         // first[i] = rand();
//         first[i] = i;
//     }
//     for (i = 0; i < BYTES; i++)
//     {
//         // last[i] = rand();
//         last[i] = 2;
//     }

//     cudaBeamWrapper(res, first, last, arraySize);
//     int loop;
//     for (loop = 0; loop < BYTES; loop++)
//         printf("%d ", res[loop]);
//     printf("\n");

//     return 0;
// }