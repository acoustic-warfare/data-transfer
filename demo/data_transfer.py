#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# File: data-transfer/demo/data_transfer.py
# Author: Irreq

from itertools import zip_longest
from itertools import islice, chain, repeat
import os
import ctypes
import asyncio
import signal
import multiprocessing as mp

import argparse

from time import perf_counter as clock

import ucp

import cupy as cp

"""
Documentation
-------------
This is a benchmark of GPUDirect RDMA throughput from gpu(0) on Server A to 
gpu(0) on Server B without copying to host memory.

The goal of this test is to provide information on how data transfer can be
performed without accessing the host's memory.

This test uses the UCX-Py wrapper together with CuPy to perform GPUDirect RDMA
over Mellanox ConnectX-6 DX Network Adapters.
------------
"""

def setup(mode="gpu"):

    if mode == "gpu":
        pass
    elif mode == "cpu":
        pass
    else:
        raise RuntimeError("Inv")


mp = mp.get_context("spawn")

PROJECT_PATH = os.path.expanduser("~/data-transfer/demo/")

KERNEL_PATH = PROJECT_PATH + "raw_kernel.cu"

C_LIB = PROJECT_PATH + 'libpyrdma.so'

# Config ucp on startup {"MEMTYPE_CACHE": "y"}
ucp_setup_options = dict(TLS="ib,cma,cuda_copy,cuda,cuda_ipc")
ucp.init(ucp_setup_options)

# Only use the first GPU
cp.cuda.runtime.setDevice(0)

# data to be sent
# n_bytes = 2**24  # 1GiB
n_bytes = 115000000
n_iter = 20
# buffer = 2**25
address = "10.0.0.4"
port = 12341

server = (address, port)

reuse_alloc = True

def receive(queue, n_bytes):
    async def run():
        async def handler(endpoint):
            recv_array = []
            if not reuse_alloc:
                for _ in range(n_iter):
                    recv_array.append(cp.zeros(n_bytes, dtype="u1"))
            else:
                t = cp.zeros(n_bytes, dtype="u1")
                for _ in range(n_iter):
                    recv_array.append(t)
            assert recv_array[-1].nbytes == n_bytes

            for i in range(n_iter):
                await endpoint.recv(recv_array[i])
            await endpoint.close()
            lf.close()
    
        lf = ucp.create_listener(handler, port=port)
        queue.put(lf.port)

        while not lf.closed():
            await asyncio.sleep(0.5)

    loop = asyncio.get_event_loop()
    loop.run_until_complete(run())

def send(queue, n_bytes):
    async def run():
        endpoint = await ucp.create_endpoint(address, port)
        send_array = [] 
        if not reuse_alloc:
            for i in range(n_iter):
                send_array.append(cp.arange(n_bytes, dtype="u1"))
        else:
            t1 = cp.arange(n_bytes, dtype="u1")
            for i in range(n_iter):
                send_array.append(t1)
        assert send_array[0].nbytes == n_bytes

        times = []
        try:
            for i in range(n_iter):
                start = clock()
                await endpoint.send(send_array[i])
                stop = clock()
                times.append(stop - start)
        finally:
            queue.put(times)

    loop = asyncio.get_event_loop()
    loop.run_until_complete(run())

    times = queue.get()
    
    for i, v in enumerate(times):
        print(i, n_bytes / v / 2**30)
    print(n_iter * n_bytes / sum(times) / 2**30)


def parse_args():
    parser = argparse.ArgumentParser(description="Roundtrip benchmark")
    parser.add_argument(
        "--client",
        default=False,
        action="store_true",
        help="IP address to connect to server.",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    # server_address = args.server_address

    # if you are the server, only start the `server process`
    # if you are the client, only start the `client process`
    # otherwise, start everything

    if args.client:
        # server_address = args.client
        print(f"Client connecting to server at {address}:{port}")
        q2 = mp.Queue()
        p2 = mp.Process(target=send, args=(q2,n_bytes))
        p2.start()
        p2.join()
        assert not p2.exitcode

    else:

        # server process
        q1 = mp.Queue()
        p1 = mp.Process(target=receive, args=(q1,n_bytes))
        p1.start()
        port = q1.get()
        print(f"Server Running at {address}:{port}")
        p1.join()
        assert not p1.exitcode


# def create_chunks(arr, size_chunks):
#     """Chunk data into size"""
#     return [arr[i:i+size_chunks] for i in range(0, len(arr), size_chunks)]

# def create_data(n_bytes, chunks_bytes):
#     assert chunks_bytes <= n_bytes
#     arr = []
#     for i in range(1, n_bytes+1, chunks_bytes):
#         print(i)


# def chunk_pad(arr, size, padval=0):
#     arr = chain(iter(arr.to_list()), repeat(padval))
#     return list(iter(lambda: tuple(islice(arr, size)), (padval,) * size))


# d = cp.zeros(1040, dtype="u1")
# # a = chunk_pad(d, 32)

# # # our_list = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
# # our_list = range(1040)
# # chunk_size = 32
# # chunked_list = list(zip_longest(*[iter(our_list)]*chunk_size, fillvalue=0))
# # print(chunked_list)

# # print(list(a), d)
# n_bytes = 2**30
# chunk = 2**25
# data = []

# def create_recv_array(n_bytes, reuse_alloc, chunk=2**26):
#     data = []
#     for i in range(0, n_bytes, chunk):
#         left = n_bytes - i
#         if not reuse_alloc:
#             if left < chunk:
#                 data.append(cp.zeros(left + (chunk - left), dtype="u1"))
#             else:
#                 data.append(cp.zeros(chunk, dtype="u1"))

#         else:

        
# print(data[-1].nbytes)

# def send(queue, n_bytes):
#     [lst[i:i + n] for i in range(1, len(lst)+1, n)]



# def load_cuda_kernel(path):
#     """Load a cuda kernel as a .cu file"""
#     with open(path, "r") as kernel_file:
#         raw_kernel = "".join([i for i in kernel_file])
#         kernel_file.close()

#     kernel = cp.RawModule(code=raw_kernel)

#     return kernel

# class Communication:
#     pass


# class DataTransfer(Communication):
#     """Main class."""
#     running = True
#     def __init__(self, address=ucp.get_address(), port=12345):
#         self.address = address
#         self.port = port

#         try:
#             self.librdma = ctypes.CDLL(C_LIB)
#         except OSError:
#             print("Shared backend library could not be loaded, have you built it?\n\nmake clean\nmake\n")
#             self._exit_gracefully()

#         signal.signal(signal.SIGINT, self._exit_gracefully)
#         signal.signal(signal.SIGTERM, self._exit_gracefully)

#     def _exit_gracefully(self, *args, **kwargs):
#         self.running = False

#     def main(self):
#         while self.running:
#             resp = input("> ")
#             if resp == "exit":
#                 self._exit_gracefully()

#             result = getattr(self, resp, None)
#             if result is not None:
#                 print(result)


# if __name__ == "__main__":
#     # # a = load_cuda_kernel(KERNEL_PATH)
#     # # print(a)
#     # dt = DataTransfer()
#     # dt.main()
#     pass
