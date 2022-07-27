# cython: language_level=3
# File: data-transfer/src/transfer_synthetic.pyx
# Author: Irreq
# Date: 26/07-2022

import time
import queue
import socket
import signal
import asyncio
import argparse
import threading

import ucp

from src.common import receiver

"""
                A Synthetic Data Transfer Demo

"""

cdef int timeout = 60
cdef str ENCODING = "utf8"

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
        async def run():
            endpoint = await ucp.create_endpoint(self._address, self._port)
            # Allocate _n_bytes ones
            bitstream = self.backend.ones(self._n_bytes, dtype=self.dtype)
            while self.running:
                try:
                    # Send bitstream
                    await endpoint.send(bitstream)
                except:
                    break

        loop = asyncio.get_event_loop()
        loop.run_until_complete(run())

        

    def callback(self, arr, bw):
        """Override this function"""
        if self.debug:
            print(arr.nbytes)

        # Broadcast bandwidth to web gauge demo
        self.web_output.broadcast(bw/2**30)




def parse_args():
    parser = argparse.ArgumentParser(description="COTS Data Transfer (SYNTHETIC)")
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
        default=2**26,
        type=int,
        help="Message size in bytes",
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
