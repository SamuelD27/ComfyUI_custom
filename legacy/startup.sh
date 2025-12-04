#!/bin/bash
# =============================================================================
# ComfyUI + Flux Enhanced Startup Script for RunPod
# =============================================================================
# This script provides:
#   - Environment validation
#   - Automatic directory creation
#   - Dependency installation with version pinning
#   - Model downloads with progress bars and verification
#   - Idempotent execution (skip already downloaded models)
#   - Comprehensive error handling and logging
#   - Final validation checks
#   - ComfyUI launch
# =============================================================================

set -o pipefail

# =============================================================================
# Color codes for output
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# =============================================================================
# Logging functions
# =============================================================================
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}${BOLD}=== $1 ===${NC}\n"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_skip() {
    echo -e "${YELLOW}⏭️${NC}  $1"
}

log_download() {
    echo -e "${CYAN}⬇️${NC}  $1"
}

# =============================================================================
# Configuration
# =============================================================================
COMFYUI_DIR="${COMFYUI_DIR:-/ComfyUI}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
LOG_FILE="${WORKSPACE_DIR}/startup.log"

# HF Token - MUST be set via environment variable
# DO NOT hardcode tokens - they should be provided at runtime
if [[ -z "${HF_TOKEN}" ]]; then
    echo "[WARN] HF_TOKEN not set - gated model downloads will fail"
fi

# Model download flags - all default to FALSE (opt-in)
# Set to "true" at runtime to enable model downloads
DOWNLOAD_FLUX="${DOWNLOAD_FLUX:-false}"
DOWNLOAD_FLUX_IPADAPTER="${DOWNLOAD_FLUX_IPADAPTER:-false}"
DOWNLOAD_FLUX_PULID="${DOWNLOAD_FLUX_PULID:-false}"
DOWNLOAD_FLUX_CONTROLNETS="${DOWNLOAD_FLUX_CONTROLNETS:-false}"
DOWNLOAD_FLUX_LORAS="${DOWNLOAD_FLUX_LORAS:-false}"

# Skip validation flag
SKIP_VALIDATION="${SKIP_VALIDATION:-false}"

# Progress tracking
TOTAL_MODELS=0
CURRENT_MODEL=0
FAILED_DOWNLOADS=()

# =============================================================================
# Header
# =============================================================================
echo ""
echo -e "${GREEN}${BOLD}"
echo "  ██████╗ ██████╗ ███╗   ███╗███████╗██╗   ██╗██╗   ██╗██╗"
echo " ██╔════╝██╔═══██╗████╗ ████║██╔════╝╚██╗ ██╔╝██║   ██║██║"
echo " ██║     ██║   ██║██╔████╔██║█████╗   ╚████╔╝ ██║   ██║██║"
echo " ██║     ██║   ██║██║╚██╔╝██║██╔══╝    ╚██╔╝  ██║   ██║██║"
echo " ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║        ██║   ╚██████╔╝██║"
echo "  ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝        ╚═╝    ╚═════╝ ╚═╝"
echo -e "${NC}"
echo -e "${CYAN}       + FLUX Enhanced Edition for RunPod${NC}"
echo "=========================================================="
echo ""
echo "Started at: $(date)"
echo ""

# =============================================================================
# Step 1: Environment Validation
# =============================================================================
log_step "Step 1: Environment Validation"

# Check Python version
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
log_info "Python version: ${PYTHON_VERSION}"

# Check CUDA availability
if command -v nvidia-smi &> /dev/null; then
    CUDA_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    log_success "NVIDIA Driver: ${CUDA_VERSION}"
    log_success "GPU: ${GPU_NAME}"
else
    log_warn "nvidia-smi not found - running without GPU"
fi

# Check PyTorch
TORCH_VERSION=$(python3 -c "import torch; print(torch.__version__)" 2>/dev/null || echo "not installed")
log_info "PyTorch version: ${TORCH_VERSION}"

if [[ "$TORCH_VERSION" != "not installed" ]]; then
    CUDA_AVAILABLE=$(python3 -c "import torch; print(torch.cuda.is_available())" 2>/dev/null || echo "False")
    log_info "CUDA available in PyTorch: ${CUDA_AVAILABLE}"
fi

# Check HF Token
if [[ -z "${HF_TOKEN}" ]] || [[ "${HF_TOKEN}" == "your_huggingface_token_here" ]]; then
    log_warn "HF_TOKEN not set - gated model downloads will fail"
    log_warn "Set HF_TOKEN environment variable for Flux downloads"
else
    log_success "HF_TOKEN is configured"
    # Login to HuggingFace
    log_info "Logging into Hugging Face..."
    huggingface-cli login --token "${HF_TOKEN}" 2>/dev/null || true
fi

# =============================================================================
# Step 2: Directory Creation
# =============================================================================
log_step "Step 2: Creating Model Directories"

# Ensure workspace exists
mkdir -p "${WORKSPACE_DIR}"

# All required model directories
REQUIRED_DIRS=(
    "${COMFYUI_DIR}/models/checkpoints"
    "${COMFYUI_DIR}/models/clip"
    "${COMFYUI_DIR}/models/clip_vision"
    "${COMFYUI_DIR}/models/controlnet"
    "${COMFYUI_DIR}/models/diffusion_models"
    "${COMFYUI_DIR}/models/embeddings"
    "${COMFYUI_DIR}/models/facerestore_models"
    "${COMFYUI_DIR}/models/ipadapter"
    "${COMFYUI_DIR}/models/insightface"
    "${COMFYUI_DIR}/models/loras"
    "${COMFYUI_DIR}/models/pulid"
    "${COMFYUI_DIR}/models/ultralytics/bbox"
    "${COMFYUI_DIR}/models/upscale_models"
    "${COMFYUI_DIR}/models/vae"
    "${COMFYUI_DIR}/models/xlabs/loras"
    "${COMFYUI_DIR}/models/LLM"
    "${COMFYUI_DIR}/models/vibevoice"
    "${COMFYUI_DIR}/input"
    "${COMFYUI_DIR}/output"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        log_success "Created: ${dir#${COMFYUI_DIR}/}"
    fi
done

log_success "All directories verified"

# =============================================================================
# Step 3: Install Flux-Compatible Dependencies
# =============================================================================
log_step "Step 3: Installing Flux-Compatible Dependencies"

# Check if requirements_flux.txt exists
REQUIREMENTS_FILE="${COMFYUI_DIR}/../requirements_flux.txt"
if [ ! -f "$REQUIREMENTS_FILE" ]; then
    REQUIREMENTS_FILE="/requirements_flux.txt"
fi

if [ -f "$REQUIREMENTS_FILE" ]; then
    log_info "Installing dependencies from requirements_flux.txt..."

    # Force correct NumPy version first
    log_info "Ensuring NumPy 1.26.4 compatibility..."
    pip uninstall -y numpy 2>/dev/null || true
    pip install --no-cache-dir numpy==1.26.4 2>&1 | tail -1

    # Install ONNX Runtime for IP-Adapter
    log_info "Installing ONNX Runtime GPU..."
    pip install --no-cache-dir onnxruntime-gpu==1.17.3 2>&1 | tail -1 || \
        pip install --no-cache-dir onnxruntime==1.17.3 2>&1 | tail -1

    # Install remaining dependencies
    pip install --no-cache-dir -r "$REQUIREMENTS_FILE" 2>&1 | tail -5

    log_success "Dependencies installed"
else
    log_warn "requirements_flux.txt not found, installing core dependencies manually..."

    pip uninstall -y numpy 2>/dev/null || true
    pip install --no-cache-dir \
        numpy==1.26.4 \
        onnxruntime-gpu==1.17.3 \
        opencv-contrib-python==4.9.0.80 \
        pillow>=10.0.0 \
        2>&1 | tail -3
fi

# Conditionally install InsightFace for PuLID
if [[ "${DOWNLOAD_FLUX_PULID}" == "true" ]]; then
    log_info "Installing InsightFace for PuLID support..."
    pip install --no-cache-dir insightface==0.7.3 2>&1 | tail -1 || \
        log_warn "InsightFace installation failed - PuLID may not work"
fi

# =============================================================================
# Step 4: Install Custom Nodes
# =============================================================================
log_step "Step 4: Installing Custom Nodes"

CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"

# Function to install a custom node
install_custom_node() {
    local repo_url=$1
    local node_name=$(basename "$repo_url" .git)
    local target_dir="${CUSTOM_NODES_DIR}/${node_name}"

    if [ -d "$target_dir" ]; then
        log_skip "Already installed: ${node_name}"
        return 0
    fi

    log_download "Installing ${node_name}..."

    if git clone --depth 1 "$repo_url" "$target_dir" 2>/dev/null; then
        # Install requirements if they exist
        if [ -f "${target_dir}/requirements.txt" ]; then
            pip install --no-cache-dir -r "${target_dir}/requirements.txt" 2>&1 | tail -1 || true
        fi
        if [ -f "${target_dir}/install.py" ]; then
            python3 "${target_dir}/install.py" 2>&1 | tail -1 || true
        fi
        log_success "Installed: ${node_name}"
        return 0
    else
        log_error "Failed to install: ${node_name}"
        return 1
    fi
}

# Install IP-Adapter Flux node
install_custom_node "https://github.com/Shakker-Labs/ComfyUI-IPAdapter-Flux.git"

# Install ComfyUI-Manager if not present
install_custom_node "https://github.com/ltdrdata/ComfyUI-Manager.git"

log_success "Custom nodes installation complete"

# =============================================================================
# Step 5: Model Downloads
# =============================================================================
log_step "Step 5: Downloading Models"

# Download function with retry logic and progress
download_file() {
    local url=$1
    local dest=$2
    local filename=$(basename "$dest")
    local expected_size=${3:-0}  # Optional expected size in bytes

    # Check if already exists
    if [ -f "$dest" ]; then
        local actual_size=$(stat -f%z "$dest" 2>/dev/null || stat -c%s "$dest" 2>/dev/null || echo "0")

        # If expected size is provided, verify it
        if [ "$expected_size" -gt 0 ] && [ "$actual_size" -lt "$((expected_size * 95 / 100))" ]; then
            log_warn "Incomplete file detected: ${filename}, re-downloading..."
            rm -f "$dest"
        else
            log_skip "Already exists: ${filename}"
            return 0
        fi
    fi

    # Ensure directory exists
    mkdir -p "$(dirname "$dest")"

    ((CURRENT_MODEL++))
    log_download "[${CURRENT_MODEL}/${TOTAL_MODELS}] Downloading ${filename}..."

    # Retry logic
    for attempt in 1 2 3; do
        if wget -q --show-progress --progress=bar:force:noscroll \
            --header="Authorization: Bearer ${HF_TOKEN}" \
            -O "$dest" "$url" 2>&1; then

            # Verify file exists and is not empty
            if [ -f "$dest" ] && [ -s "$dest" ]; then
                log_success "Downloaded: ${filename}"
                return 0
            fi
        fi

        log_warn "Attempt ${attempt}/3 failed for ${filename}, retrying..."
        rm -f "$dest"
        sleep 3
    done

    log_error "Failed to download: ${filename}"
    FAILED_DOWNLOADS+=("$filename")
    return 1
}

# Download from HuggingFace using CLI
download_hf() {
    local repo=$1
    local file=$2
    local dest=$3
    local filename=$(basename "$dest")

    if [ -f "$dest" ]; then
        log_skip "Already exists: ${filename}"
        return 0
    fi

    mkdir -p "$(dirname "$dest")"

    ((CURRENT_MODEL++))
    log_download "[${CURRENT_MODEL}/${TOTAL_MODELS}] Downloading ${filename} from ${repo}..."

    # Use huggingface-cli for better handling
    for attempt in 1 2 3; do
        if huggingface-cli download "$repo" "$file" \
            --local-dir "$(dirname "$dest")" \
            --local-dir-use-symlinks False \
            --token "${HF_TOKEN}" 2>/dev/null; then

            # Move file to correct location if needed
            local downloaded_file="$(dirname "$dest")/${file}"
            if [ -f "$downloaded_file" ] && [ "$downloaded_file" != "$dest" ]; then
                mv "$downloaded_file" "$dest"
            fi

            if [ -f "$dest" ] && [ -s "$dest" ]; then
                log_success "Downloaded: ${filename}"
                return 0
            fi
        fi

        log_warn "Attempt ${attempt}/3 failed, retrying..."
        sleep 3
    done

    log_error "Failed to download: ${filename}"
    FAILED_DOWNLOADS+=("$filename")
    return 1
}

# Calculate total models to download
calculate_total_models() {
    TOTAL_MODELS=0

    if [[ "${DOWNLOAD_FLUX}" == "true" ]]; then
        TOTAL_MODELS=$((TOTAL_MODELS + 5))  # VAE, diffusion model, clip_l, t5xxl, kontext
    fi

    if [[ "${DOWNLOAD_FLUX_IPADAPTER}" == "true" ]]; then
        TOTAL_MODELS=$((TOTAL_MODELS + 2))  # IP-Adapter model, CLIP Vision
    fi

    if [[ "${DOWNLOAD_FLUX_PULID}" == "true" ]]; then
        TOTAL_MODELS=$((TOTAL_MODELS + 2))  # PuLID model, InsightFace model
    fi

    if [[ "${DOWNLOAD_FLUX_CONTROLNETS}" == "true" ]]; then
        TOTAL_MODELS=$((TOTAL_MODELS + 3))  # Union Pro 2.0, Union, Upscaler
    fi

    if [[ "${DOWNLOAD_FLUX_LORAS}" == "true" ]]; then
        TOTAL_MODELS=$((TOTAL_MODELS + 4))  # Realism LoRAs
    fi

    # Upscaler
    TOTAL_MODELS=$((TOTAL_MODELS + 1))
}

calculate_total_models
log_info "Total models to download: ${TOTAL_MODELS}"

# -----------------------------------------------------------------------------
# Core Flux Models
# -----------------------------------------------------------------------------
if [[ "${DOWNLOAD_FLUX}" == "true" ]]; then
    echo ""
    log_info "${BOLD}Downloading Core Flux Models...${NC}"

    # Flux VAE (ae.safetensors)
    download_file \
        "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors?download=true" \
        "${COMFYUI_DIR}/models/vae/ae.sft" \
        335544320  # ~335MB

    # Flux Diffusion Model (flux1-dev.safetensors)
    download_file \
        "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors?download=true" \
        "${COMFYUI_DIR}/models/diffusion_models/flux1-dev.sft" \
        23840000000  # ~23.8GB

    # CLIP-L Text Encoder
    download_file \
        "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors?download=true" \
        "${COMFYUI_DIR}/models/clip/clip_l.safetensors" \
        0

    # T5 XXL FP8 Text Encoder
    download_file \
        "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors?download=true" \
        "${COMFYUI_DIR}/models/clip/t5xxl_fp8_e4m3fn.safetensors" \
        0

    # Flux Kontext (optional but useful)
    download_file \
        "https://huggingface.co/black-forest-labs/FLUX.1-Kontext-dev/resolve/main/flux1-kontext-dev.safetensors?download=true" \
        "${COMFYUI_DIR}/models/diffusion_models/flux1-kontext-dev.safetensors" \
        0
fi

# -----------------------------------------------------------------------------
# Flux IP-Adapter Models
# -----------------------------------------------------------------------------
if [[ "${DOWNLOAD_FLUX_IPADAPTER}" == "true" ]]; then
    echo ""
    log_info "${BOLD}Downloading Flux IP-Adapter Models...${NC}"

    # Flux IP-Adapter
    download_file \
        "https://huggingface.co/InstantX/FLUX.1-dev-IP-Adapter/resolve/main/ip-adapter.bin?download=true" \
        "${COMFYUI_DIR}/models/ipadapter/FLUX.1-dev-IP-Adapter.bin" \
        0

    # SigLIP Vision Encoder (required for IP-Adapter)
    download_file \
        "https://huggingface.co/google/siglip-so400m-patch14-384/resolve/main/model.safetensors?download=true" \
        "${COMFYUI_DIR}/models/clip_vision/sigclip_vision_patch14_384.safetensors" \
        0
fi

# -----------------------------------------------------------------------------
# PuLID Models
# -----------------------------------------------------------------------------
if [[ "${DOWNLOAD_FLUX_PULID}" == "true" ]]; then
    echo ""
    log_info "${BOLD}Downloading PuLID Models...${NC}"

    # PuLID Flux Model
    download_file \
        "https://huggingface.co/guozinan/PuLID/resolve/main/pulid_flux_v0.9.1.safetensors?download=true" \
        "${COMFYUI_DIR}/models/pulid/pulid_flux_v0.9.1.safetensors" \
        0

    # EVA CLIP (required for PuLID)
    download_file \
        "https://huggingface.co/QuanSun/EVA-CLIP/resolve/main/EVA02_CLIP_L_336_psz14_s6B.pt?download=true" \
        "${COMFYUI_DIR}/models/pulid/EVA02_CLIP_L_336_psz14_s6B.pt" \
        0
fi

# -----------------------------------------------------------------------------
# Flux ControlNet Models
# -----------------------------------------------------------------------------
if [[ "${DOWNLOAD_FLUX_CONTROLNETS}" == "true" ]]; then
    echo ""
    log_info "${BOLD}Downloading Flux ControlNet Models...${NC}"

    # Shakker-Labs ControlNet Union Pro 2.0
    download_file \
        "https://huggingface.co/Shakker-Labs/FLUX.1-dev-ControlNet-Union-Pro-2.0/resolve/main/diffusion_pytorch_model.safetensors?download=true" \
        "${COMFYUI_DIR}/models/controlnet/flux_controlnet_union_pro_2.0.safetensors" \
        0

    # InstantX ControlNet Union
    download_file \
        "https://huggingface.co/InstantX/FLUX.1-dev-Controlnet-Union/resolve/main/diffusion_pytorch_model.safetensors?download=true" \
        "${COMFYUI_DIR}/models/controlnet/flux_controlnet_union_instantx.safetensors" \
        0

    # Jasper AI Flux Upscaler ControlNet
    download_file \
        "https://huggingface.co/jasperai/Flux.1-dev-Controlnet-Upscaler/resolve/main/diffusion_pytorch_model.safetensors?download=true" \
        "${COMFYUI_DIR}/models/controlnet/flux_controlnet_upscaler_jasperai.safetensors" \
        0
fi

# -----------------------------------------------------------------------------
# Flux LoRA Models
# -----------------------------------------------------------------------------
if [[ "${DOWNLOAD_FLUX_LORAS}" == "true" ]]; then
    echo ""
    log_info "${BOLD}Downloading Flux LoRA Models...${NC}"

    # Super Realism LoRA
    download_file \
        "https://huggingface.co/strangerzonehf/Flux-Super-Realism-LoRA/resolve/main/super-realism-lora.safetensors?download=true" \
        "${COMFYUI_DIR}/models/loras/flux_super_realism_lora.safetensors" \
        0

    # VideoAditor Realism LoRA
    download_file \
        "https://huggingface.co/VideoAditor/Flux-Lora-Realism/resolve/main/flux_realism_lora.safetensors?download=true" \
        "${COMFYUI_DIR}/models/loras/VideoAditor_flux_realism_lora.safetensors" \
        0

    # XLabs Realism LoRA
    mkdir -p "${COMFYUI_DIR}/models/xlabs/loras"
    download_file \
        "https://huggingface.co/XLabs-AI/flux-RealismLora/resolve/main/lora.safetensors?download=true" \
        "${COMFYUI_DIR}/models/xlabs/loras/Xlabs-AI_flux-RealismLora.safetensors" \
        0

    # GracePenelopeTargaryen LoRA (ValyrianTech custom)
    download_file \
        "https://huggingface.co/WouterGlorieux/GracePenelopeTargaryenV5/resolve/main/GracePenelopeTargaryenV5.safetensors?download=true" \
        "${COMFYUI_DIR}/models/loras/GracePenelopeTargaryenV5.safetensors" \
        0
fi

# -----------------------------------------------------------------------------
# Upscaler Models
# -----------------------------------------------------------------------------
echo ""
log_info "${BOLD}Downloading Upscaler Models...${NC}"

download_file \
    "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth?download=true" \
    "${COMFYUI_DIR}/models/upscale_models/4x-UltraSharp.pth" \
    0

# =============================================================================
# Step 6: Final Validation
# =============================================================================
log_step "Step 6: Running Final Validation"

if [[ "${SKIP_VALIDATION}" != "true" ]]; then
    # Run validation script if it exists
    VALIDATE_SCRIPT="${COMFYUI_DIR}/../validate_environment.py"
    if [ ! -f "$VALIDATE_SCRIPT" ]; then
        VALIDATE_SCRIPT="/validate_environment.py"
    fi

    if [ -f "$VALIDATE_SCRIPT" ]; then
        log_info "Running environment validation..."
        if python3 "$VALIDATE_SCRIPT"; then
            log_success "All validation checks passed!"
        else
            log_warn "Some validation checks failed - see above for details"
        fi
    else
        log_info "Validation script not found, running basic checks..."

        # Basic checks
        python3 -c "import torch; print(f'PyTorch: {torch.__version__}')" 2>/dev/null && log_success "PyTorch OK" || log_error "PyTorch failed"
        python3 -c "import numpy; print(f'NumPy: {numpy.__version__}')" 2>/dev/null && log_success "NumPy OK" || log_error "NumPy failed"

        # Check if main Flux model exists
        if [ -f "${COMFYUI_DIR}/models/diffusion_models/flux1-dev.sft" ]; then
            log_success "Flux model present"
        else
            log_warn "Flux model not found at expected location"
        fi
    fi
else
    log_warn "Validation skipped (SKIP_VALIDATION=true)"
fi

# Report any failed downloads
if [ ${#FAILED_DOWNLOADS[@]} -gt 0 ]; then
    echo ""
    log_error "Failed to download the following models:"
    for failed in "${FAILED_DOWNLOADS[@]}"; do
        echo "  - $failed"
    done
    echo ""
    log_warn "You can retry downloading these manually or restart the container"
fi

# =============================================================================
# Step 7: Launch ComfyUI
# =============================================================================
log_step "Step 7: Launching ComfyUI"

echo ""
echo "=========================================================="
echo -e "${GREEN}${BOLD}Startup Complete!${NC}"
echo "=========================================================="
echo ""
echo "Access ComfyUI at: http://localhost:8188"
echo "Started at: $(date)"
echo ""

# Change to ComfyUI directory
cd "${COMFYUI_DIR}"

# Launch ComfyUI
log_info "Starting ComfyUI server..."
exec python3 main.py --listen 0.0.0.0 --port 8188 "$@"
