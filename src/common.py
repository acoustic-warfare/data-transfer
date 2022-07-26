import asyncio

def receiver(n_bytes, port, queue, array_backend, ucp, dtype, running):
    print(n_bytes, port, queue, array_backend, ucp, dtype, running)
    async def run():
        async def handler(endpoint):
            print(1)
            recv_data = array_backend.empty(n_bytes, dtype=dtype)
            while running:
                print(2)
                try:
                    await endpoint.recv(recv_data)
                    queue.put(recv_data)
                except:
                    break

            await endpoint.close()
            lf.close()

        print("lol")
        lf = ucp.create_listener(handler, port=port)

        while not lf.closed():
            await asyncio.sleep(0.5)
    loop = asyncio.get_event_loop()
    loop.run_until_complete(run())
