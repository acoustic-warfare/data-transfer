# cython: language_level=3
# File: data-transfer/src/main.pyx
# Author: Irreq
# Date: 05/07-2022

from libc.stdio cimport printf

import sys
import time
import queue
import signal
import ctypes
import socket
import asyncio
import argparse
import threading

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

Make sure:

# htop
htop --delay=0.2

# top
top -d 0.2 -i

# nvidia-smi
watch -n 0.2 nvidia-smi

TODO:

    - Remove unused code
    * Fix Cython not awaiting UCP coroutine in `receiver`
    + Add more documentation
"""

# Config
cdef int port = 12000
cdef unsigned long int n_bytes = 2**30

cdef int timeout = 60


class Payload(ctypes.Structure):
    """Payload C-like structure"""

    _fields_ = [("id", ctypes.c_int),
                ("protocol_version", ctypes.c_int),
                ("fs", ctypes.c_int),
                ("fs_nr", ctypes.c_int),
                ("samples", ctypes.c_int),
                ("sample_error", ctypes.c_int),
                ("bitstream", (ctypes.c_int*192))]


cdef load_init(args):
    """Namespace args"""

    # Only use the first GPU
    cp.cuda.runtime.setDevice(args.device)

    # Initiate UCX framework
    ucp_setup_options = dict(TLS=args.methods)
    try: 
        ucp.init(ucp_setup_options)
    except RuntimeError:  # Already initiated
        ucp.reset()
        ucp.init(ucp_setup_options)



## External C code
# cdef extern from "../src/hello.c":
#     void f()
#     
# cpdef myf():
#     f()

# from src import transmitter

# cdef extern from "../lib/cubridge.so":
#     void say_hello(int k)
# 
# say_hello(5)

def dummy_callback(data):
    print(f"GPUDirect RDMA Transfer: {data.n_bytes} Bytes")

cdef class PythonCudaBridge:

    """Call C or Cuda code from running Cython.
    
    Usage:
        # Load the library
        pyculib = PythonCudaBridge().load()
        # Setup a function
        f = pyculib.say_hello
        # Define a function
        f.argtypes = [ctypes.c_int]
        # Call a function
        f(5)
    """

    cdef str _shared_object  # Path to shared object 
    cdef object cubridge_lib  # Object placeholder which will contain the runtime lib

    def __init__(self, shared_object="lib/cubridge.so"):
        self._shared_object = shared_object
        self.reload()

    def reload(self):
        """Reload the shared object."""
        self.cubridge_lib = ctypes.cdll.LoadLibrary(self._shared_object)

    def load(self):
        """Return the library"""
        return self.cubridge_lib

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
    cdef unsigned long int _msg_size  # Up to 115MB

    cdef public int running  # Signal interupt
    cdef public _receive_q  # Internal queue

    def __init__(self, unsigned long int n_bytes, str address = ucp.get_address(), unsigned long int msg_size=1000):
        self._n_bytes = n_bytes
        self._address = address
        self._msg_size = msg_size

        self._receive_q = queue.Queue()

        # print(self._address, self._n_bytes)
        self.running = True

        signal.signal(signal.SIGINT, self.exit_gracefully)
        signal.signal(signal.SIGTERM, self.exit_gracefully)

    def exit_gracefully(self, *args, **kwargs):
        """Break loop on `SIGINT` or `SIGTERM`"""
        self.running = False

    def receive_handler(self, callback):
        last = time.time()
        while time.time()-last < timeout:
            for buffer in queue_rows(self._receive_q):
                callback(buffer)
                last = time.time()

            time.sleep(0.01)

    def cont_receive_from_gpu(self, port):
        print("Starting receiving end")
        async def run():
            async def handler(ep):
                while self.running:
                    try:
                        arr = cp.zeros(192, dtype="u1")
                        await ep.recv(arr)
                        #self._receive_q.put(arr)
                        #print(f"Receiving: {arr.nbytes}")
                        del arr
                    except:
                        break

                await ep.close()
                lf.close()
                print("Closing")

            lf = ucp.create_listener(handler, port=port)
            while not lf.closed():
                print("Waiting")
                await asyncio.sleep(0.5)

        loop = asyncio.get_event_loop()
        loop.run_until_complete(run())
        print("Done")

    def old_cont_transmit_from_gpu(self, port):
        print("Starting transmission from GPU to GPU")
        async def run():
            address = "10.0.0.4"
            ep = await ucp.create_endpoint(address, port)
            last = time.time()
            while time.time()-last < timeout:
                for buffer in queue_rows(self._receive_q):
                    
                    await ep.send(buffer)
                    print(f"Sent buffer: {buffer.nbytes}")
                    last = time.time()

                time.sleep(0.01)
        loop = asyncio.get_event_loop()
        loop.run_until_complete(run())

    
    def cont_transmit_from_gpu(self, port, socket_port):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        # [Errno 98] Address already in use, https://stackoverflow.com/questions/4465959/python-errno-98-address-already-in-use
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

        sock.bind(("localhost", socket_port))
        print("Waiting for a connection")
        sock.listen(1)

        csock, _ = sock.accept()
        print("Connected to incoming datastream.")
        print("Starting transmission from GPU to GPU")
        async def run():
            address = "10.0.0.4"
            ep = await ucp.create_endpoint(address, port)

            try:
                while self.running:
                    # buffer = await csock.recv(792)
                    buffer = False
                    if buffer:
                        try:
                            payload_data = Payload.from_buffer_copy(
                                buffer)
                        except ValueError:
                            print("Warning missing data")

                    #bitstream = list(payload_data.bitstream)
                    bitstream = cp.ones(192)
                    # Load the array to the gpu
                    cp_arr = cp.array(bitstream, dtype="u1")
                    await ep.send(cp_arr)
                    #print(f"Sent buffer: {cp_arr.nbytes}")
            finally:
                sock.close()

        loop = asyncio.get_event_loop()
        loop.run_until_complete(run())

    def receive_from_fpga_send_to_gpu(self, socket_port):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        # [Errno 98] Address already in use, https://stackoverflow.com/questions/4465959/python-errno-98-address-already-in-use
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

        sock.bind(("localhost", socket_port))
        print("Waiting for a connection")
        sock.listen(1)

        csock, _ = sock.accept()
        print("Connected to incoming datastream.")

        try:
            while True:
                buffer = csock.recv(792)
                if buffer:
                    try:
                        payload_data = Payload.from_buffer_copy(
                            buffer)
                    except ValueError:
                        print("Warning missing data")

                    bitstream = list(payload_data.bitstream)
                    # Load the array to the gpu
                    cp_arr = cp.array(bitstream, dtype="u1")
                    # Put a reference to the array in a queue for the transmitter
                    self._receive_q.put(cp_arr)
        finally:
            sock.close()
            


    def old_receive_from_fpga_send_to_gpu(self, socket_port):
        """Receiving end of real data."""

        class Payload(ctypes.Structure):
            """Payload C-like structure"""

            _fields_ = [("id", ctypes.c_int),
                        ("protocol_version", ctypes.c_int),
                        ("fs", ctypes.c_int),
                        ("fs_nr", ctypes.c_int),
                        ("samples", ctypes.c_int),
                        ("sample_error", ctypes.c_int),
                        ("bitstream", (ctypes.c_int*192))]

        # Initiate socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        # [Errno 98] Address already in use, https://stackoverflow.com/questions/4465959/python-errno-98-address-already-in-use
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            

        sock.bind(("localhost", socket_port))
        print("Waiting for a connection")
        sock.listen(1)

        csock, _ = sock.accept()
        print("Connected to incoming datastream.")
        try:
            while True:
                buffer = csock.recv(792)
                if buffer:
                    payload_data = Payload.from_buffer_copy(
                        buffer)

                    batch = dict(id=int(payload_data.id),
                                    protocol_version=int(
                        payload_data.protocol_version),
                        fs=int(payload_data.fs),
                        fs_nr=int(payload_data.fs_nr),
                        samples=int(payload_data.samples),
                        sample_error=int(
                                        payload_data.sample_error),
                        bitstream=list(payload_data.bitstream))

                    # Load the array to the gpu
                    cp_arr = cp.array(batch["bitstream"], dtype="u1")
                    # Put a reference to the array in a queue for the transmitter
                    self._receive_q.put(cp_arr)

        finally:
            # Close socket when stream has ended
            sock.close()


    def test(self):
        arr = cp.zeros(self._n_bytes, dtype="u1")
        print(arr)
        print(arr.nbytes)
        print(self._receive_q)
        self._receive_q.put(arr)
        self._receive_q.put(arr)
        print(1)
        for buffer in queue_rows(self._receive_q):
                print(buffer)
        print(2)
        for buffer in queue_rows(self._receive_q):
                print(buffer)
        print(3)


    def main(self):
        while self.running:
            time.sleep(1)
            printf("Hello World!\n")

    def receiver(self):
        """Receiving end for transmission."""
        
        bw_list = []

        async def run():
            # handler with connection endpoint 
            async def server_handler(ep):
                pass



def parse_args():
    import argparse
    parser = argparse.ArgumentParser(description="COTS Data Transfer")
    parser.add_argument(
        "--client",
        default=False,
        action="store_true",
        help="IP address to connect to server.",
    )
    parser.add_argument(
        "--msg-size",
        default=2**26,
        type=int,
        help="Message size in bytes",
    )
    parser.add_argument(
        "-a", "--address",
        default=ucp.get_address(),
        type=str,
        help="IP address to connect to server.",
    )
    parser.add_argument(
        "-p", "--port",
        default=12345,
        type=int,
        help="IP port to connect to server.",
    )
    parser.add_argument(
        "-sp", "--socket-port",
        default=23100,
        type=int,
        help="IP port to connect to server.",
    )
    parser.add_argument(
        "-d", "--device",
        default=0,
        type=int,
        help="GPU Index to use.",
    )
    parser.add_argument(
        "-m", "--methods",
        default="ib,cma,cuda_copy,cuda,cuda_ipc,gdr_copy",
        type=str,
        help="UCX Tx/Rx methods.",
    )
    return parser.parse_args()


async def server(port):
    bw_list = []
    async def run():
        async def server_handler(ep):
            recv_data = cp.zeros(192, dtype="u1")
            last = time.time()
            # while True:
            print("Running")
            while True:
                try:
                    
                    await ep.recv(recv_data)
                    bandwidth = (n_bytes / (time.time() - last)) / 2**30  # For GB/s
                    print(f"Continuous bandwidth: {round(bandwidth, 4)} GB/s    ", end="\r")
                    last = time.time()
                except Exception as e:
                    print(e)
                    break
            await ep.close()
            lf.close()
    
        lf = ucp.create_listener(server_handler, port=port)

        while not lf.closed():
            await asyncio.sleep(0.5)

    await run()

    


if __name__ == "__main__":
    args = parse_args()

    load_init(args)

    

    #sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    ## [Errno 98] Address already in use, https://stackoverflow.com/questions/4465959/python-errno-98-address-already-in-use
    #sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
#
    #sock.bind(("localhost", args.socket_port))
    #print("Waiting for a connection")
    #sock.listen(1)
#
    #csock, _ = sock.accept()
    #print("Connected to incoming datastream.")
#
    #try:
    #    while True:
    #        buffer = csock.recv(792)
    #        if buffer:
    #            try:
    #                payload_data = Payload.from_buffer_copy(
    #                    buffer)
    #            except ValueError:
    #                print("Valueerror")
    #                continue
#
    #            bitstream = list(payload_data.bitstream)
    #            # Load the array to the gpu
    #            cp_arr = cp.array(bitstream, dtype="u1")
    #            # Put a reference to the array in a queue for the transmitter
    #            #self._receive_q.put(cp_arr)
    #            print(cp_arr.nbytes)
    #finally:
    #    sock.close()
#
    #exit()

    if args.client:
        dt = DataTransfer(10000, msg_size=args.msg_size)
        # t1 = threading.Thread(target=dt.receive_from_fpga_send_to_gpu, args=(args.socket_port,))
        # t1.start()
        dt.cont_transmit_from_gpu(args.port, args.socket_port)
        #t1.join()

    else:
        #res = await server(args.port)
        loop = asyncio.get_event_loop()
        loop.run_until_complete(server(args.port))
        #exit()
        
        print("Server")
        #dt.test()
        #t1 = threading.Thread(target=dt.receive_handler, args=(dummy_callback,))
        #t1.start()
        #dt.cont_receive_from_gpu(args.port)
        #t1.join()