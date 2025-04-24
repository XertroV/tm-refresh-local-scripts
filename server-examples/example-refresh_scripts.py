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
    sock.settimeout(60.0)
    operation_completed_successfully = False
    try:
        sock.connect(("localhost", PORT))

        command = {"command": "refresh", "extra": DoExtra, "filter": DoFilter, "title": DoDevTitleOnly}
        command_bytes = json.dumps(command).encode('utf-8')
        sock.sendall(command_bytes)

        while True:
            hdr_bytes = sock.recv(4)
            if not hdr_bytes: break
            if len(hdr_bytes) < 4:
                print(f"{RED}[ERR]{RESET} Incomplete length header ({len(hdr_bytes)} bytes).", file=sys.stderr)
                break
            try:
                (data_length,) = struct.unpack("<I", hdr_bytes)
            except struct.error as e:
                print(f"{RED}[ERR]{RESET} Could not unpack length header: {e}", file=sys.stderr)
                break

            data_bytes = b""
            try:
                while len(data_bytes) < data_length:
                    chunk = sock.recv(min(4096, data_length - len(data_bytes)))
                    if not chunk:
                        raise ConnectionAbortedError("Connection closed unexpectedly while reading data")
                    data_bytes += chunk
            except socket.error as e:
                 print(f"{RED}[ERR]{RESET} Socket error reading data: {e}", file=sys.stderr)
                 break

            try:
                message_str = data_bytes.decode('utf-8')
                response = json.loads(message_str)
                process_message(response)
                if response.get("status") == "success":
                    operation_completed_successfully = True

            except (json.JSONDecodeError, UnicodeDecodeError) as e:
                 print(f"{RED}[ERR]{RESET} Failed to decode/parse message: {e}", file=sys.stderr)
                 print(f"{GREY} Raw data: {data_bytes!r}{RESET}", file=sys.stderr)
                 break
            except Exception as e:
                 print(f"{RED}[ERR]{RESET} Error processing message: {e}", file=sys.stderr)
                 break

    except socket.timeout:
        print(f"{RED}[ERR]{RESET} Socket timed out.", file=sys.stderr)
    except ConnectionRefusedError:
         print(f"{RED}[ERR]{RESET} Connection refused. Is the Openplanet script running?", file=sys.stderr)
    except socket.error as e:
        print(f"{RED}[ERR]{RESET} Socket Error: {e}", file=sys.stderr)
    except Exception as e:
        print(f"{RED}[ERR]{RESET} An unexpected Python error occurred: {e}", file=sys.stderr)
        # import traceback; traceback.print_exc() # Uncomment for debugging
    finally:
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