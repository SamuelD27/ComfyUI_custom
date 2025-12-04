#!/bin/bash
set -euo pipefail

# =============================================================================
# Sync Models from HuggingFace to Cloudflare R2
# =============================================================================
# Downloads models from HuggingFace and uploads to R2 for faster pod startup.
# Run this from your local machine with HF_TOKEN set.
# =============================================================================

# R2 Configuration
R2_BUCKET="comfyui-models"
R2_PROFILE="r2"

# Temporary download directory
TEMP_DIR="/tmp/hf_models_$$"
mkdir -p "$TEMP_DIR"
trap "rm -rf $TEMP_DIR" EXIT

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

# Check prerequisites
check_prerequisites() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not installed. Run: brew install awscli"
        exit 1
    fi

    if [[ -z "${HF_TOKEN:-}" ]]; then
        log_error "HF_TOKEN not set. Export your HuggingFace token first."
        log_error "  export HF_TOKEN=hf_your_token_here"
        exit 1
    fi

    # Test R2 connection
    if ! aws s3 ls s3://${R2_BUCKET}/ --profile ${R2_PROFILE} &> /dev/null; then
        log_error "Cannot connect to R2 bucket. Check your ~/.aws/credentials"
        exit 1
    fi

    log_info "Prerequisites OK"
}

# Download from HF and upload to R2
sync_to_r2() {
    local hf_url=$1
    local r2_path=$2
    local filename=$(basename "$r2_path")
    local local_path="$TEMP_DIR/$filename"

    # Check if already exists in R2
    if aws s3 ls "s3://${R2_BUCKET}/${r2_path}" --profile ${R2_PROFILE} &> /dev/null; then
        log_info "[SKIP] Already in R2: $r2_path"
        return 0
    fi

    log_info "[DOWNLOAD] $filename from HuggingFace..."

    # Download with HF token
    if wget -q --show-progress -O "$local_path" \
        --header="Authorization: Bearer ${HF_TOKEN}" \
        "${hf_url}?download=true" 2>&1; then

        # Validate download
        if [[ ! -f "$local_path" ]] || [[ ! -s "$local_path" ]]; then
            log_error "Download failed or empty: $filename"
            return 1
        fi

        # Check for HTML error page
        if file "$local_path" 2>/dev/null | grep -q "HTML"; then
            log_error "Downloaded HTML error instead of model (auth issue?): $filename"
            rm -f "$local_path"
            return 1
        fi

        log_info "[UPLOAD] $filename to R2..."
        if aws s3 cp "$local_path" "s3://${R2_BUCKET}/${r2_path}" --profile ${R2_PROFILE}; then
            log_info "[OK] $filename"
            rm -f "$local_path"
            return 0
        else
            log_error "Upload to R2 failed: $filename"
            rm -f "$local_path"
            return 1
        fi
    else
        log_error "Download failed: $filename"
        return 1
    fi
}

# Main
echo ""
echo "=========================================="
echo "  Sync Models: HuggingFace -> R2"
echo "=========================================="
echo ""

check_prerequisites

# ===== CORE FLUX MODELS (gated - require HF access approval) =====
log_step "Core Flux Models (gated)"

sync_to_r2 \
    "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors" \
    "vae/ae.safetensors"

sync_to_r2 \
    "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors" \
    "diffusion_models/flux1-dev.safetensors"

sync_to_r2 \
    "https://huggingface.co/black-forest-labs/FLUX.1-Kontext-dev/resolve/main/flux1-kontext-dev.safetensors" \
    "diffusion_models/flux1-kontext-dev.safetensors"

# ===== TEXT ENCODERS (non-gated) =====
log_step "Text Encoders"

sync_to_r2 \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors" \
    "clip/clip_l.safetensors"

sync_to_r2 \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors" \
    "clip/t5xxl_fp8_e4m3fn.safetensors"

# ===== IP-ADAPTER =====
log_step "IP-Adapter Models"

sync_to_r2 \
    "https://huggingface.co/InstantX/FLUX.1-dev-IP-Adapter/resolve/main/ip-adapter.bin" \
    "ipadapter/FLUX.1-dev-IP-Adapter.bin"

sync_to_r2 \
    "https://huggingface.co/google/siglip-so400m-patch14-384/resolve/main/model.safetensors" \
    "clip_vision/sigclip_vision_patch14_384.safetensors"

# ===== PULID =====
log_step "PuLID Models"

sync_to_r2 \
    "https://huggingface.co/guozinan/PuLID/resolve/main/pulid_flux_v0.9.1.safetensors" \
    "pulid/pulid_flux_v0.9.1.safetensors"

sync_to_r2 \
    "https://huggingface.co/QuanSun/EVA-CLIP/resolve/main/EVA02_CLIP_L_336_psz14_s6B.pt" \
    "pulid/EVA02_CLIP_L_336_psz14_s6B.pt"

# ===== CONTROLNETS =====
log_step "ControlNet Models"

sync_to_r2 \
    "https://huggingface.co/Shakker-Labs/FLUX.1-dev-ControlNet-Union-Pro-2.0/resolve/main/diffusion_pytorch_model.safetensors" \
    "controlnet/flux_controlnet_union_pro_2.0.safetensors"

sync_to_r2 \
    "https://huggingface.co/InstantX/FLUX.1-dev-Controlnet-Union/resolve/main/diffusion_pytorch_model.safetensors" \
    "controlnet/flux_controlnet_union_instantx.safetensors"

sync_to_r2 \
    "https://huggingface.co/jasperai/Flux.1-dev-Controlnet-Upscaler/resolve/main/diffusion_pytorch_model.safetensors" \
    "controlnet/flux_controlnet_upscaler_jasperai.safetensors"

# ===== LORAS =====
log_step "LoRA Models"

sync_to_r2 \
    "https://huggingface.co/WouterGlorieux/GracePenelopeTargaryenV5/resolve/main/GracePenelopeTargaryenV5.safetensors" \
    "loras/GracePenelopeTargaryenV5.safetensors"

sync_to_r2 \
    "https://huggingface.co/VideoAditor/Flux-Lora-Realism/resolve/main/flux_realism_lora.safetensors" \
    "loras/VideoAditor_flux_realism_lora.safetensors"

sync_to_r2 \
    "https://huggingface.co/XLabs-AI/flux-RealismLora/resolve/main/lora.safetensors" \
    "loras/Xlabs-AI_flux-RealismLora.safetensors"

# ===== UPSCALERS =====
log_step "Upscaler Models"

sync_to_r2 \
    "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth" \
    "upscale_models/4x-UltraSharp.pth"

# ===== SUMMARY =====
log_step "Sync Complete"

echo ""
echo "Bucket contents:"
aws s3 ls s3://${R2_BUCKET}/ --recursive --human-readable --profile ${R2_PROFILE}
echo ""
log_info "All models synced to R2!"
