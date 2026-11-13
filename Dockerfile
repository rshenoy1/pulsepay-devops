# --- Stage 1: Builder ---
FROM python:3.12-slim AS builder

WORKDIR /build
COPY app/requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# --- Stage 2: Production Runtime ---
FROM python:3.12-slim

# Security Best Practice: Create a dedicated non-root user
RUN useradd --create-home --shell /bin/bash appuser

WORKDIR /app

# Copy only compiled dependencies from the builder stage
COPY --from=builder /install /usr/local
COPY app/ ./app/

# Transfer ownership and switch to non-root user
RUN chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

# Container-level healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
