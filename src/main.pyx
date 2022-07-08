# File: data-transfer/src/main.pyx
# Author: Irreq
# Date: 05/07-2022

from libc.stdio cimport printf

import sys
import time
import queue
import signal
import asyncio
import argparse
import threading

from time import perf_counter as clock

import ucp
import cupy as cp

from src import ethernet

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

Make sure:

# htop
htop --delay=0.2

# top
top -d 0.2 -i

# nvidia-smi
watch -n 0.2 nvidia-smi
"""

ucp_setup_options = dict(TLS="ib,cma,cuda_copy,cuda,cuda_ipc")
ucp.init(ucp_setup_options)

# Only use the first GPU
cp.cuda.runtime.setDevice(0)

# Config
cdef int port = 12000
cdef unsigned long int n_bytes = 2**30


## External C code
# cdef extern from "../src/hello.c":
#     void f()
#     
# cpdef myf():
#     f()

# from src import transmitter


class read_from_q:
    def __init__(self, q, block=False, timeout=None):
        """
         :param Queue.Queue q:
         :param bool block:
         :param timeout:
        """
        self.q = q
        self.block = block
        self.timeout = timeout

    def __enter__(self):
        return self.q.get(self.block, self.timeout)

    def __exit__(self, _type, _value, _traceback):
        self.q.task_done()


def queue_rows(q, block=False, timeout=None):
    """
     :param Queue.Queue q:
     :param bool block:
     :param int timeout:
    """
    while not q.empty():
        with read_from_q(q, block, timeout) as row:
            yield row


def callback(data):
    print(data.nbytes)
    pass



class GracefulInterruptHandler(object):
    def __init__(self, signals=(signal.SIGINT, signal.SIGTERM)):
        self.signals = signals
        self.original_handlers = {}

    def __enter__(self):
        self.interrupted = False
        self.released = False

        for sig in self.signals:
            self.original_handlers[sig] = signal.getsignal(sig)
            signal.signal(sig, self.handler)

        return self

    def handler(self, signum, frame):
        self.release()
        self.interrupted = True

    def __exit__(self, type, value, tb):
        self.release()

    def release(self):
        if self.released:
            return False

        for sig in self.signals:
            signal.signal(sig, self.original_handlers[sig])

        self.released = True
        return True

cdef class DataTransfer:
    """Main data transfer class."""

    # Define variables to be accessed by function outside DataTransfer class
    cdef unsigned long int _n_bytes  # Up to 1GB
    cdef str _address  # host address

    cdef public int running  # Signal interupt
    cdef public _receive_q  # Internal queue

    def __init__(self, unsigned long int n_bytes, str address = "localhost"):
        self._n_bytes = n_bytes
        self._address = address

        self._receive_q = queue.Queue()

        # print(self._address, self._n_bytes)
        self.running = True

        signal.signal(signal.SIGINT, self.exit_gracefully)
        signal.signal(signal.SIGTERM, self.exit_gracefully)

    def exit_gracefully(self, *args, **kwargs):
        """Break loop on `SIGINT` or `SIGTERM`"""
        self.running = False

    def receive_handler(self, callback, timeout=10):
        last = time.time()
        while time.time()-last < timeout:
            for buffer in queue_rows(self._receive_q):
                callback(buffer)
                last = time.time()

            time.sleep(0.01)

    def cont_receive_from_gpu(self):
        async def run():
            async def handler(ep):
                while self.running:
                    try:
                        arr = cp.zeros(192, dtype="u1")
                        await ep.recv(arr)
                        self._receive_q.put(arr)
                        del arr
                    except:
                        break

                await ep.close()
                lf.close()

            lf = ucp.create_listener(handler, port=12341)
            while not lf.closed():
                await asyncio.sleep(0.5)

        loop = asyncio.get_event_loop()
        loop.run_until_complete(run())

    def test(self):
        # arr = cp.zeros(self._n_bytes, dtype="u1")
        # print(arr)
        # print(arr.nbytes)
        print(self._receive_q)

    def main(self):
        while self.running:
            time.sleep(1)
            printf("Hello World!\n")



if __name__ == "__main__":
    # print(sys.argv)

    dt = DataTransfer(10000, address="10.0.0.4")
    dt.test()
    # dt.main()