# Build from the REPOSITORY ROOT:   docker build -f server/Dockerfile -t khairagarh-battle .
FROM debian:12-slim
ARG GODOT_VERSION=4.3
RUN apt-get update && apt-get install -y --no-install-recommends wget unzip ca-certificates python3 \
      libfontconfig1 libxcursor1 libxinerama1 libxi6 libxrandr2 libgl1 libasound2 \
 && rm -rf /var/lib/apt/lists/*
RUN ARCH=$(uname -m); if [ "$ARCH" = "aarch64" ]; then F=linux.arm64; else F=linux.x86_64; fi; \
    wget -q https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_${F}.zip -O /tmp/g.zip \
 && unzip -q /tmp/g.zip -d /tmp/g && mv /tmp/g/Godot_v${GODOT_VERSION}-stable_${F} /usr/local/bin/godot \
 && chmod +x /usr/local/bin/godot && rm -rf /tmp/g /tmp/g.zip
RUN useradd -m kb && mkdir /data /app && chown kb /data
COPY game /app/game
COPY admin /app/admin
COPY server/start.sh server/server_config.json /app/
RUN chown -R kb /app
USER kb
RUN godot --headless --path /app/game --import || true; godot --headless --path /app/game --import || true
ENV KB_DATA_DIR=/data
EXPOSE 7777/udp 8080/tcp
VOLUME /data
CMD ["/app/start.sh"]
