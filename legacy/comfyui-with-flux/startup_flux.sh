#!/bin/bash
# =============================================================================
# ComfyUI + Flux Model Download Script
# =============================================================================
# This script downloads Flux models at runtime. It is designed to be called
# by the main start.sh script when DOWNLOAD_FLUX=true.
#
# Required environment variables:
#   HF_TOKEN - Hugging Face token with access to gated repos
#
# Optional environment variables:
#   DOWNLOAD_FLUX=true           - Download core Flux models
#   DOWNLOAD_FLUX_IPADAPTER=true - Download IP-Adapter models
#   DOWNLOAD_FLUX_PULID=true     - Download PuLID models
#   DOWNLOAD_FLUX_CONTROLNETS=true - Download ControlNet models
#   DOWNLOAD_FLUX_LORAS=true     - Download additional LoRA models
# =============================================================================

set -euo pipefail

# =============================================================================
# Color codes for output
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

# =============================================================================
# Configuration
# =============================================================================
COMFYUI_DIR="${COMFYUI_DIR:-/ComfyUI}"

# Check if any downloads are requested
ANY_DOWNLOAD=false
if [[ "${DOWNLOAD_FLUX}" == "true" ]] || \
   [[ "${DOWNLOAD_FLUX_IPADAPTER}" == "true" ]] || \
   [[ "${DOWNLOAD_FLUX_PULID}" == "true" ]] || \
   [[ "${DOWNLOAD_FLUX_CONTROLNETS}" == "true" ]] || \
   [[ "${DOWNLOAD_FLUX_LORAS}" == "true" ]]; then
    ANY_DOWNLOAD=true
fi

# Exit early if no downloads requested
if [[ "${ANY_DOWNLOAD}" != "true" ]]; then
    log_info "No Flux model downloads requested. Set DOWNLOAD_FLUX=true to enable."
    exit 0
fi

# =============================================================================
# Validate HF_TOKEN for gated downloads
# =============================================================================
if [[ "${DOWNLOAD_FLUX}" == "true" ]]; then
    if [[ -z "${HF_TOKEN}" ]]; then
        log_error "HF_TOKEN is required for Flux model downloads."
        log_error "Set the HF_TOKEN environment variable and try again."
        log_error "Get a token at: https://huggingface.co/settings/tokens"
        exit 1
    fi

    # Validate token format (basic check)
    if [[ ! "${HF_TOKEN}" =~ ^hf_ ]]; then
        log_warn "HF_TOKEN doesn't start with 'hf_' - may be invalid"
    fi

    # Login to HuggingFace
    log_info "Logging into Hugging Face..."
    if ! huggingface-cli login --token "${HF_TOKEN}" 2>/dev/null; then
        log_error "Failed to login to Hugging Face. Check your token."
        exit 1
    fi
fi

# =============================================================================
# Download function with retry logic
# =============================================================================
download_file() {
    local url=$1
    local dest=$2
    local filename=$(basename "$dest")
    local auth_header=""

    # Add auth header for gated repos
    if [[ -n "${HF_TOKEN}" ]]; then
        auth_header="--header=Authorization: Bearer ${HF_TOKEN}"
    fi

    # Skip if already exists and has content
    if [[ -f "$dest" ]] && [[ -s "$dest" ]]; then
        log_info "Skipping ${filename} (already exists)"
        return 0
    fi

    # Ensure directory exists
    mkdir -p "$(dirname "$dest")"

    log_info "Downloading ${filename}..."

    # Retry logic
    for attempt in 1 2 3; do
        if wget -q --show-progress --progress=bar:force:noscroll \
            ${auth_header} \
            -O "$dest" "$url" 2>&1; then

            # Verify file was downloaded and has content
            if [[ -f "$dest" ]] && [[ -s "$dest" ]]; then
                # Check it's not an HTML error page
                if file "$dest" | grep -q "HTML"; then
                    log_warn "Downloaded HTML instead of model (attempt ${attempt}/3)"
                    rm -f "$dest"
                else
                    log_info "Downloaded ${filename}"
                    return 0
                fi
            fi
        fi

        log_warn "Download attempt ${attempt}/3 failed for ${filename}"
        rm -f "$dest"
        sleep 3
    done

    log_error "Failed to download ${filename} after 3 attempts"
    return 1
}

# =============================================================================
# Download Core Flux Models
# =============================================================================
if [[ "${DOWNLOAD_FLUX}" == "true" ]]; then
    log_step "Downloading Core Flux Models"

    # Flux VAE
    download_file \
        "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors?download=true" \
        "${COMFYUI_DIR}/models/vae/ae.sft"

    # Flux Diffusion Model (~23GB)
    download_file \
        "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors?download=true" \
        "${COMFYUI_DIR}/models/diffusion_models/flux1-dev.sft"

    # Flux Kontext (optional)
    download_file \
        "https://huggingface.co/black-forest-labs/FLUX.1-Kontext-dev/resolve/main/flux1-kontext-dev.safetensors?download=true" \
        "${COMFYUI_DIR}/models/diffusion_models/flux1-kontext-dev.safetensors" || true
fi

# =============================================================================
# Download IP-Adapter Models
# =============================================================================
if [[ "${DOWNLOAD_FLUX_IPADAPTER}" == "true" ]]; then
    log_step "Downloading IP-Adapter Models"

    download_file \
        "https://huggingface.co/InstantX/FLUX.1-dev-IP-Adapter/resolve/main/ip-adapter.bin?download=true" \
        "${COMFYUI_DIR}/models/ipadapter/FLUX.1-dev-IP-Adapter.bin"

    download_file \
        "https://huggingface.co/google/siglip-so400m-patch14-384/resolve/main/model.safetensors?download=true" \
        "${COMFYUI_DIR}/models/clip_vision/sigclip_vision_patch14_384.safetensors"
fi

# =============================================================================
# Download PuLID Models
# =============================================================================
if [[ "${DOWNLOAD_FLUX_PULID}" == "true" ]]; then
    log_step "Downloading PuLID Models"

    download_file \
        "https://huggingface.co/guozinan/PuLID/resolve/main/pulid_flux_v0.9.1.safetensors?download=true" \
        "${COMFYUI_DIR}/models/pulid/pulid_flux_v0.9.1.safetensors"

    download_file \
        "https://huggingface.co/QuanSun/EVA-CLIP/resolve/main/EVA02_CLIP_L_336_psz14_s6B.pt?download=true" \
        "${COMFYUI_DIR}/models/pulid/EVA02_CLIP_L_336_psz14_s6B.pt"
fi

# =============================================================================
# Download ControlNet Models
# =============================================================================
if [[ "${DOWNLOAD_FLUX_CONTROLNETS}" == "true" ]]; then
    log_step "Downloading ControlNet Models"

    download_file \
        "https://huggingface.co/Shakker-Labs/FLUX.1-dev-ControlNet-Union-Pro-2.0/resolve/main/diffusion_pytorch_model.safetensors?download=true" \
        "${COMFYUI_DIR}/models/controlnet/flux_controlnet_union_pro_2.0.safetensors"

    download_file \
        "https://huggingface.co/InstantX/FLUX.1-dev-Controlnet-Union/resolve/main/diffusion_pytorch_model.safetensors?download=true" \
        "${COMFYUI_DIR}/models/controlnet/flux_controlnet_union_instantx.safetensors"

    download_file \
        "https://huggingface.co/jasperai/Flux.1-dev-Controlnet-Upscaler/resolve/main/diffusion_pytorch_model.safetensors?download=true" \
        "${COMFYUI_DIR}/models/controlnet/flux_controlnet_upscaler_jasperai.safetensors"
fi

# =============================================================================
# Download Additional LoRA Models
# =============================================================================
if [[ "${DOWNLOAD_FLUX_LORAS}" == "true" ]]; then
    log_step "Downloading Additional LoRA Models"

    download_file \
        "https://huggingface.co/strangerzonehf/Flux-Super-Realism-LoRA/resolve/main/super-realism-lora.safetensors?download=true" \
        "${COMFYUI_DIR}/models/loras/flux_super_realism_lora.safetensors"
fi

# =============================================================================
# Download Upscaler
# =============================================================================
log_step "Downloading Upscaler Models"

download_file \
    "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth?download=true" \
    "${COMFYUI_DIR}/models/upscale_models/4x-UltraSharp.pth" || true

# =============================================================================
# Summary
# =============================================================================
log_step "Download Complete"
log_info "Flux model downloads finished."
log_info "Models are stored in: ${COMFYUI_DIR}/models/"
