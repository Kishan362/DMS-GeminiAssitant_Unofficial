#!/usr/bin/env python3
import sys
import os
import json
import mimetypes
import base64

if len(sys.argv) < 2:
    sys.exit(1)

file_path = os.path.abspath(sys.argv[1])
if not os.path.isfile(file_path):
    sys.exit(1)

# Format human-readable file size
size_bytes = os.path.getsize(file_path)
if size_bytes < 1024:
    size_str = f"{size_bytes} B"
elif size_bytes < 1024 * 1024:
    size_str = f"{size_bytes / 1024:.1f} KB"
else:
    size_str = f"{size_bytes / (1024 * 1024):.1f} MB"

filename = os.path.basename(file_path)
mime_type, _ = mimetypes.guess_type(file_path)

# Fallback for Linux configs, scripts, and code files that mimetypes misses
text_extensions = (
    '.kdl', '.conf', '.sh', '.bash', '.zsh', '.fish',
    '.py', '.qml', '.json', '.toml', '.yaml', '.yml',
    '.txt', '.log', '.md', '.c', '.cpp', '.h', '.rs',
    '.go', '.js', '.ts', '.html', '.css', '.ini'
)

if not mime_type:
    if filename.lower().endswith(text_extensions):
        mime_type = "text/plain"
    else:
        mime_type = "application/octet-stream"

# Encode file content to Base64
with open(file_path, "rb") as f:
    raw_bytes = f.read()
    b64_data = base64.b64encode(raw_bytes).decode("utf-8")

is_image = mime_type.startswith("image/")
image_url = f"file://{file_path}" if is_image else ""

payload = {
    "name": filename,
    "size": size_str,
    "mime": mime_type,
    "isImage": is_image,
    "imagePath": image_url,
    "b64": b64_data
}

# Write atomic JSON package for QML to consume
output_path = "/tmp/dms_gemini_attach.json"
with open(output_path, "w", encoding="utf-8") as out:
    json.dump(payload, out, ensure_ascii=False)
    out.flush()
    os.fsync(out.fileno())

sys.exit(0)