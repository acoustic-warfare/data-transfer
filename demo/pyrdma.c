// File: data-transfer/demo/pyrdma.c
// Author: Irreq

#include <stdio.h>

#include "pyrdma.h"

static const int RDMA_BUFFER_SIZE = 1024;

static const int *ptr;

int call(int msg) {
    printf("%d", msg);
    ptr = &RDMA_BUFFER_SIZE;
    return *ptr;
}