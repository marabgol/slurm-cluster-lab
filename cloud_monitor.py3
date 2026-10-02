#!/usb/bin/env python3
#
# Cloud monitoring server to get commands from Slurm to start and stop cloud nodes
#
import socket
import sys
import os
import subprocess
import signal
import stat
import json
from shlex import quote

active_nodes = 0
server_address = 'cloud_socket'
requested_nodes = set()
node_names = dict() # docker tag -> requested hostname
dcompose = sys.argv[1]

# Make sure the socket does not already exist
try:
    os.unlink(server_address)
except OSError:
    if os.path.exists(server_address):
        raise

# Create a UDS socket
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.bind(server_address)
#allow anyone to write to the socket
os.chmod(server_address, stat.S_IROTH | stat.S_IWOTH)

# Listen for incoming connections
sock.listen(1)

os.system("%s up --remove-orphans --build --scale cloud=%s --no-recreate -d" % (dcompose, active_nodes))

while True:
    connection=None
    try:
        print('waiting for a connection', file=sys.stderr)
        connection, client_address = sock.accept()
        print('new connection', file=sys.stderr)

        connection.settimeout(10)
        data = connection.recv(4096).decode('utf-8').strip()
        connection.shutdown(socket.SHUT_RD)
        print('received "%s"' % (data), file=sys.stderr)
        if data:
            op = data.split(":", 1)
            if op[0] == "stop":
                tag=node_names[op[1]]

                os.system("docker rm -f \"%s\"" % (quote(tag)))
                node_names.pop(tag, None)
                connection.sendall(b'ACK')
                active_nodes -= 1
            elif op[0] == "start":
                #increase node count by 1
                requested_nodes.add(op[1])
                active_nodes += 1
                os.system("%s up --scale cloud=%s --no-recreate -d" % (dcompose, active_nodes))
                connection.sendall(b'ACK')
            elif op[0] == "whoami":
                found=False

                # already known hash
                for requested_node, short_node in node_names.items():
                    if short_node == op[1]:
                        found=True
                        break

                if not found:
                    short_node=op[1]
                    requested_node = requested_nodes.pop()
                    node_names[requested_node]=short_node

                if requested_node:
                    print("responding: %s=%s" % (requested_node, short_node), file=sys.stderr)
                    connection.sendall(requested_node.encode('utf-8'))
                else:
                    connection.sendall(b'FAIL')

                print("Active Nodes=%s Known Nodes[%s]=%s" % (active_nodes, len(node_names), node_names), file=sys.stderr)
            else:
                connection.sendall(b'FAIL')

        connection.close()
    except socket.timeout:
        print('connection timeout', file=sys.stderr)
    except BrokenPipeError:
        print('ignoring broken pipe', file=sys.stderr)
    except KeyboardInterrupt:
        print('shutting down', file=sys.stderr)
        break;

sock.close()
os.unlink(server_address)

#stop the containers
os.system("make stop")
