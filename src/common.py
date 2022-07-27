#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# File: data-transfer/src/common.py
# Author: Irreq
# Date: 26/07-2022

import time
import asyncio

def receiver(n_bytes, port, queue, array_backend, ucp, dtype, running):
    """A python receiver for cython. Cython does not await UCP on the receiving
    end so a callable python module is used instead."""
    async def run():
        async def handler(endpoint):
            # Create an empty buffer of n_bytes size
            recv_data = array_backend.empty(n_bytes, dtype=dtype)
            last = time.time()
            while running:  # Bool
                try:
                    await endpoint.recv(recv_data)  # Fill buffer with received data
                    bandwidth = (n_bytes / (time.time() - last) / 2**20)  # For GB/s
                    queue.put((recv_data, bandwidth))  # Put data to a callback queue
                    last = time.time()
                except:
                    break
            
            # Gracefully quit connection after loop
            await endpoint.close()
            lf.close()

        # Initiate a connection to sender
        lf = ucp.create_listener(handler, port=port)

        # Loop when listener is open
        while not lf.closed():
            await asyncio.sleep(0.5)

    loop = asyncio.get_event_loop()
    loop.run_until_complete(run())
