#!/usr/bin/env bash
# =============================================================================
# ComfyUI Serverless Worker Startup Script
# =============================================================================
# Based on official runpod-workers/worker-comfyui implementation.
# =============================================================================

set -e

echo "worker-comfyui: Starting ComfyUI"

# Allow operators to tweak verbosity; default is DEBUG
: "${COMFY_LOG_LEVEL:=DEBUG}"

# Serve the API locally (for development/testing)
if [ "$SERVE_API_LOCALLY" == "true" ]; then
    echo "worker-comfyui: Starting ComfyUI server..."
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata --listen --verbose "${COMFY_LOG_LEVEL}" --log-stdout &

    echo "worker-comfyui: Starting RunPod Handler with local API..."
    python -u /serverless_worker.py --rp_serve_api --rp_api_host=0.0.0.0
else
    # Normal serverless mode: ComfyUI starts on-demand from handler
    echo "worker-comfyui: Starting RunPod Handler"
    python -u /serverless_worker.py
fi
