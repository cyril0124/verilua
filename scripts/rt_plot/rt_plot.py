import socket
import threading
import matplotlib.pyplot as plt
import time
import re
import argparse
import sys

parser = argparse.ArgumentParser(description='')
parser.add_argument('--domain', '-d', dest="domain", type=str, help='socket domain')
parser.add_argument('--port', '-p', dest="port", type=str, help='socket port')
parser.add_argument('--xlabel', '-x', dest="xlabel", type=str, help='x label of the fig')
parser.add_argument('--ylabel', '-y', dest="ylabel", type=str, help='y label of the fig')
parser.add_argument('--title', '-t', dest="title", type=str, help='title of the fig')
parser.add_argument('--avg_interval', '-i', dest="avg_interval", type=str, help='title of the fig')
args = parser.parse_args()


socket_domain = args.domain and args.domain or "localhost"
socket_port = args.port and int(args.port) or 12345
xlabel = args.xlabel
ylabel = args.ylabel
title = args.title
avg_interval = args.avg_interval and int(args.avg_interval) or 100

data_list = []
pattern = re.compile(r"<(\w+):(-?\d+(\.\d+)?)>")

def server_thread():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind((socket_domain, socket_port))
    server.listen(1)
    print(f"Start listening on {socket_domain}:{socket_port}...", flush=True)

    while True:
        client, addr = server.accept()

        cnt = 0
        while True:
            try:
                data = client.recv(1024)
                if data:
                    recv_data = data.decode()
                    
                    # Format: <[your var name]:[your var val]>
                    #      Start with '<', end with '>', var and val are seperated by ':'
                    matches = re.findall(pattern, recv_data)
                    for match in matches:
                        var_name, val, _ = match
                        data_list.append(float(val))
                        # print(f"[{cnt}] get: {var_name}={val}")
                        cnt = cnt + 1
                    print(">> " + recv_data, end="")
                    sys.stdout.flush()
                else:
                    break
            except Exception as e:
                print(e)
                break

        client.close()
    server.close()

server_thread = threading.Thread(target=server_thread)
server_thread.start()


plt.ion()
plt.style.use('fast')
fig, ax = plt.subplots(figsize=(12, 5))
ax.grid(True, linestyle='--')
fig.patch.set_facecolor('white')

x, y = [], []
y_min = 0
y_max = 1
line, = ax.plot(x, y, linewidth=1, color='blue')

y_avg = []
line_avg, = ax.plot(x, y_avg, linewidth=1, color='red')

if title != None:
    ax.set_title(title, fontsize=20)
if xlabel != None:
    ax.set_xlabel(xlabel, fontsize=16)
if ylabel != None:
    ax.set_ylabel(ylabel, fontsize=16)

annotation = ax.annotate("", (0, 0), color='blue')
annotation_avg = ax.annotate("", (0, 0), color='red')

while True:
    if data_list:
        y_data = data_list.pop(0)

        y.append(y_data)
        x.append(len(x))

        avg = sum(y[-1*avg_interval:]) / len(y[-1*avg_interval:])
        y_avg.append(avg)

        line.set_xdata(x)
        line.set_ydata(y)

        line_avg.set_xdata(x)
        line_avg.set_ydata(y_avg)

        y_min = min(y_min, y_data)
        y_max = max(y_max, y_data)
        ax.set_ylim(y_min, y_max)
        ax.set_xlim(0, len(x))

        # Remove the old annotation
        annotation.remove()
        annotation_avg.remove()

        # Add a new annotation for the latest point
        annotation = ax.annotate(f"Latest: {y_data:.4f}", (len(x), y_data), color='blue')
        annotation_avg = ax.annotate(f"Average: {avg:.4f}", (len(x), avg), color='red')

        # ax.fill_between(x, y, color='skyblue', alpha=0.3)
    # fig.canvas.draw()
    # plt.pause(0.0001)
    fig.canvas.draw_idle()
    fig.canvas.flush_events()

server_thread.join()
