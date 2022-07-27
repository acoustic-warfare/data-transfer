# cython: language_level=3
# File: data-transfer/src/transfer_real.pyx
# Author: Irreq
# Date: 26/07-2022

import time
import queue
import socket
import signal
import ctypes
import asyncio
import argparse
import threading

import ucp

from src.common import receiver

"""
                A Real Data Transfer Demo

Usage:
    1. Run instance of receiver mode on PC B. (Default)
    2. Run instance of transmitter mode on PC A.
    3. Run data generator to PC A
    4. Run `web_gauge` on PC B

    See bandwidth in real-time on the running web server


Documentation:

            Data Flow - Transmission Mode (PC A)
+-----------------------------------------------------------+
|                                                           |
| 1. FPGA (Emulated) or device writing to socket on PC A    |
|                                                           |
| 2. PC A (Two threads)                                     |
|     First establish a connection, then:                   |
|     * (Loop 1) Socket parser                              |
|                 |                                         |
|                 +-> Fill buffer from socket in the size   |
|                 |   of `Protocol`                         |
|                 |                                         |
|                 +-> Put received data into FIFO queue     |
|                                                           |
|     * (Loop 2) RDMA Transmitter                           |
|                 |                                         |
|                 +-> Poll queue and load buffer onto GPU   |    
|                 |   (CuPy Array)                          |
|                 |                                         |
|                 +-> Write to Remote memory region         |
|                 |                                         |
|                 +-> Await write completion                |
|                                                           |
+-----------------------------------------------------------+


          Data Flow - Receiving Mode (PC B)
+-----------------------------------------------------------+
|                                                           |
| 1. PC B (Two threads)                                     |
|     First establish connection, then:                     |
|     * (Loop 1) RDMA Receiver (Python function, see: TODO) |
|                 |                                         |
|                 +-> Create empty buffer (CuPy Array) of   |
|                 |   `n_bytes` size                        |
|                 |                                         |
|                 +-> Fill buffer of received RDMA transfer |
|                 |                                         |
|                 +-> Put Buffer into a queue               |
|                                                           |
|     * (Loop 2) Receive handler                            |
|                 |                                         |
|                 +-> Poll queue and callback with received |
|                 |   buffer (Received RDMA)                |
|                 |                                         |
|                 +-> (Default Callback) Broadcast received |
|                     buffers's bandwidth to Running        |
|                     `web_gauge` server. See:              |
|                     src/web_live_gauge.pyx                |
|                                                           |
| 2. Running `web_gauge` server listening on                |
|    `--web-port` on PC B                                   |
|                                                           |
+-----------------------------------------------------------+
"""

cdef int timeout = 60
cdef str ENCODING = "utf8"

# Struct from receiving protocol
class Payload(ctypes.Structure):
    """Payload C-like structure"""

    _fields_ = [("id", ctypes.c_int),                # Transfer id, for tracking later
                ("protocol_version", ctypes.c_int),  # Debugging
                ("fs", ctypes.c_int),                # Sampling Rate (Hz)
                ("fs_nr", ctypes.c_int),             # Sample number
                ("samples", ctypes.c_int),           # Status from mic
                ("sample_error", ctypes.c_int),      # If error, and location of error
                ("bitstream", (ctypes.c_int*192))]   # The bitstream from the mic array

def setup(args):
    if args.mode == "gpu":
        import cupy as array_backend
        array_backend.cuda.runtime.setDevice(args.device)
        if args.debug:
            print("Will use GPU backend (CuPy)")
    elif args.mode == "cpu":
        import numpy as array_backend
        if args.debug:
            print("Will use CPU backend (Numpy)")

    ucp_setup_options = dict(TLS=args.methods)

    try:
        ucp.init(ucp_setup_options)
    except RuntimeError:  # Already initiated
        ucp.reset()
        ucp.init(ucp_setup_options)

    return array_backend


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


cdef class WebGaugeTransmitter:

    cdef public str address
    cdef public int port
    cdef public object sock

    def __init__(self, str address, int port):
        self.address = address
        self.port = port

        # Setup socket
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        # [Errno 98] Address already in use, https://stackoverflow.com/questions/4465959/python-errno-98-address-already-in-use
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

        self.sock.connect((self.address, self.port))

    def broadcast(self, bandwidth):
        encoded = str(bandwidth).encode(ENCODING)
        self.sock.sendto(encoded, (self.address, self.port))


cdef class DataTransfer:

    """Main data transfer class."""

    # Define variables to be accessed by function outside DataTransfer class
    cdef unsigned long int _n_bytes  # Up to 1GB
    cdef str _address  # host address
    cdef int _port  # RDMA port
    cdef int _socket_port  # Socket port
    cdef unsigned long int _msg_size  # Up to 115MB

    cdef public args  # Commandline arguments
    cdef public int running  # Signal interupt
    cdef public _receive_q  # Internal queue
    cdef public backend  # Array backend, CuPy or Numpy
    cdef public bint debug  # Debug mode
    cdef public object web_output
    cdef public str dtype
    
    cdef public unsigned long int iter
    cdef public unsigned long int faults

    def __init__(self, object args, unsigned long int n_bytes, str address=ucp.get_address(), int port=12345, unsigned long int msg_size=1000):
        self.args = args
        
        self._n_bytes = args.n_bytes
        self._address = args.address
        self._port = args.port
        self._socket_port = args.socket_port
        self._msg_size = msg_size

        self.debug = args.debug

        if not args.transmitter:  # For receiver
            self.web_output = WebGaugeTransmitter(args.web_output, args.socket_port)

        self._receive_q = queue.Queue()

        self.backend = setup(self.args)

        self.dtype = "u1"

        self.running = True
        self.iter = 0
        self.faults = 0
        
        signal.signal(signal.SIGINT, self.exit_gracefully)
        signal.signal(signal.SIGTERM, self.exit_gracefully)

    def exit_gracefully(self, *args, **kwargs):
        """Break loop on `SIGINT` or `SIGTERM`"""
        self.running = False

    def _receive_handler(self):
        """Threaded handler"""
        last = time.time()
        while time.time()-last < timeout and self.running:
            for (buffer, bandwidth) in queue_rows(self._receive_q):
                self.callback(buffer, bandwidth)
                last = time.time()
            time.sleep(0.01)

    def receiver(self):
        """Receiving end, will spawn a second thread collecting the received data
        
        TODO: 

            Needs a wrapper to a python function because cython fails to await
            See: __doc__
        """
        second_thread = threading.Thread(target=self._receive_handler)
        second_thread.start()

        # The real python function
        receiver(self._n_bytes,
                 self._port,
                 self._receive_q,
                 self.backend,
                 ucp,
                 self.dtype,
                 self.running)

        second_thread.join()

    def transmitter(self):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        # [Errno 98] Address already in use, https://stackoverflow.com/questions/4465959/python-errno-98-address-already-in-use
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

        sock.bind(("localhost", self._socket_port))
        if self.debug:
            print("Waiting for a connection")
        sock.listen(1)

        csock, _ = sock.accept()

        async def run():
            endpoint = await ucp.create_endpoint(self._address, self._port)
            
            while self.running:
                buffer = csock.recv(792)
                if buffer:
                    try:
                        payload_data = Payload.from_buffer_copy(
                            buffer)
                        bitstream = list(payload_data.bitstream)
                        # Load the array to the gpu
                        cp_arr = self.backend.array(bitstream, dtype=self.dtype)
                        
                        await endpoint.send(cp_arr)

                    except ValueError:
                        self.faults += 1
                        if self.debug:
                            print("Warning missing data")
                    
                    self.iter += 1
                    
            
            sock.close()
            print(f"Dropped Errors: {round(self.faults/self.iter, 2)}%")

        loop = asyncio.get_event_loop()
        loop.run_until_complete(run())

        

    def callback(self, arr, bw):
        """Override this function"""
        if self.debug:
            print(arr.nbytes)

        # Broadcast bandwidth to web gauge demo
        self.web_output.broadcast(bw/2**20)




def parse_args():
    parser = argparse.ArgumentParser(description="COTS Data Transfer (REAL)")
    parser.add_argument(
        "--transmitter",
        default=False,
        action="store_true",
        help="IP address to connect to server.",
    )
    parser.add_argument(
        "--debug",
        default=False,
        action="store_true",
        help="Debug mode.",
    )
    parser.add_argument(
        "--web-output",
        default=None,
        type=str,
        help="Output transfer-rate to web server.",
    )
    parser.add_argument(
        "--n-bytes",
        default=192,  # Size of data-stream coming from the real FPGA board
        type=int,
        help="Message size in bytes from FPGA",
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
        default=45550,
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
    parser.add_argument(
        "--mode",
        default="gpu",
        type=str,
        help="CPU or GPU RDMA",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    dt = DataTransfer(args, args.n_bytes)

    if args.transmitter:
        dt.transmitter()
    else:
        dt.receiver()
