from libc.stdio cimport printf

import asyncio
import time
import ucp
import cupy as cp

import signal

# Config
cdef int port = 12000
cdef unsigned long int n_bytes = 2**30

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
    cdef unsigned long int _n_bytes
    # cdef char* _address[10]
    cdef str _address
    def __init__(self, unsigned long int n_bytes, str address = "localhost"):
        self._n_bytes = n_bytes
        self._address = address

        print(self._address, self._n_bytes)

    def test(self):
        arr = cp.zeros(self._n_bytes, dtype="u1")
        print(arr)
        print(arr.nbytes)


if __name__ == "__main__":
    dt = DataTransfer(port)
    dt.test()