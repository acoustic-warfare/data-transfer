#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# File: data-transfer/src/ethernet.py
# Author: Irreq
# Date: 05/07-2022

import socket
import ctypes
import queue

"""Data receiver from FPGA dummy."""


class Payload(ctypes.Structure):
    """Payload C-like structure"""

    _fields_ = [("id", ctypes.c_int),
                ("protocol_version", ctypes.c_int),
                ("fs", ctypes.c_int),
                ("fs_nr", ctypes.c_int),
                ("samples", ctypes.c_int),
                ("sample_error", ctypes.c_int),
                ("bitstream", (ctypes.c_int*192))]


class PollQueue:
    """Poll a queue and return task_done on completion."""

    def __init__(self, q, block=False, timeout=None):
        self.q = q
        self.block = block
        self.timeout = timeout

    def __enter__(self):
        return self.q.get(self.block, self.timeout)

    def __exit__(self, _type, _value, _traceback):
        self.q.task_done()


class EthernetFIFO:
    """Ethernet FIFO for data-transfer"""
    time_out = 5
    time_out_count = 0
    running = True

    def __init__(self, n_bytes=792, address=socket.gethostname(), port=2300):
        self._n_bytes = n_bytes
        self._address = address
        self._port = port

        self.sock = self._setup()
        self.fifo = queue.Queue()

    def _setup(self):
        """Setup the socket"""
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        # [Errno 98] Address already in use, https://stackoverflow.com/questions/4465959/python-errno-98-address-already-in-use
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        return sock
    
    def _is_socket_closed(self, sock):
        """Determine if the socket is closed by peaking."""
        try:
            # Will try to read bytes without blocking and also without removing them from buffer (peek only)
            data = sock.recv(16, socket.MSG_DONTWAIT | socket.MSG_PEEK)
            if len(data) == 0:
                return True
        except BlockingIOError:
            return False  # Socket is open and reading from it would block
        except ConnectionResetError:
            return True  # Socket was closed for some other reason
        except:
            return True
        return False

    def _loop(self):
        """Receive data from socket and put into fifo."""
        try:
            self.sock.bind((self._address, self._port))
            self.sock.listen(1)
            csock, _ = self.sock.accept()
            while self.running:
                buffer = csock.recv(self._n_bytes)
                if buffer:
                    payload_data = Payload.from_buffer_copy(buffer)

                    batch = dict(id=int(payload_data.id),
                                 protocol_version=int(payload_data.protocol_version),
                                 fs=int(payload_data.fs),
                                 fs_nr=int(payload_data.fs_nr),
                                 samples=int(payload_data.samples),
                                 sample_error=int(payload_data.sample_error),
                                 bitstream=list(payload_data.bitstream))
                    self.fifo.put(batch)
                
                else:
                    break
        finally:
            self.sock.close()

    def poll(self, block=False, timeout=1):
        """Poll the queue"""
        def _parser():
            while not self.fifo.empty():
                with PollQueue(self.fifo, block, timeout) as data:
                    yield data

        return [data for data in _parser()]
