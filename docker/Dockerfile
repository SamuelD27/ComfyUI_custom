# =============================================================================
# ComfyUI Serverless Worker - RunPod Deployment
# =============================================================================
# Aligned with official runpod-workers/worker-comfyui implementation.
#
# Build:
#   docker build --platform linux/amd64 -t <user>/comfyui-serverless:latest .
#
# Build with models baked in:
#   docker build --platform linux/amd64 --build-arg MODEL_TYPE=flux1-dev-fp8 \
#     --build-arg HUGGINGFACE_ACCESS_TOKEN=hf_xxx -t <user>/comfyui-serverless:flux .
#
# Push:
#   docker push <user>/comfyui-serverless:latest
# =============================================================================

ARG BASE_IMAGE=nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

# =============================================================================
# Stage 1: Base image with ComfyUI and dependencies
# =============================================================================
FROM ${BASE_IMAGE} AS base

# Build arguments
ARG COMFYUI_VERSION=latest
ARG PYTORCH_VERSION=2.2.0
ARG CUDA_VERSION=cu121

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_PREFER_BINARY=1
ENV PYTHONUNBUFFERED=1

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3.11-venv \
    python3-pip \
    git \
    wget \
    curl \
    ffmpeg \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    && ln -sf /usr/bin/python3.11 /usr/bin/python \
    && ln -sf /usr/bin/python3.11 /usr/bin/python3 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

# Upgrade pip and install build tools
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# Install PyTorch with CUDA support
RUN pip install --no-cache-dir \
    torch==${PYTORCH_VERSION} \
    torchvision \
    torchaudio \
    --index-url https://download.pytorch.org/whl/${CUDA_VERSION}

# Clone ComfyUI
WORKDIR /comfyui
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git . && \
    pip install --no-cache-dir -r requirements.txt

# Install essential custom nodes
WORKDIR /comfyui/custom_nodes
RUN git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git && \
    pip install --no-cache-dir -r ComfyUI-Manager/requirements.txt || true

# Prune git directories
RUN find /comfyui -name .git -type d -prune -exec rm -rf {} + 2>/dev/null || true

# Go back to root
WORKDIR /

# Install Python runtime dependencies
RUN pip install --no-cache-dir runpod~=1.7.12 requests websocket-client

# Support for network volume model paths
COPY src/extra_model_paths.yaml /comfyui/extra_model_paths.yaml

# Add handler and startup script
COPY serverless_worker.py /serverless_worker.py
COPY src/start.sh /start.sh
COPY test_input.json /test_input.json
RUN chmod +x /start.sh

# Create model directories
RUN mkdir -p /comfyui/models/checkpoints \
    /comfyui/models/clip \
    /comfyui/models/clip_vision \
    /comfyui/models/controlnet \
    /comfyui/models/diffusion_models \
    /comfyui/models/embeddings \
    /comfyui/models/loras \
    /comfyui/models/unet \
    /comfyui/models/upscale_models \
    /comfyui/models/vae \
    /comfyui/input \
    /comfyui/output

# Default command
CMD ["/start.sh"]

# =============================================================================
# Stage 2: Download models (optional)
# =============================================================================
FROM base AS downloader

ARG HUGGINGFACE_ACCESS_TOKEN
ARG MODEL_TYPE=none

WORKDIR /comfyui

# Download models based on MODEL_TYPE
RUN if [ "$MODEL_TYPE" = "flux1-dev-fp8" ]; then \
      echo "Downloading Flux1-dev-fp8 checkpoint..." && \
      wget -q -O models/checkpoints/flux1-dev-fp8.safetensors \
        https://huggingface.co/Comfy-Org/flux1-dev/resolve/main/flux1-dev-fp8.safetensors; \
    fi

RUN if [ "$MODEL_TYPE" = "flux1-dev" ] && [ -n "$HUGGINGFACE_ACCESS_TOKEN" ]; then \
      echo "Downloading Flux1-dev models..." && \
      wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" \
        -O models/unet/flux1-dev.safetensors \
        https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors && \
      wget -q -O models/clip/clip_l.safetensors \
        https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors && \
      wget -q -O models/clip/t5xxl_fp8_e4m3fn.safetensors \
        https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors && \
      wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" \
        -O models/vae/ae.safetensors \
        https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors; \
    fi

RUN if [ "$MODEL_TYPE" = "sdxl" ]; then \
      echo "Downloading SDXL models..." && \
      wget -q -O models/checkpoints/sd_xl_base_1.0.safetensors \
        https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors && \
      wget -q -O models/vae/sdxl_vae.safetensors \
        https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors; \
    fi

# =============================================================================
# Stage 3: Final image (copy models from downloader if any were downloaded)
# =============================================================================
FROM base AS final

# Copy models from downloader stage (will be empty if MODEL_TYPE=none)
COPY --from=downloader /comfyui/models /comfyui/models
