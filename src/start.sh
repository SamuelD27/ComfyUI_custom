#!/usr/bin/env bash
# =============================================================================
# ComfyUI Serverless Worker Startup Script
# =============================================================================
# Based on official runpod-workers/worker-comfyui implementation.
# =============================================================================

set -e

echo "worker-comfyui: Starting ComfyUI"

# =============================================================================
# Model Download (if network volume is mounted and models are missing)
# =============================================================================
NETWORK_VOLUME="/runpod-volume"
MODELS_DIR="${NETWORK_VOLUME}/models"

download_model_if_missing() {
    local url=$1
    local dest=$2
    local name=$(basename "$dest")

    if [[ -f "$dest" ]]; then
        echo "worker-comfyui: Model exists: $name"
    else
        echo "worker-comfyui: Downloading $name..."
        mkdir -p "$(dirname "$dest")"
        wget -q --show-progress -O "$dest" "$url" || {
            echo "worker-comfyui: Failed to download $name"
            rm -f "$dest"
        }
    fi
}

if [[ -d "$NETWORK_VOLUME" ]] && [[ "${DOWNLOAD_MODELS:-true}" == "true" ]]; then
    echo "worker-comfyui: Network volume detected at $NETWORK_VOLUME"

    # Download Flux FP8 checkpoint (smallest, ~17GB)
    download_model_if_missing \
        "https://huggingface.co/Comfy-Org/flux1-dev/resolve/main/flux1-dev-fp8.safetensors" \
        "${MODELS_DIR}/checkpoints/flux1-dev-fp8.safetensors"

    echo "worker-comfyui: Model setup complete"
fi

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
