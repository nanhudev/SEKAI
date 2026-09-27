#!/usr/bin/env python
"""Direct client for the Blender MCP addon socket on 127.0.0.1:9876.

SEKAI ART pipeline tool. Lets the Producer drive the visible Blender instance
without going through an MCP tool binding.

Protocol: send a single UTF-8 JSON object per command; the addon buffers until
it parses. Responses are JSON, possibly split across recv() chunks.

    {"type": "execute_code", "params": {"code": "import bpy; ..."}}

Usage:
    python blender_mcp_client.py scene-info
    python blender_mcp_client.py exec --file path/to/chunk.py
    python blender_mcp_client.py exec --code 'import bpy; print(len(bpy.data.objects))'
    python blender_mcp_client.py shot --out F:/SEKAI/assets_source/review/shot.png
    python blender_mcp_client.py raw '{"type":"ping","params":{}}'
"""

import argparse
import json
import socket
import sys
import time

HOST = "127.0.0.1"
PORT = 9876
RECV_TIMEOUT = 300.0  # long: a modelling chunk can rebuild geometry for a while


def send(command: dict, timeout: float = RECV_TIMEOUT) -> dict:
    payload = json.dumps(command, ensure_ascii=False).encode("utf-8")
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    try:
        sock.connect((HOST, PORT))
        sock.sendall(payload)
        buffer = b""
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                chunk = sock.recv(65536)
            except socket.timeout:
                break
            if not chunk:
                break
            buffer += chunk
            try:
                return json.loads(buffer.decode("utf-8"))
            except (json.JSONDecodeError, UnicodeDecodeError):
                # Incomplete. Keep reading.
                continue
        # Nothing parseable arrived in time.
        return {"status": "error", "message": "no parseable response (timeout or empty)"}
    finally:
        try:
            sock.close()
        except OSError:
            pass


def print_response(response: dict) -> int:
    status = response.get("status", "?")
    if status == "success":
        result = response.get("result")
        if isinstance(result, dict) and "error" in result:
            print("EXEC ERROR:\n" + str(result["error"]))
            return 1
        if isinstance(result, dict) and "output" in result:
            out = result.get("output")
            if out:
                print(out)
        print("[ok] " + str(result)[:2000] if not isinstance(result, dict) or "output" not in result else "")
        return 0
    print("[error] " + str(response.get("message", response)))
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Blender MCP direct socket client")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("scene-info", help="get_scene_info")
    sub.add_parser("addon-info", help="get_addon_info")

    p_exec = sub.add_parser("exec", help="execute_code")
    group = p_exec.add_mutually_exclusive_group(required=True)
    group.add_argument("--file", help="path to a .py file")
    group.add_argument("--code", help="inline python")

    p_shot = sub.add_parser("shot", help="get_viewport_screenshot")
    p_shot.add_argument("--out", required=True, help="output png path")

    p_raw = sub.add_parser("raw", help="send a raw JSON command")
    p_raw.add_argument("json", help="raw JSON string")

    args = parser.parse_args()

    if args.cmd == "scene-info":
        return print_response(send({"type": "get_scene_info", "params": {}}))
    if args.cmd == "addon-info":
        return print_response(send({"type": "get_addon_info", "params": {}}))

    if args.cmd == "exec":
        if args.file:
            with open(args.file, "r", encoding="utf-8") as handle:
                code = handle.read()
        else:
            code = args.code
        return print_response(send({"type": "execute_code", "params": {"code": code}}))

    if args.cmd == "shot":
        response = send({"type": "get_viewport_screenshot", "params": {"output_path": args.out}})
        return print_response(response)

    if args.cmd == "raw":
        return print_response(send(json.loads(args.json)))

    return 1


if __name__ == "__main__":
    sys.exit(main())
