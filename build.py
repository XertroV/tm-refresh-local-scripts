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

INFO_TOML = "info.toml"
SOURCE_DIR = "src"
DIST_DIR = "dist"

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

def copy_plugin_files(src_dir, info_toml, dest_dir):
    if os.path.exists(dest_dir):
        shutil.rmtree(dest_dir)
    os.makedirs(dest_dir, exist_ok=True)
    shutil.copy2(info_toml, dest_dir)
    if os.path.isdir(src_dir):
        for item in os.listdir(src_dir):
            src_item = os.path.join(src_dir, item)
            dst_item = os.path.join(dest_dir, item)
            if os.path.isdir(src_item):
                shutil.copytree(src_item, dst_item)
            else:
                shutil.copy2(src_item, dst_item)

def send_api_request(route, data, port=30001):
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

def reload_plugin(plugin_id, plugin_type, port=30001):
    response = send_api_request("load_plugin", {
        "id": plugin_id,
        "source": "user",
        "type": plugin_type
    }, port)
    
    error_text = response.get("error", "")
    data_text = response.get("data", "")
    
    if error_text != "":
        print(f"{COLOR['RED']}{error_text}{COLOR['RESET']}")
    if data_text != "":
        print(data_text)
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
    
    plugin_id = os.path.basename(os.getcwd())
    src_dir = os.path.join(os.getcwd(), SOURCE_DIR)
    info_toml = os.path.join(os.getcwd(), INFO_TOML)
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
    op_file_path = os.path.join(dist_dir, f"{plugin_id}.op")
    dest_op_file = os.path.join(plugins_dir, f"{plugin_id}.op")
    dest_folder = os.path.join(plugins_dir, plugin_id)
    
    print(f"Building {plugin_id} as {'folder' if args.type == 'folder' else '.op file'}")
    
    if args.type == "folder":
        if os.path.exists(dest_op_file):
            print(f"Removing existing .op file: {dest_op_file}")
            os.remove(dest_op_file)
        
        print(f"Deploying as folder to: {dest_folder}")
        copy_plugin_files(src_dir, info_toml, dest_folder)
    else:
        if os.path.exists(dest_folder):
            print(f"Removing existing folder: {dest_folder}")
            shutil.rmtree(dest_folder)
        
        temp_dir = os.path.join(dist_dir, "temp")
        copy_plugin_files(src_dir, info_toml, temp_dir)
        
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
    
    if reload_plugin(plugin_id, plugin_type=plugin_type, port=port):
        print(f"{COLOR['GREEN']}Plugin reloaded successfully.{COLOR['RESET']}")
        print("Build and deployment complete!")

if __name__ == "__main__":
    main()