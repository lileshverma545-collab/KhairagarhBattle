#!/bin/sh
# Starts the Admin Panel (port 8080, TCP) and the game server (port 7777, UDP) in one container.
mkdir -p /data
[ -f /data/server_config.json ] || cp /app/server_config.json /data/server_config.json
python3 /app/admin/admin_server.py serve &
exec godot --headless --path /app/game -- --server
