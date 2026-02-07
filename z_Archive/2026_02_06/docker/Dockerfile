# pxe-pilot Docker image
FROM python:3.12-slim

WORKDIR /app

# Install dependencies
COPY pyproject.toml README.md ./
COPY src/ ./src/

RUN pip install --no-cache-dir .

# Create config directory
RUN mkdir -p /config/hosts

# Default environment
ENV CONFIG_DIR=/config
ENV HOST=0.0.0.0
ENV PORT=8080

EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

ENTRYPOINT ["pxe-pilot"]
CMD ["serve"]
