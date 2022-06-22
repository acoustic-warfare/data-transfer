#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import argparse
import ctypes
import signal
import socket
import queue
import threading

import numpy as np

try:
    import cupy as cp
    from cupy.cuda.runtime import memcpyPeer

    cp.cuda.Stream.null.synchronize()
    GPU_MODE = True

except ImportError:
    print("`cupy` could not be found, defaulting to `pycuda`")
    try:
        import pycuda.driver.memcpy_peer as memcpyPeer
    except ImportError:
        print("`pycuda` could not be found, defaulting to CPU")
        GPU_MODE = False
        

"""
Compile the Ctypes Common

gcc -shared -Wl,-soname,rdma-common -o rdma-common.so -fPIC rdma-common.c

"""

PROJECT_PATH = os.path.expanduser("~/data-transfer/demo/")

KERNEL_PATH = PROJECT_PATH + "raw_kernel.cu"

C_LIB = PROJECT_PATH + 'libpyrdma.so'

rdma = ctypes.CDLL(C_LIB)

try:
    rdma = ctypes.CDLL(C_LIB)
except OSError:
    print(f"`{C_LIB}` could not be found, have you compiled it?\n\ngcc -shared -Wl,-soname,pyrdma -o pyrdma.so -fPIC pyrdma.c\n")
    exit(1)

def get_args() -> object:
    parser = argparse.ArgumentParser()
    parser.add_argument("--server", action="store_true")
    parser.add_argument("--client", help="ip address of server")
    return parser.parse_args()



def load_cuda_kernel(path):
    """Load a cuda kernel as a .cu file"""
    with open(path, "r") as kernel_file:
        raw_kernel = "".join([i for i in kernel_file])
        kernel_file.close()

    kernel = cp.RawModule(code=raw_kernel)

    return kernel

def cuda_calc_demo():

    kernel = load_kernel(KERNEL_PATH)

    ker_sum = kernel.get_function('test_sum')

    ker_times = kernel.get_function('test_multiply')

    N = 10

    x1 = cp.arange(N**2, dtype=cp.float32).reshape(N, N)

    x2 = cp.ones((N, N), dtype=cp.float32)

    y = cp.zeros((N, N), dtype=cp.float32)

    ker_sum((N,), (N,), (x1, x2, y, N**2))   # y = x1 + x2

    assert cp.allclose(y, x1 + x2)

    ker_times((N,), (N,), (x1, x2, y, N**2)) # y = x1 * x2

    assert cp.allclose(y, x1 * x2)

def server(ip="10.0.0.2", port=12345):
    pass

def client(ip="10.0.0.1", port=12345):
    pass

class Connection:
    running = True
    def __init__(self):
        signal.signal(signal.SIGINT, self._exit_gracefully)
        signal.signal(signal.SIGTERM, self._exit_gracefully)

        self._rdma = rdma

        self.queue = queue.Queue()

        # Turn-on the worker thread.
        threading.Thread(target=self.pollwrapper, daemon=True).start()

    def _exit_gracefully(self, *args, **kwargs):
        self.running = False

    def pollwrapper(self):
        while self.running:
            self.item = self.queue.get()
            print(self.item, 77)
            # print("c", self.item, "\n")
            result = self._rdma.call(self.item)
            print(result)
            if result == 0:
                self._exit_gracefully()
            self.queue.task_done()


    def demo(self):
        while self.running:
            msg = input()
            self.queue.put(msg)



if __name__ == "__main__":
    conn = Connection()
    conn.demo()

    args = get_args()
    if args.server:
        server()
    elif args.client:
        client(args.client)
    else:
        args.help()
    
    
    # main()