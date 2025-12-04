# ComfyUI Serverless Project - Claude Code Context

## Project Overview

This is a customized ComfyUI setup for Flux.1-dev image generation, designed for **RunPod Serverless** deployment. The project provides a containerized worker that processes image generation jobs via the RunPod Serverless API.

## Architecture

### Serverless vs Pod Deployment

This project uses **RunPod Serverless** (not long-running Pods):
- **Serverless**: Pay per request, auto-scaling, cold starts, no idle costs
- **Pod (legacy)**: Long-running, persistent, manual scaling, pay for uptime

The old Pod-based infrastructure has been archived in the `legacy/` folder.

### Key Files

```
ComfyUI_custom/
├── serverless_worker.py    # RunPod handler function
├── requirements.txt        # Python dependencies
├── test_input.json         # Test workflow for validation
├── src/
│   ├── start.sh            # Container startup script
│   └── extra_model_paths.yaml  # Network volume model paths
├── docker/                 # Docker Hub deployment (optional)
│   ├── Dockerfile          # Serverless worker Docker image
│   ├── build.sh            # Build and push script
│   └── BUILD_COMMANDS.md   # Build documentation
├── examples/
│   ├── api_example.py      # Client example
│   └── workflow_api_format.json  # Example Flux workflow
└── legacy/                 # Archived Pod-style infrastructure
```

---

## RunPod Serverless Deployment

### Option A: GitHub Repo (Recommended)

RunPod can build directly from this GitHub repository:

1. Go to https://www.runpod.io/console/serverless
2. Click **"New Endpoint"**
3. Select **"GitHub"** as the source
4. Connect your GitHub account and select this repository
5. Configure:
   - **Branch**: `main`
   - **Dockerfile Path**: `docker/Dockerfile`
   - **GPU**: Any with 24GB+ VRAM (RTX 3090/4090, A5000, A6000, L40, A100, H100)
6. Deploy

### Option B: Docker Hub

Build and push the image manually:

```bash
# From the docker/ directory
cd docker && ./build.sh
```

Then create endpoint with image: `samsam27/comfyui-serverless:latest`

### Create RunPod Serverless Endpoint

1. Go to [RunPod Console](https://www.runpod.io/console/serverless)
2. Click **"New Endpoint"**
3. Configure:
   - **Docker Image**: `YOUR_DOCKERHUB_USER/comfyui-serverless:latest`
   - **GPU Type**: Select based on model requirements (RTX 4090, A6000, etc.)
   - **GPU Count**: 1 (usually sufficient)
   - **Environment Variables** (optional):
     - `HF_TOKEN`: Your Hugging Face token (for gated models)
   - **Container Disk**: 20GB minimum
   - **Volume**: Mount network volume with models (recommended)
4. Click **"Deploy"**

### Step 4: Test the Endpoint

```bash
# Get your endpoint ID from the RunPod console
ENDPOINT_ID="your-endpoint-id"
RUNPOD_API_KEY="your-api-key"

# Run a test job
curl -X POST "https://api.runpod.ai/v2/${ENDPOINT_ID}/run" \
  -H "Authorization: Bearer ${RUNPOD_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "input": {
      "workflow": { ... },
      "prompt": "A beautiful sunset over mountains"
    }
  }'
```

---

## API Reference

### Input Schema

```json
{
  "input": {
    "workflow": { ... },           // Required: ComfyUI workflow in API format
    "prompt": "text override",     // Optional: Override text in prompt node
    "prompt_node_id": "6",         // Optional: Node ID for prompt (default: "6")
    "seed": 12345,                 // Optional: Override random seed
    "seed_node_id": "25",          // Optional: Node ID for seed (default: "25")
    "width": 1024,                 // Optional: Image width
    "height": 1024,                // Optional: Image height
    "size_node_id": "27"           // Optional: Node ID for size (default: "27")
  }
}
```

### Output Schema

**Success:**
```json
{
  "status": "success",
  "images": ["base64_encoded_image_1", "base64_encoded_image_2"],
  "filenames": ["ComfyUI_00001_.png", "ComfyUI_00002_.png"],
  "execution_time_seconds": 12.5,
  "prompt_id": "abc123"
}
```

**Error:**
```json
{
  "status": "error",
  "error_type": "validation|timeout|internal",
  "error": "Error message",
  "execution_time_seconds": 0.5
}
```

### Workflow Format

The workflow must be in ComfyUI **API format** (not the GUI workflow format). Export from ComfyUI:
1. Open your workflow in ComfyUI
2. Click **"Save (API Format)"** or use the API export option
3. Use the resulting JSON as the `workflow` field

See `examples/workflow_api_format.json` for a complete Flux example.

---

## Local Testing

### Test the Handler Locally

```bash
# Test with default workflow
python serverless_worker.py --test

# Test with custom input
python serverless_worker.py --test_input '{"workflow": {...}, "prompt": "test"}'

# Or set environment variable
export MODE_TO_RUN=test
python serverless_worker.py
```

### Run ComfyUI Locally (for development)

```bash
# Clone ComfyUI
git clone https://github.com/comfyanonymous/ComfyUI.git
cd ComfyUI

# Install dependencies
pip install -r requirements.txt

# Run server
python main.py --listen 0.0.0.0 --port 8188
```

---

## Model Management

### Baking Models into Docker Image

For faster cold starts, you can bake models directly into the image. Add to Dockerfile:

```dockerfile
# Download models during build
RUN mkdir -p /ComfyUI/models/diffusion_models && \
    wget -O /ComfyUI/models/diffusion_models/flux1-dev.safetensors \
    "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors"
```

**Warning**: This creates a very large image (30GB+). Consider using RunPod Network Volumes instead.

### Using Network Volumes (Recommended)

1. Create a Network Volume in RunPod console
2. Upload models to the volume
3. Mount the volume when creating the endpoint
4. Models persist across invocations

### Downloading Models at Runtime

Set environment variables in RunPod:
- `HF_TOKEN`: Hugging Face token for gated models
- `DOWNLOAD_MODELS`: Set to "true" to enable runtime downloads

---

## Cloudflare R2 Storage

Models are backed up to R2 for persistence.

- **Bucket**: `comfyui-models`
- **Endpoint**: Configured in `.secrets` file

### R2 Bucket Contents

```
comfyui-models/
├── clip/
├── clip_vision/
├── controlnet/
├── diffusion_models/    # flux1-dev.safetensors, flux1-kontext-dev.safetensors
├── ipadapter/
├── loras/
├── pulid/
├── upscale_models/
└── vae/
```

---

## Credentials

All API keys and secrets are stored in `.secrets` (gitignored):

```bash
# RunPod
RUNPOD_API_KEY=...

# Cloudflare R2
R2_ACCESS_KEY_ID=...
R2_SECRET_ACCESS_KEY=...
R2_ENDPOINT=...

# Hugging Face (for gated models)
HF_TOKEN=...
```

---

## Breaking Changes from Pod Deployment

| Feature | Pod (legacy) | Serverless (current) |
|---------|--------------|----------------------|
| Deployment | Long-running container | Request-based invocation |
| Access | HTTP endpoints, SSH | RunPod API only |
| Ports | 8188, 8888, 22 | None exposed |
| Billing | Per-hour | Per-request (GPU-seconds) |
| State | Persistent | Ephemeral (use volumes) |
| JupyterLab | Available | Not included |

If you need the old Pod-style deployment, see the `legacy/` folder.

---

## Troubleshooting

### Cold Start Timeouts

If jobs timeout during cold starts:
1. Increase the **Active Workers** setting in RunPod
2. Use a Network Volume with pre-loaded models
3. Bake smaller models into the Docker image

### Missing Models

Ensure models are available:
1. Mount a Network Volume with models
2. Or bake models into Docker image
3. Or configure runtime download via `HF_TOKEN`

### Workflow Errors

1. Verify workflow is in **API format** (not GUI format)
2. Check node IDs match your override parameters
3. Test workflow locally in ComfyUI before deploying

---

## Notes

1. **Flux1-dev location**: The model works in `/models/checkpoints/` for standard checkpoint loading, OR in `/models/diffusion_models/` for UNet-only loading.

2. **IP-Adapter for Flux**: Requires `ComfyUI-IPAdapter-Flux` node and models in `/models/ipadapter-flux/`.

3. **CLIP Vision for Flux IP-Adapter**: Needs `siglip-so400m-patch14-384` model in `/models/clip_vision/`.

4. **Cold starts**: First request may take 30-60 seconds while ComfyUI initializes.

5. **GPU memory**: Flux models require 24GB+ VRAM. Use RTX 4090, A6000, or H100.
