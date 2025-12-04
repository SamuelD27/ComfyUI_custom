#!/bin/bash
set -euo pipefail

# =============================================================================
# Download Models from Cloudflare R2
# =============================================================================
# Fast model downloads from R2 (no HF token required!)
# Called by startup script on RunPod.
# =============================================================================

# R2 Configuration (public read or use RunPod secret MASUKA)
R2_ENDPOINT="https://e6b3925ef3896465b73c442be466db90.r2.cloudflarestorage.com"
R2_BUCKET="comfyui-models"

# ComfyUI paths
COMFYUI_DIR="${COMFYUI_DIR:-/ComfyUI}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

# Minimum file size for validation (50MB)
MIN_MODEL_SIZE=$((50 * 1024 * 1024))

# Configure AWS CLI for R2 if credentials are available
setup_r2_cli() {
    if [[ -n "${R2_ACCESS_KEY_ID:-}" ]] && [[ -n "${R2_SECRET_ACCESS_KEY:-}" ]]; then
        mkdir -p ~/.aws
        cat > ~/.aws/credentials << EOF
[r2]
aws_access_key_id = ${R2_ACCESS_KEY_ID}
aws_secret_access_key = ${R2_SECRET_ACCESS_KEY}
EOF
        cat > ~/.aws/config << EOF
[profile r2]
endpoint_url = ${R2_ENDPOINT}
region = auto
output = json
EOF
        log_info "R2 credentials configured"
        return 0
    else
        log_warn "R2 credentials not set - using public URLs if available"
        return 1
    fi
}

# Download file from R2 using AWS CLI
download_from_r2() {
    local r2_path=$1
    local local_path=$2
    local filename=$(basename "$local_path")
    local dest_dir=$(dirname "$local_path")

    mkdir -p "$dest_dir"

    # Skip if already exists and valid
    if [[ -f "$local_path" ]] && [[ -s "$local_path" ]]; then
        local size=$(stat -c%s "$local_path" 2>/dev/null || stat -f%z "$local_path" 2>/dev/null || echo 0)
        if [[ "$size" -gt "$MIN_MODEL_SIZE" ]]; then
            log_info "[SKIP] $filename already exists (${size} bytes)"
            return 0
        fi
    fi

    log_info "[DOWNLOAD] $filename from R2..."

    if aws s3 cp "s3://${R2_BUCKET}/${r2_path}" "$local_path" --profile r2 2>&1; then
        # Validate
        if [[ -f "$local_path" ]] && [[ -s "$local_path" ]]; then
            local size=$(stat -c%s "$local_path" 2>/dev/null || stat -f%z "$local_path" 2>/dev/null || echo 0)
            if [[ "$size" -gt "$MIN_MODEL_SIZE" ]]; then
                log_info "[OK] $filename (${size} bytes)"
                return 0
            else
                log_error "[ERROR] File too small: $filename"
                rm -f "$local_path"
                return 1
            fi
        fi
    fi

    log_error "[ERROR] Failed to download: $filename"
    return 1
}

# Main
echo ""
echo "=========================================="
echo "  Download Models from R2"
echo "=========================================="
echo ""

# Setup R2 credentials
if ! setup_r2_cli; then
    log_error "R2 credentials required. Set R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY"
    exit 1
fi

# Download based on flags
if [[ "${DOWNLOAD_FLUX:-false}" == "true" ]]; then
    log_step "Core Flux Models"

    download_from_r2 "vae/ae.safetensors" "${COMFYUI_DIR}/models/vae/ae.safetensors"
    download_from_r2 "diffusion_models/flux1-dev.safetensors" "${COMFYUI_DIR}/models/diffusion_models/flux1-dev.safetensors"
    download_from_r2 "clip/clip_l.safetensors" "${COMFYUI_DIR}/models/clip/clip_l.safetensors"
    download_from_r2 "clip/t5xxl_fp8_e4m3fn.safetensors" "${COMFYUI_DIR}/models/clip/t5xxl_fp8_e4m3fn.safetensors"
fi

if [[ "${DOWNLOAD_FLUX_IPADAPTER:-false}" == "true" ]]; then
    log_step "IP-Adapter Models"

    download_from_r2 "ipadapter/FLUX.1-dev-IP-Adapter.bin" "${COMFYUI_DIR}/models/ipadapter/FLUX.1-dev-IP-Adapter.bin"
    download_from_r2 "clip_vision/sigclip_vision_patch14_384.safetensors" "${COMFYUI_DIR}/models/clip_vision/sigclip_vision_patch14_384.safetensors"
fi

if [[ "${DOWNLOAD_FLUX_PULID:-false}" == "true" ]]; then
    log_step "PuLID Models"

    download_from_r2 "pulid/pulid_flux_v0.9.1.safetensors" "${COMFYUI_DIR}/models/pulid/pulid_flux_v0.9.1.safetensors"
    download_from_r2 "pulid/EVA02_CLIP_L_336_psz14_s6B.pt" "${COMFYUI_DIR}/models/pulid/EVA02_CLIP_L_336_psz14_s6B.pt"
fi

if [[ "${DOWNLOAD_FLUX_CONTROLNETS:-false}" == "true" ]]; then
    log_step "ControlNet Models"

    download_from_r2 "controlnet/flux_controlnet_union_pro_2.0.safetensors" "${COMFYUI_DIR}/models/controlnet/flux_controlnet_union_pro_2.0.safetensors"
    download_from_r2 "controlnet/flux_controlnet_union_instantx.safetensors" "${COMFYUI_DIR}/models/controlnet/flux_controlnet_union_instantx.safetensors"
    download_from_r2 "controlnet/flux_controlnet_upscaler_jasperai.safetensors" "${COMFYUI_DIR}/models/controlnet/flux_controlnet_upscaler_jasperai.safetensors"
fi

if [[ "${DOWNLOAD_FLUX_LORAS:-false}" == "true" ]]; then
    log_step "LoRA Models"

    download_from_r2 "loras/GracePenelopeTargaryenV5.safetensors" "${COMFYUI_DIR}/models/loras/GracePenelopeTargaryenV5.safetensors"
    download_from_r2 "loras/VideoAditor_flux_realism_lora.safetensors" "${COMFYUI_DIR}/models/loras/VideoAditor_flux_realism_lora.safetensors"
    download_from_r2 "loras/Xlabs-AI_flux-RealismLora.safetensors" "${COMFYUI_DIR}/models/loras/Xlabs-AI_flux-RealismLora.safetensors"
    download_from_r2 "loras/my_first_lora_v1.safetensors" "${COMFYUI_DIR}/models/loras/my_first_lora_v1.safetensors" || true
    download_from_r2 "loras/my_first_lora_v2.safetensors" "${COMFYUI_DIR}/models/loras/my_first_lora_v2.safetensors" || true
fi

# Always download upscaler if any download is requested
if [[ "${DOWNLOAD_FLUX:-false}" == "true" ]] || [[ "${DOWNLOAD_FLUX_CONTROLNETS:-false}" == "true" ]]; then
    log_step "Upscaler Models"
    download_from_r2 "upscale_models/4x-UltraSharp.pth" "${COMFYUI_DIR}/models/upscale_models/4x-UltraSharp.pth" || true
fi

log_step "Download Complete"
log_info "Models downloaded from R2!"
