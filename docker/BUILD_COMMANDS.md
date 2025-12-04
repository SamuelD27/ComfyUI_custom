# ComfyUI Serverless Worker - Build Commands Reference

> **Note:** Builds for `linux/amd64` only. ARM64 is not supported due to NVIDIA CUDA/GPU requirements.

## Quick Reference

| Command | Description |
|---------|-------------|
| `./build.sh` | Build and push latest |
| `./build.sh --no-push` | Build locally only |
| `./build.sh --no-push --no-test` | Fast local build |
| `./build.sh --model flux1-dev-fp8` | Build with Flux model |
| `./build.sh --cleanup-only` | Cleanup old images |
| `USE_LOCAL_BUILDER=true ./build.sh` | Force local builder |

---

## Build Script Options

### Basic Options

```bash
# Show help
./build.sh --help
./build.sh -h

# Build and push latest (default)
./build.sh

# Build with specific tag
./build.sh --tag v1.0.0
./build.sh -t v1.0.0

# Override Docker Hub username (default: samsam27)
./build.sh --username other_user
./build.sh -u other_user
```

### Model Options

```bash
# Build without models (smallest, ~8GB)
./build.sh --model none
./build.sh -m none

# Build with Flux.1 dev FP8 (~15GB) - RECOMMENDED
./build.sh --model flux1-dev-fp8
./build.sh -m flux1-dev-fp8

# Build with full Flux.1 dev (~35GB) - requires HF_TOKEN
HF_TOKEN=hf_xxx ./build.sh --model flux1-dev
./build.sh -m flux1-dev  # Will fail without HF_TOKEN

# Build with SDXL (~15GB)
./build.sh --model sdxl
./build.sh -m sdxl
```

### Build Control Options

```bash
# Build only, don't push to Docker Hub
./build.sh --no-push

# Skip running tests
./build.sh --no-test

# Only cleanup old images, don't build
./build.sh --cleanup-only

# Force local builder (if cloud builder fails due to disk space)
USE_LOCAL_BUILDER=true ./build.sh
```

---

## Common Build Scenarios

### 1. Quick Local Test Build

```bash
# Fast: no push, no tests
./build.sh --no-push --no-test
```

### 2. Full Production Build (No Models)

```bash
# Push to Docker Hub, run tests
./build.sh --tag v1.0.0
```

**Result:** `samsam27/comfyui-serverless:v1.0.0` + `samsam27/comfyui-serverless:latest`

### 3. Production Build with Flux Model

```bash
# Build with Flux FP8 baked in
./build.sh --model flux1-dev-fp8 --tag flux-fp8
```

**Result:** `samsam27/comfyui-serverless:flux-fp8`

### 4. Full Flux Build (Gated Model)

```bash
# Requires Hugging Face token
HF_TOKEN=hf_YOUR_TOKEN ./build.sh --model flux1-dev --tag flux-full
```

**Result:** `samsam27/comfyui-serverless:flux-full` (~35GB image)

### 5. SDXL Build

```bash
./build.sh --model sdxl --tag sdxl
```

**Result:** `samsam27/comfyui-serverless:sdxl`

### 6. Development Workflow

```bash
# 1. Build locally for testing
./build.sh --no-push

# 2. Test the image
docker run --rm -it samsam27/comfyui-serverless:latest python /serverless_worker.py --test

# 3. If tests pass, build and push
./build.sh --tag v1.0.0
```

### 7. Cleanup Old Images

```bash
# Remove images older than 7 days
./build.sh --cleanup-only
```

### 8. Use Local Builder (When Cloud Fails)

```bash
# Cloud builder may run out of disk space for large images
# Use local builder instead:
USE_LOCAL_BUILDER=true ./build.sh --model flux1-dev-fp8
```

---

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DOCKER_USERNAME` | Docker Hub username | `samsam27` |
| `HF_TOKEN` | Hugging Face token (for gated models) | - |
| `USE_LOCAL_BUILDER` | Force local builder | `false` |

### Using Environment Variables

```bash
# Override username
DOCKER_USERNAME=myuser ./build.sh

# Set HF token for full Flux
export HF_TOKEN=hf_YOUR_TOKEN
./build.sh --model flux1-dev

# Or inline
HF_TOKEN=hf_xxx ./build.sh --model flux1-dev

# Force local builder
USE_LOCAL_BUILDER=true ./build.sh
```

---

## Builders

The script automatically selects the best builder:

| Builder | Name | Use Case |
|---------|------|----------|
| Cloud | `cloud-samsam27-masuka` | Fast builds (5-15 min), limited disk |
| Local | `comfyui-builder` | Large builds (30-60 min), more disk |

The script tries cloud builder first, falls back to local if unavailable.

To force local builder:
```bash
USE_LOCAL_BUILDER=true ./build.sh
```

---

## Test Suite

The build script runs 8 tests automatically:

| # | Test | Description |
|---|------|-------------|
| 1 | Image exists | Verifies Docker image was created |
| 2 | Python syntax | Checks `serverless_worker.py` |
| 3 | Handler imports | Tests runpod, requests, websocket |
| 4 | ComfyUI installation | Verifies ComfyUI is installed |
| 5 | Model directories | Checks all model dirs exist |
| 6 | Baked models | If MODEL_TYPE≠none, verifies models |
| 7 | start.sh | Checks startup script |
| 8 | Handler validation | Dry-run handler tests |

### Skip Tests

```bash
./build.sh --no-test
```

---

## Output Images

All images are pushed to Docker Hub under `samsam27/comfyui-serverless`:

| Tag | Models | Size (approx) |
|-----|--------|---------------|
| `latest` | None | ~8GB |
| `flux-fp8` | Flux.1 dev FP8 | ~15GB |
| `flux-full` | Full Flux.1 dev | ~35GB |
| `sdxl` | SDXL 1.0 | ~15GB |

---

## After Building

### Deploy to RunPod Serverless

1. Go to https://www.runpod.io/console/serverless
2. Click **"New Endpoint"**
3. Enter image: `samsam27/comfyui-serverless:latest`
4. Select GPU with 24GB+ VRAM:
   - **Consumer**: RTX 3090 (24GB), RTX 4090 (24GB)
   - **Professional**: A5000 (24GB), A6000 (48GB), L40 (48GB), L40S (48GB)
   - **Data Center**: A100 (40/80GB), H100 (80GB)
5. (Optional) Mount network volume at `/runpod-volume`
6. Deploy

### Test Locally

```bash
# Run handler test
docker run --rm -it samsam27/comfyui-serverless:latest python /serverless_worker.py --test

# Interactive shell
docker run --rm -it samsam27/comfyui-serverless:latest bash

# Run with GPU (requires nvidia-docker)
docker run --rm -it --gpus all samsam27/comfyui-serverless:latest bash
```

### Test Endpoint

```bash
ENDPOINT_ID="your-endpoint-id"
RUNPOD_API_KEY="rpa_xxx"

# Sync request (waits for result)
curl -X POST "https://api.runpod.ai/v2/${ENDPOINT_ID}/runsync" \
  -H "Authorization: Bearer ${RUNPOD_API_KEY}" \
  -H "Content-Type: application/json" \
  -d @test_input.json
```

---

## Troubleshooting

### Build Fails with Disk Space Error

```bash
# Cloud builder has limited disk space
# Use local builder instead:
USE_LOCAL_BUILDER=true ./build.sh
```

### Base Image Not Found

The script uses `nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04`. If this fails:
1. Check Docker Hub for available CUDA tags
2. Update the `BASE_IMAGE` in `Dockerfile`

### Tests Fail

```bash
# Run tests manually
docker run --rm samsam27/comfyui-serverless:latest python -c "import runpod; print('OK')"

# Check logs
./build.sh --no-test  # Skip tests, inspect manually
```

### Push Fails

```bash
# Login to Docker Hub
docker login

# Retry
./build.sh
```

### Build Takes Too Long

```bash
# Cloud builder is faster (5-15 min vs 30-60 min)
# Make sure you're not forcing local builder

# Or skip tests for faster iteration
./build.sh --no-test
```
