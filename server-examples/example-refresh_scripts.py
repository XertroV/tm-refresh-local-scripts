#!/usr/bin/env python3
import socket
import json
import struct
import argparse
import sys

PORT = 30005
GREEN = '\033[92m'
RED = '\033[91m'
YELLOW = '\033[93m'
GREY = '\033[90m'
RESET = '\033[0m'

_filter_patterns = []
_filtered_folders = []

def process_message(msg):
    status = msg.get("status")
    
    if status == "log":
        message = msg.get("message", "")
        prefix = f"{GREY}[ LOG]{RESET}"
        if message.startswith("WARN:"):
            prefix = f"{YELLOW}[WARN]{RESET}"
            message = message[5:].lstrip()
        elif message.startswith("Refreshed: "):
            prefix = f"{GREEN}[  OK]{RESET}"
            message = message[11:].lstrip()
        elif message.startswith("Refreshing scripts in"):
            prefix = f"{GREY}[ DIR]{RESET}"
            message = message[21:].lstrip()
        print(f" {prefix} {message}")
    elif status == "filter":
        pattern = msg.get("pattern")
        folder = msg.get("folder")
        _filter_patterns.append(pattern)
        _filtered_folders.append(folder)
    elif status == "error":
        message = msg.get("message", "")
        print(f" {RED}[ERR]{RESET} {message}", file=sys.stderr)
    elif status == "success":
        message = msg.get("message", "")
        files = msg.get('files', 'N/A')
        folders = msg.get('folders', 'N/A')
        
        if _filter_patterns:
            unique_patterns = sorted(set(_filter_patterns))
            patterns_str = ', '.join(f'"{p}"' for p in unique_patterns)
            
            print(f"\n {YELLOW}[FILTERS]{RESET} [{patterns_str}]")
            for folder in _filtered_folders:
                print(f" {folder}")
            
            _filter_patterns.clear()
            _filtered_folders.clear()

        print(f"\n {GREEN}[SUCCESS]{RESET} {message} (Files: {files}, Folders: {folders})\n")
    else:
        print(f"\n {YELLOW}[???]{RESET} Unknown message status '{status}': {msg}\n")

def send_refresh_command(DoExtra=False, DoFilter=False, DoDevTitleOnly=False):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    operation_completed_successfully = False
    
    connection_result = sock.connect_ex(("localhost", PORT))
    if connection_result != 0:
        print(f"{RED}[ERR]{RESET} Connection failed. Is the Openplanet script running?", file=sys.stderr)
        sock.close()
        return False
    
    command = {"command": "refresh", "DoExtra": DoExtra, "DoFilter": DoFilter, "DoDevTitleOnly": DoDevTitleOnly}
    command_bytes = json.dumps(command).encode('utf-8')
    sock.sendall(command_bytes)
    
    while True:
        hdr_bytes = sock.recv(4)
        if not hdr_bytes or len(hdr_bytes) < 4:
            break

        header_result = struct.unpack("<I", hdr_bytes)
        data_length = header_result[0]
        
        data_bytes = b""
        bytes_remaining = data_length
        while bytes_remaining > 0:
            chunk = sock.recv(min(4096, bytes_remaining))
            data_bytes += chunk
            bytes_remaining = data_length - len(data_bytes)
        
        message_str = data_bytes.decode('utf-8')
            
        response = json.loads(message_str)
        process_message(response)
        if response.get("status") == "success":
            operation_completed_successfully = True
    
    sock.close()
    return operation_completed_successfully

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Refresh ManiaScripts via Openplanet Socket")
    parser.add_argument("--DoExtra", action="store_true", help="Do extra refresh mode")
    parser.add_argument("--DoFilter", action="store_true", help="Filter folders based on .refreshignore")
    parser.add_argument("--DoDevTitleOnly", action="store_true", help="Only refresh title scripts in WorkTitles folder")
    args = parser.parse_args()

    if send_refresh_command(args.DoExtra, args.DoFilter, args.DoDevTitleOnly):
        sys.exit(0)
    else:
        sys.exit(1)