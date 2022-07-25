# cython: language_level=3
# -*- coding: utf-8 -*-

# File: data-transfer/web_live_gauge.pyx
# Author: Irreq
# Date: 25/07-2022

import socket
import signal
import argparse
import threading
import subprocess

import dash
from dash import dcc, html
from dash.dependencies import Input, Output

import dash_core_components as dcc
import dash_html_components as html

import plotly.graph_objects as go


"""
Data-Transfer Live Gauge Over UDP

Run this application and access the web application prompted on running.
Default: http://127.0.0.1:8050

The app waits for an UDP connection from the running RDMA transfer test
and displays stats in an intuitive way in real-time.

Usage:
    ./web_gauge -a <IP-ADDRESS> -p <IP-PORT>
Example:
    ./web_gauge -a 81.236.100.90 -p 30000
"""

# Global Variables
value = 0
previous = value

host_address = "localhost"

try:
    host_address = subprocess.check_output(['hostname', '-s', '-I']).decode('utf-8')[:-1]
    host_address = host_address.split()[0]
except:
    host_address = "localhost"

class Connection:

    encoding = "utf8"

    time_out = 5
    timeout_count = 0
    sock = None
    next_n_bytes = 1024

    running = True

    def __init__(self, as_client=False, address="localhost", port=12348):
        self.as_client = as_client
        self.address = address
        self.port = port

        self.connect()

        if self.as_client:
            self.sock.bind((self.address, self.port))
        else:
            self.sock.connect((self.address, self.port))

        if self.is_socket_closed(self.sock):
            raise RuntimeError("Socket could not be opened...")

        signal.signal(signal.SIGINT, self.exit_gracefully)
        signal.signal(signal.SIGTERM, self.exit_gracefully)

    def exit_gracefully(self, *args, **kwargs):
        """Break loop on `SIGINT` or `SIGTERM`"""
        self.running = False

    def is_socket_closed(self, sock):
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

    def connect(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        # [Errno 98] Address already in use, https://stackoverflow.com/questions/4465959/python-errno-98-address-already-in-use
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    def poll(self):
        if self.is_socket_closed(self.sock):
            raise RuntimeError("Socket is closed")

        # data = "Nothing received for %ds." % (
        #     self.timeout_count * self.time_out)
        data = None
        self.sock.settimeout(self.time_out)
        try:
            # buffer size is 1024 bytes
            data, addr = self.sock.recvfrom(self.next_n_bytes)
            # print(data)
            try:
                decoded_data = data.decode(self.encoding)
            except Exception as e:
                print(e)
            try:
                data = eval(data)
            except ValueError:
                data = decoded_data

            self.timeout_count = 0
        except:
            self.timeout_count += 1
        self.sock.settimeout(None)

        return data

    def receive(self):
        response = None
        while response is None:
            response = self.poll()
        return response


    def broadcast(self, data):
        """The goal for this function can be described by "Mr. Boy" stackoverflow
        question:
        (https://stackoverflow.com/questions/64749467/is-there-a-standard-ipc-technique-similar-to-named-pipes-without-the-requiremen)
        "[...] be able to open a pipe and push data down it, without knowing/caring
        if there is a client. If there's no client, the data just gets discarded.
        Perhaps more a 'sink' than a pipe is a better way to describe this? The
        server doesn't handle connection attempts it just "throws the data" for
        anyone who happens to listen."
        This program utilizes: User Datagram Protocol (UDP) as a way to "broadcast"
        data to anyone or no one who is listening."""
        encoded = data.encode(self.encoding)
        self.sock.sendto(encoded, (self.address, self.port))

def parse_args():
    parser = argparse.ArgumentParser(description="Data-Transfer Throughput Gauge")
    parser.add_argument(
        "-a", "--address",
        default="localhost",
        type=str,
        help="IP address to connect to server.",
    )
    parser.add_argument(
        "-p", "--port",
        default=30000,
        type=int,
        help="IP port to connect to server.",
    )
    parser.add_argument(
        "--debug",
        default=True,
        action='store_false',
        help="IP address to connect to server.",
    )
    parser.add_argument(
        "--web-host",
        default=host_address,
        # default="localhost",
        type=str,
        help="Address for Dash Application.",
    )
    parser.add_argument(
        "-w", "--web-port",
        default=8050,
        type=int,
        help="Port for Dash Application.",
    )
    # return parser.parse_args()
    args, unknown = parser.parse_known_args()
    return args


args = parse_args()

# Initiate UDP receiver sink
com = Connection(as_client=True, address=args.address, port=args.port)

# Initiated Dash App
app = dash.Dash(__name__)
app.layout = html.Div(
    # Setup simple web app
    html.Div([
        html.H1('GPU RDMA Live Data Transfer Throughput Demo'),
        dcc.Graph(id='live-update-graph'),
        dcc.Interval(
            id='interval-component',
            interval=200,
            n_intervals=0
        )
    ])
)


def updater():
    """Polling function which runs in parallel and continuously updates
    `value`. 
    """
    try:
        while True:
            global value
            value = float(com.receive())
    except:
        com.running = False


# Multiple components can update everytime interval gets fired.
@app.callback(Output('live-update-graph', 'figure'),
              Input('interval-component', 'n_intervals'))
def update_graph_live(n):

    global previous
    
    fig = go.Figure(go.Indicator(
        domain={'x': [0, 1], 'y': [0, 1]},
        value=value,
        mode="gauge+number+delta",
        title={'text': "Real-Time Speed GB/s"},
        delta={'reference': previous},
        gauge={'axis': {'range': [None, 8.0]},
               'steps': [
            {'range': [0.0, 1.0], 'color': "lightgray"},
            {'range': [1.0, 6.0], 'color': "gray"}],
            'threshold': {'line': {'color': "red", 'width': 4}, 'thickness': 0.75, 'value': 6.0}}))
    
    previous = value
    return fig


if __name__ == '__main__':
    # Poll the server for data-transfer speed, will receive a float representing GB/s
    threading.Thread(target=updater).start()

    # Run the web-application on the specified port
    app.run_server(debug=args.debug, port=args.web_port, host=args.web_host)