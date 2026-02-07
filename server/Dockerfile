# Stage 1: Build iPXE with embedded chain script
FROM debian:bookworm-slim AS ipxe-builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    git gcc make liblzma-dev ca-certificates libc6-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/ipxe/ipxe.git /ipxe

# Embedded script: DHCP then chain to our boot.ipxe
RUN printf '#!ipxe\ndhcp\nchain http://${next-server}:8080/boot.ipxe\n' > /ipxe/src/embed.ipxe

RUN cd ipxe/src && \
    sed -i 's/\/\/#define\ PING_CMD/#define\ PING_CMD/' config/general.h && \
    sed -i 's/\/\/#define\ IPSTAT_CMD/#define\ IPSTAT_CMD/' config/general.h && \
    sed -i 's/\/\/#define\ REBOOT_CMD/#define\ REBOOT_CMD/' config/general.h && \
    sed -i 's/\/\/#define\ POWEROFF/#define\ POWEROFF/' config/general.h

# Build BIOS and UEFI binaries
RUN cd /ipxe/src && make -j$(nproc) bin/undionly.kpxe EMBED=embed.ipxe
RUN cd /ipxe/src && make -j$(nproc) bin-x86_64-efi/ipxe.efi EMBED=embed.ipxe

# Stage 2: Server image
FROM python:3.12-alpine

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY server.py .

# Copy iPXE binaries from builder stage
COPY --from=ipxe-builder /ipxe/src/bin/undionly.kpxe /app/ipxe/undionly.kpxe
COPY --from=ipxe-builder /ipxe/src/bin-x86_64-efi/ipxe.efi /app/ipxe/ipxe.efi

EXPOSE 8080 69/udp

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')"]

CMD ["python", "server.py"]
