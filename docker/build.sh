#!/usr/bin/env bash
# =============================================================================
# ComfyUI Serverless Worker - Build and Push Script
# =============================================================================
# Builds Docker image for RunPod Serverless (linux/amd64 only - NVIDIA CUDA).
# Note: ARM64 not supported due to NVIDIA CUDA/GPU requirements.
#
# Usage:
#   ./build.sh                    # Build and push latest
#   ./build.sh --tag v1.0.0       # Build with specific tag
#   ./build.sh --model flux1-dev-fp8  # Build with model baked in
#   ./build.sh --no-push          # Build only, don't push
#   ./build.sh --no-test          # Skip tests
#   ./build.sh --cleanup-only     # Only cleanup old images
#
# Environment variables:
#   DOCKER_USERNAME    Docker Hub username (default: samsam27)
#   HF_TOKEN           Hugging Face token for gated models
#   RUNPOD_API_KEY     RunPod API key for live tests (optional)
#   USE_LOCAL_BUILDER  Set to "true" to use local builder instead of cloud
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Script directory (docker/) and project root (parent)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values
IMAGE_NAME="comfyui-serverless"
TAG="latest"
MODEL_TYPE="none"
PUSH_IMAGE=true
RUN_TESTS=true
CLEANUP_ONLY=false

# Platform - AMD64 only (NVIDIA CUDA doesn't support ARM64)
PLATFORM="linux/amd64"

# Docker username - hardcoded default, can be overridden via --username or DOCKER_USERNAME env
DOCKER_USERNAME="${DOCKER_USERNAME:-samsam27}"

# Hugging Face token (for gated models)
HF_TOKEN="${HF_TOKEN:-}"

# Builder name (will be set in setup_buildx)
BUILDER_NAME=""

# =============================================================================
# Logging Functions
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

log_fail() {
    echo -e "${RED}✗${NC} $1"
}

# =============================================================================
# Helper Functions
# =============================================================================

show_help() {
    cat << EOF
ComfyUI Serverless Worker - Build and Push Script

Usage: $0 [OPTIONS]

Options:
  -t, --tag TAG           Docker image tag (default: latest)
  -m, --model MODEL       Model type to bake in: none, flux1-dev-fp8, flux1-dev, sdxl
  -u, --username USER     Docker Hub username (default: samsam27)
  --no-push               Build only, don't push to registry
  --no-test               Skip running tests
  --cleanup-only          Only cleanup old images, don't build
  -h, --help              Show this help message

Environment Variables:
  DOCKER_USERNAME         Docker Hub username
  HF_TOKEN                Hugging Face token for gated models
  USE_LOCAL_BUILDER       Set to "true" to force local builder

Note: Builds for linux/amd64 only (NVIDIA CUDA doesn't support ARM64)

Examples:
  $0                                    # Build and push latest
  $0 --tag v1.0.0                       # Build with version tag
  $0 --model flux1-dev-fp8 --tag flux   # Build with Flux model
  $0 --no-push --no-test                # Quick local build
  $0 --cleanup-only                     # Cleanup old images
  USE_LOCAL_BUILDER=true $0             # Use local builder

Model Types:
  none          No models (smallest image, ~8GB)
  flux1-dev-fp8 Flux.1 dev FP8 quantized (~15GB)
  flux1-dev     Full Flux.1 dev (requires HF_TOKEN, ~35GB)
  sdxl          Stable Diffusion XL (~15GB)
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--tag)
                TAG="$2"
                shift 2
                ;;
            -m|--model)
                MODEL_TYPE="$2"
                shift 2
                ;;
            -u|--username)
                DOCKER_USERNAME="$2"
                shift 2
                ;;
            --no-push)
                PUSH_IMAGE=false
                shift
                ;;
            --no-test)
                RUN_TESTS=false
                shift
                ;;
            --cleanup-only)
                CLEANUP_ONLY=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

check_prerequisites() {
    log_step "Checking Prerequisites"

    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    log_success "Docker is installed"

    # Check Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    log_success "Docker daemon is running"

    # Check buildx
    if ! docker buildx version &> /dev/null; then
        log_error "Docker buildx is not available"
        exit 1
    fi
    log_success "Docker buildx is available"

    # Check username
    if [[ -z "$DOCKER_USERNAME" ]]; then
        log_error "Docker username not set. Use --username or set DOCKER_USERNAME"
        exit 1
    fi
    log_success "Docker username: $DOCKER_USERNAME"

    # Check HF token for gated models
    if [[ "$MODEL_TYPE" == "flux1-dev" ]] && [[ -z "$HF_TOKEN" ]]; then
        log_error "HF_TOKEN required for flux1-dev model"
        log_info "Set HF_TOKEN environment variable or use --model flux1-dev-fp8 instead"
        exit 1
    fi

    # Check required files (Dockerfile in docker/, others in project root)
    if [[ ! -f "$SCRIPT_DIR/Dockerfile" ]]; then
        log_error "Required file not found: docker/Dockerfile"
        exit 1
    fi

    local project_files=(
        "serverless_worker.py"
        "requirements.txt"
        "src/start.sh"
        "src/extra_model_paths.yaml"
    )

    for file in "${project_files[@]}"; do
        if [[ ! -f "$PROJECT_ROOT/$file" ]]; then
            log_error "Required file not found: $file"
            exit 1
        fi
    done
    log_success "All required files present"
}

setup_buildx() {
    log_step "Setting Up Docker Buildx"

    local cloud_builder="cloud-samsam27-masuka"
    local local_builder="comfyui-builder"

    # Check if USE_LOCAL_BUILDER environment variable is set
    if [[ "${USE_LOCAL_BUILDER:-false}" == "true" ]]; then
        log_info "Using local builder as requested (USE_LOCAL_BUILDER=true)"
        BUILDER_NAME="$local_builder"
    else
        # Try cloud builder first
        log_info "Checking cloud builder availability..."
        if docker buildx inspect "$cloud_builder" &> /dev/null; then
            log_success "Cloud builder '$cloud_builder' is available"
            log_warn "Cloud builder has limited disk space. If build fails, use local builder:"
            log_warn "  USE_LOCAL_BUILDER=true ./build.sh"
            BUILDER_NAME="$cloud_builder"
        else
            log_warn "Cloud builder not found, using local builder"
            BUILDER_NAME="$local_builder"
        fi
    fi

    # Setup the selected builder
    if [[ "$BUILDER_NAME" == "$local_builder" ]]; then
        log_info "Setting up local builder: $local_builder"
        if docker buildx inspect "$local_builder" &> /dev/null; then
            docker buildx use "$local_builder"
            log_success "Using existing local builder"
        else
            log_info "Creating local builder..."
            docker buildx create --name "$local_builder" --driver docker-container --use
            log_success "Created local builder"
        fi
        docker buildx inspect --bootstrap &> /dev/null || true
    else
        log_info "Using cloud builder: $cloud_builder"
        docker buildx use "$cloud_builder" 2>/dev/null || true
    fi

    log_success "Builder ready: $BUILDER_NAME"

    # Show builder details
    log_info "Builder details:"
    docker buildx inspect "$BUILDER_NAME" 2>/dev/null | head -10 || true
}

cleanup_old_images() {
    log_step "Cleaning Up Old Images"

    local full_image="$DOCKER_USERNAME/$IMAGE_NAME"

    # Remove dangling images first
    log_info "Removing dangling images..."
    docker image prune -f &> /dev/null || true

    # List all local images matching our name
    local images
    images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^${full_image}:" || true)

    if [[ -z "$images" ]]; then
        log_info "No old images found to clean up"
        return 0
    fi

    log_info "Found images:"
    echo "$images"

    # Remove ALL old tagged images (only keep the current tag we're building)
    local count=0
    while IFS= read -r image; do
        local image_tag="${image##*:}"

        # Skip if it's the current tag we're building
        if [[ "$image_tag" == "$TAG" ]]; then
            log_info "Keeping (current build tag): $image"
            continue
        fi

        # Delete all other versions
        log_info "Removing: $image"
        docker rmi -f "$image" &> /dev/null || true
        ((count++)) || true
    done <<< "$images"

    log_success "Removed $count old image(s)"

    # Also clean up buildx cache if it's getting large
    log_info "Pruning build cache..."
    docker buildx prune -f --filter "until=24h" &> /dev/null || true

    # Show disk usage
    log_info "Current Docker disk usage:"
    docker system df 2>/dev/null || true
}

build_image() {
    log_step "Building Docker Image"

    local full_image="$DOCKER_USERNAME/$IMAGE_NAME:$TAG"
    local latest_image="$DOCKER_USERNAME/$IMAGE_NAME:latest"

    log_info "Building for RunPod platform: $PLATFORM (NVIDIA CUDA)"
    log_info "Note: ARM64 not supported due to CUDA/GPU requirements"
    log_info "Using builder: $BUILDER_NAME"
    log_info "Image: $full_image"
    log_info "Model type: $MODEL_TYPE"

    if [[ "$BUILDER_NAME" == *"local"* ]] || [[ "$BUILDER_NAME" == "comfyui-builder" ]]; then
        log_info "Local build time estimate: 30-60 minutes"
    else
        log_info "Cloud build time estimate: 5-15 minutes"
    fi
    echo ""

    # Build and push
    local build_cmd=(
        docker buildx build
        --builder "$BUILDER_NAME"
        --platform "$PLATFORM"
        -f "$SCRIPT_DIR/Dockerfile"
        -t "$full_image"
        --build-arg "MODEL_TYPE=$MODEL_TYPE"
        --build-arg "BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        --target final
    )

    # Add HF token if available
    if [[ -n "$HF_TOKEN" ]]; then
        build_cmd+=(--build-arg "HUGGINGFACE_ACCESS_TOKEN=$HF_TOKEN")
    fi

    # Add push or load based on settings
    if [[ "$PUSH_IMAGE" == true ]]; then
        build_cmd+=(-t "$latest_image")
        build_cmd+=(--push)
    else
        build_cmd+=(--load)
    fi

    # Use project root as build context
    build_cmd+=("$PROJECT_ROOT")

    # Execute build
    log_info "Running build..."
    echo ""

    if "${build_cmd[@]}"; then
        log_success "Successfully built Docker image"
        if [[ "$PUSH_IMAGE" == true ]]; then
            log_success "Pushed: $full_image"
            log_success "Pushed: $latest_image"
        else
            log_success "Loaded locally: $full_image"
        fi
    else
        log_error "Build failed"
        exit 1
    fi

    # Store image name for testing
    export PUSHED_IMAGE="$full_image"
}

run_tests() {
    log_step "Running Tests"

    local full_image="$DOCKER_USERNAME/$IMAGE_NAME:$TAG"
    local test_failed=false

    # Test 1: Check image exists
    log_info "Test 1: Checking image exists..."
    if docker manifest inspect "$full_image" &> /dev/null || docker image inspect "$full_image" &> /dev/null; then
        log_success "Image exists: $full_image"
    else
        log_fail "Image not found: $full_image"
        test_failed=true
    fi

    # Test 2: Check Python syntax
    log_info "Test 2: Checking Python syntax..."
    if python3 -c "import ast; ast.parse(open('$SCRIPT_DIR/serverless_worker.py').read())"; then
        log_success "Python syntax OK"
    else
        log_fail "Python syntax error"
        test_failed=true
    fi

    # Test 3: Run container and check handler imports
    log_info "Test 3: Checking handler imports..."
    local import_test
    import_test=$(docker run --rm --platform linux/amd64 "$full_image" \
        python -c "
import sys
try:
    import runpod
    import requests
    import websocket
    print('OK: All imports successful')
    sys.exit(0)
except ImportError as e:
    print(f'FAIL: {e}')
    sys.exit(1)
" 2>&1) || true

    if [[ "$import_test" == *"OK:"* ]]; then
        log_success "Handler imports OK"
    else
        log_fail "Handler import failed: $import_test"
        test_failed=true
    fi

    # Test 4: Check ComfyUI installation
    log_info "Test 4: Checking ComfyUI installation..."
    local comfy_test
    comfy_test=$(docker run --rm --platform linux/amd64 "$full_image" \
        python -c "
import sys
import os
comfy_dir = '/comfyui'
if os.path.exists(f'{comfy_dir}/main.py'):
    print('OK: ComfyUI main.py found')
    sys.exit(0)
else:
    print('FAIL: ComfyUI not found')
    sys.exit(1)
" 2>&1) || true

    if [[ "$comfy_test" == *"OK:"* ]]; then
        log_success "ComfyUI installation OK"
    else
        log_fail "ComfyUI check failed: $comfy_test"
        test_failed=true
    fi

    # Test 5: Check model directories
    log_info "Test 5: Checking model directories..."
    local dirs_test
    dirs_test=$(docker run --rm --platform linux/amd64 "$full_image" \
        bash -c "
dirs=('checkpoints' 'clip' 'vae' 'loras' 'controlnet' 'unet')
for dir in \"\${dirs[@]}\"; do
    if [[ ! -d \"/comfyui/models/\$dir\" ]]; then
        echo \"FAIL: /comfyui/models/\$dir not found\"
        exit 1
    fi
done
echo 'OK: All model directories exist'
" 2>&1) || true

    if [[ "$dirs_test" == *"OK:"* ]]; then
        log_success "Model directories OK"
    else
        log_fail "Model directories check failed: $dirs_test"
        test_failed=true
    fi

    # Test 6: Check if models are present (if MODEL_TYPE != none)
    if [[ "$MODEL_TYPE" != "none" ]]; then
        log_info "Test 6: Checking baked models..."
        local model_test
        model_test=$(docker run --rm --platform linux/amd64 "$full_image" \
            bash -c "
model_count=\$(find /comfyui/models -name '*.safetensors' -o -name '*.ckpt' | wc -l)
if [[ \$model_count -gt 0 ]]; then
    echo \"OK: Found \$model_count model file(s)\"
    find /comfyui/models -name '*.safetensors' -o -name '*.ckpt'
    exit 0
else
    echo 'FAIL: No models found'
    exit 1
fi
" 2>&1) || true

        if [[ "$model_test" == *"OK:"* ]]; then
            log_success "Baked models found"
            echo "$model_test" | grep -v "OK:" || true
        else
            log_fail "Baked models check failed: $model_test"
            test_failed=true
        fi
    else
        log_info "Test 6: Skipped (no models baked)"
    fi

    # Test 7: Check start.sh exists and is executable
    log_info "Test 7: Checking start.sh..."
    local start_test
    start_test=$(docker run --rm --platform linux/amd64 "$full_image" \
        bash -c "
if [[ -x /start.sh ]]; then
    echo 'OK: start.sh exists and is executable'
    exit 0
else
    echo 'FAIL: start.sh not found or not executable'
    exit 1
fi
" 2>&1) || true

    if [[ "$start_test" == *"OK:"* ]]; then
        log_success "start.sh OK"
    else
        log_fail "start.sh check failed: $start_test"
        test_failed=true
    fi

    # Test 8: Quick handler test (dry run)
    log_info "Test 8: Handler dry run test..."
    local handler_test
    handler_test=$(docker run --rm --platform linux/amd64 \
        -e "COMFYUI_DIR=/comfyui" \
        "$full_image" \
        python -c "
import sys
sys.path.insert(0, '/')
from serverless_worker import validate_input, handler

# Test validation
result, error = validate_input({'workflow': {'1': {'class_type': 'Test'}}})
if error:
    print(f'FAIL: Validation failed: {error}')
    sys.exit(1)

# Test empty input
result, error = validate_input(None)
if error != 'Please provide input':
    print(f'FAIL: Empty input validation wrong')
    sys.exit(1)

# Test missing workflow
result, error = validate_input({'images': []})
if 'workflow' not in error.lower():
    print(f'FAIL: Missing workflow validation wrong')
    sys.exit(1)

print('OK: Handler validation tests passed')
" 2>&1) || true

    if [[ "$handler_test" == *"OK:"* ]]; then
        log_success "Handler validation tests passed"
    else
        log_fail "Handler test failed: $handler_test"
        test_failed=true
    fi

    # Summary
    echo ""
    if [[ "$test_failed" == true ]]; then
        log_error "Some tests failed!"
        return 1
    else
        log_success "All tests passed!"
        return 0
    fi
}

show_summary() {
    log_step "Build Summary"

    local full_image="$DOCKER_USERNAME/$IMAGE_NAME:$TAG"
    local latest_image="$DOCKER_USERNAME/$IMAGE_NAME:latest"

    echo ""
    echo -e "${GREEN}${BOLD}🎉 Successfully built ComfyUI Serverless Worker!${NC}"
    echo ""
    echo -e "${CYAN}📦 Docker Images (${PLATFORM} for RunPod):${NC}"
    echo "   - $full_image"
    if [[ "$PUSH_IMAGE" == true ]]; then
        echo "   - $latest_image"
    fi
    echo ""
    echo -e "${CYAN}🏷️  Configuration:${NC}"
    echo "   - Model: $MODEL_TYPE"
    echo "   - Builder: $BUILDER_NAME"
    echo "   - Pushed: $PUSH_IMAGE"
    echo ""

    if [[ "$PUSH_IMAGE" == true ]]; then
        echo -e "${CYAN}🚀 RunPod Serverless Deployment:${NC}"
        echo ""
        echo "1. Create Serverless Endpoint:"
        echo "   - Go to: https://www.runpod.io/console/serverless"
        echo "   - Container Image: $latest_image"
        echo "   - GPU: Any with 24GB+ VRAM (RTX 3090/4090, A5000, A6000, L40, A100, H100)"
        echo ""
        echo "2. Optional Environment Variables:"
        echo "   - BUCKET_ENDPOINT_URL: For S3 upload"
        echo "   - HF_TOKEN: For gated model downloads"
        echo ""
        echo "3. Optional Network Volume:"
        echo "   - Mount at /runpod-volume for models"
        echo ""
        echo "4. Test with curl:"
        echo "   curl -X POST \"https://api.runpod.ai/v2/\${ENDPOINT_ID}/runsync\" \\"
        echo "     -H \"Authorization: Bearer \${RUNPOD_API_KEY}\" \\"
        echo "     -H \"Content-Type: application/json\" \\"
        echo "     -d @test_input.json"
        echo ""
    fi

    echo -e "${CYAN}🧪 Test Locally:${NC}"
    echo "   docker run --rm -it $full_image python /serverless_worker.py --test"
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    echo -e "${CYAN}${BOLD}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║     ComfyUI Serverless Worker - Build Script          ║"
    echo "  ╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Parse arguments
    parse_args "$@"

    # Cleanup only mode
    if [[ "$CLEANUP_ONLY" == true ]]; then
        check_prerequisites
        cleanup_old_images
        exit 0
    fi

    # Normal build flow
    check_prerequisites
    setup_buildx
    cleanup_old_images
    build_image

    if [[ "$RUN_TESTS" == true ]]; then
        run_tests || log_warn "Tests failed but continuing..."
    fi

    show_summary

    echo ""
    log_success "Done!"
}

# Run main
main "$@"
