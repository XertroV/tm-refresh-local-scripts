#!/usr/bin/env python3
import sys
import os
import shutil
import argparse
import zipfile
import json
import struct
import socket
import platform

PLUGIN_PACK = ["src", "info.toml", "README.md"] 
DIST_DIR = "dist"
PLUGIN_ID = "refresh-local-scripts"

WINEPREFIX = "/mnt/secondary/Prefixes/ProtonGE9_25/drive_c/"

DEFAULT_PORTS = {
    "tmnext": 30000,
    "mp4": 30001,
    "turbo": 30002,
}

COLOR = {
    "GREEN": '\033[92m',
    "RED": '\033[91m',
    "YELLOW": '\033[93m',
    "GREY": '\033[90m',
    "RESET": '\033[0m'
}

def copy_plugin_files(plugin_pack, dest_dir):
    if os.path.exists(dest_dir):
        shutil.rmtree(dest_dir)
    os.makedirs(dest_dir, exist_ok=True)
    
    for item in plugin_pack:
        src_item = os.path.join(os.getcwd(), item)
        dst_item = os.path.join(dest_dir, item)
        
        if not os.path.exists(src_item):
            print(f"{COLOR['RED']}Error: Required item not found: {src_item}{COLOR['RESET']}")
            sys.exit(1)  # Exit with error code
            
        if os.path.isdir(src_item):
            shutil.copytree(src_item, dst_item)
        else:
            shutil.copy2(src_item, dst_item)

def send_api_request(route, data, port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(3.0)
    try:
        sock.connect(("localhost", port))
        request = json.dumps({
            "route": route,
            "data": data
        }).encode()
        sock.send(request)
        
        hdr_bytes = sock.recv(4)
        (data_length,) = struct.unpack("<I", hdr_bytes)
        data_bytes = b""
        while len(data_bytes) < data_length:
            chunk = sock.recv(1024)
            if not chunk:
                break
            data_bytes += chunk
        
        return json.loads(data_bytes.decode())
    except Exception as e:
        print(f"{COLOR['RED']}Error calling API: {e}{COLOR['RESET']}")
        return {"error": str(e), "data": ""}
    finally:
        sock.close()

def reload_plugin(PLUGIN_ID, plugin_type, port):
    response = send_api_request("load_plugin", {
        "id": PLUGIN_ID,
        "source": "user",
        "type": plugin_type
    }, port)
    
    log_response = send_api_request("get_data_folder", {}, port)
    data_folder = log_response.get("data", "")
    
    if data_folder:
        log_path = os.path.join(windows_to_linux_path(data_folder), "Openplanet.log")
        
        if os.path.exists(log_path):
            try:
                with open(log_path, 'r', encoding='utf-8', errors='ignore') as f:
                    lines = f.readlines()
                
                relevant_logs = []
                found_unload = False
                unload_marker = f"Unloading plugin '{PLUGIN_ID}'"
                
                for line in reversed(lines):
                    if unload_marker in line:
                        found_unload = True
                        relevant_logs.insert(0, line)
                        break
                    elif found_unload:
                        relevant_logs.insert(0, line)
                    else:
                        relevant_logs.insert(0, line)
                        if len(relevant_logs) > 30:
                            relevant_logs.pop()
                
                unloaded = False
                loaded = False
                compilation_failed = False
                
                for line in relevant_logs:
                    if f"Unloading plugin '{PLUGIN_ID}'" in line:
                        unloaded = True
                    if f"Loaded plugin '{PLUGIN_ID}'" in line or f"Loaded zipped plugin '{PLUGIN_ID}'" in line:
                        loaded = True
                    if "Script compilation failed!" in line:
                        compilation_failed = True
                
                print(f"\n{COLOR['GREY']}--- Relevant Log Output ---{COLOR['RESET']}")
                import re
                for line in relevant_logs:
                    original_line = line
                    line = line.strip()
                    
                    prefixes_to_remove = [
                        "[    ScriptEngine]",
                        "[    ScriptRuntime]",
                        f" [{PLUGIN_ID}] ",
                        " [RemoteBuild] "
                    ]
                    
                    for prefix in prefixes_to_remove:
                        if prefix in line:
                            line = line.replace(prefix, "")
                    
                    line = re.sub(r'\[\d{2}:\d{2}:\d{2}\]', '', line)
                    line = line.strip()
                    
                    if "[ERROR]" in original_line:
                        print(f"{COLOR['RED']}{line}{COLOR['RESET']}")
                    elif "[ WARN]" in original_line:
                        print(f"{COLOR['YELLOW']}{line}{COLOR['RESET']}")
                    else:
                        print(line)
                print(f"{COLOR['GREY']}--- End Log Output ---{COLOR['RESET']}\n")
                
                if unloaded and loaded:
                    if not compilation_failed:
                        print(f"{COLOR['GREEN']}Plugin deployment and reload successful.{COLOR['RESET']}")
                    if compilation_failed:
                        print(f"{COLOR['RED']}Plugin deployment completed but script compilation failed.{COLOR['RESET']}")
                
            except Exception as e:
                print(f"{COLOR['RED']}Error reading log: {e}{COLOR['RESET']}")
    
    error_text = response.get("error", "")
    return error_text == ""

def windows_to_linux_path(path):
    if platform.system() != "Linux":
        return path
        
    if not WINEPREFIX:
        print(f"{COLOR['RED']}Error: WINEPREFIX is empty but required on Linux{COLOR['RESET']}")
        sys.exit(1)
    
    prefix = os.path.normpath(WINEPREFIX)
    
    if ":" in path:
        path = path.split(":", 1)[1]
    
    path = path.replace("\\", "/").lstrip("/")
    
    return os.path.join(prefix, path)

def main():
    parser = argparse.ArgumentParser(description="Build and deploy Openplanet plugin")
    parser.add_argument("--type", choices=["folder", "op"], required=True, help="Build as folder or .op file")
    parser.add_argument("--op", choices=list(DEFAULT_PORTS.keys()), required=True, help="Target Openplanet")
    args = parser.parse_args()
    
    dist_dir = os.path.join(os.getcwd(), DIST_DIR)
    port = DEFAULT_PORTS[args.op]
    
    response = send_api_request("get_data_folder", {}, port)
    data_folder = response.get("data", "")
    
    if not data_folder:
        print(f"{COLOR['RED']}Failed to get data folder from API{COLOR['RESET']}")
        return

    base_path = windows_to_linux_path(data_folder)
    
    openplanet_log = os.path.join(base_path, "Openplanet.log")
    if not os.path.exists(openplanet_log):
        print(f"{COLOR['RED']}Error: Openplanet.log not found in {base_path}, might be an incorrect path{COLOR['RESET']}")
        sys.exit(1)
    
    plugins_dir = os.path.join(base_path, "Plugins")
        
    if not os.path.exists(plugins_dir):
        print(f"{COLOR['RED']}Plugins directory not found: {plugins_dir}{COLOR['RESET']}")
        sys.exit(1)
    
    print(f"Using plugins directory: {plugins_dir}")
    
    os.makedirs(dist_dir, exist_ok=True)
    op_file_path = os.path.join(dist_dir, f"{PLUGIN_ID}.op")
    dest_op_file = os.path.join(plugins_dir, f"{PLUGIN_ID}.op")
    dest_folder = os.path.join(plugins_dir, PLUGIN_ID)
    
    print(f"Building {PLUGIN_ID} as {'folder' if args.type == 'folder' else '.op file'}")
    
    if args.type == "folder":
        if os.path.exists(dest_op_file):
            print(f"Removing existing .op file: {dest_op_file}")
            os.remove(dest_op_file)
        
        print(f"Deploying as folder to: {dest_folder}")
        copy_plugin_files(PLUGIN_PACK, dest_folder)
    else:
        if os.path.exists(dest_folder):
            print(f"Removing existing folder: {dest_folder}")
            shutil.rmtree(dest_folder)
        
        temp_dir = os.path.join(dist_dir, "temp")
        copy_plugin_files(PLUGIN_PACK, temp_dir)
        
        with zipfile.ZipFile(op_file_path, 'w', compression=zipfile.ZIP_DEFLATED) as zipf:
            for root, _, files in os.walk(temp_dir):
                for file in files:
                    file_path = os.path.join(root, file)
                    arcname = os.path.relpath(file_path, temp_dir)
                    zipf.write(file_path, arcname)
        
        shutil.rmtree(temp_dir)
        print(f"Deploying .op file to: {dest_op_file}")
        shutil.copy2(op_file_path, dest_op_file)
    
    print(f"Reloading plugin using port {port}...")
    plugin_type = "folder" if args.type == "folder" else "zip"
    
    reload_plugin(PLUGIN_ID, plugin_type=plugin_type, port=port)

if __name__ == "__main__":
    main()