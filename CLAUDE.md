# CLAUDE.md - Project Guide for AI Assistants

## Project Overview

This is a **fork of [ValyrianTech/ComfyUI_with_Flux](https://github.com/ValyrianTech/ComfyUI_with_Flux)** customized for Runpod.io deployment with network volumes. It includes:
- Pre-configured ComfyUI with custom nodes (ComfyUI Manager, IPAdapter, ControlNet, etc.)
- AI-Toolkit for LoRA training
- Model syncing from Cloudflare R2 storage (custom addition)
- 32+ pre-configured workflows

**Primary Language**: Bash, Python
**License**: MIT (Valyrian Tech 2024)
**Repository**: https://github.com/SamuelD27/ComfyUI_custom

## Secrets

**API keys and secrets are stored in `SECRETS.local.md`** (gitignored, local only).

If this file doesn't exist, create it from the template and add your keys:
- Runpod API Key
- Cloudflare R2 credentials
- HuggingFace token

## Git Workflow for Claude Code Sessions

**IMPORTANT**: Every Claude Code session creates a new worktree/branch. To keep changes synchronized:

### At the START of a new session:
```bash
# Sync with remote first
git fetch origin
git merge origin/main
```

### At the END of a session (before closing):
```bash
# Commit and push changes to remote
git add -A
git commit -m "Description of changes"
git push origin HEAD:main
```

### Quick sync command (run at session start):
```bash
git fetch origin && git merge origin/main --no-edit
```

This ensures all worktrees stay synchronized through the remote repository.

## Current Infrastructure Status

**Network Volume**: Created in CA-MTL-1 datacenter (check via API for current ID)
- Size: 100GB
- Name: comfyui-volume

**Pod Requirements**:
- GPU: A40 recommended ($0.35/hr, 48GB VRAM, medium availability in CA-MTL-1)
- Alternative: RTX A5000 ($0.16/hr, 24GB VRAM) if available
- Ports: `8080/http,8888/http,22/tcp`
- Image: `runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04`
- **CRITICAL**: Set `volumeInGb: 100` to use full network volume (not default 20GB)

## Directory Structure

```
├── comfyui-with-flux/            # Docker config with Flux models included
│   ├── Dockerfile
│   └── flux/                     # Flux model files (.gitkeep)
├── comfyui-without-flux/         # Docker config without large models
│   ├── Dockerfile                # Main Docker build file
│   ├── start-ssh-only.sh         # Main startup script (R2 sync + services)
│   ├── start-original.sh         # User-customizable startup script
│   ├── comfyui-on-workspace.sh   # Persists ComfyUI to /workspace
│   ├── ai-toolkit-on-workspace.sh # Persists AI-Toolkit to /workspace
│   ├── download_*.sh             # Model download scripts (HuggingFace)
│   ├── workflows/                # 32+ pre-configured JSON workflows
│   ├── ai-toolkit/               # LoRA training toolkit
│   └── nginx config files        # Reverse proxy setup
├── examples/                     # API usage examples (Python)
├── build_docker.py               # Docker build script
├── SECRETS.local.md              # Local secrets (gitignored)
└── README.md                     # Documentation
```

## Custom Modifications (vs upstream)

1. **R2 Model Sync** (`start-ssh-only.sh`): Added rclone sync from Cloudflare R2 bucket
2. **Port 8080** (`start-original.sh`): ComfyUI runs on port 8080 for Runpod HTTP proxy
3. **Venv Activation**: Scripts activate `/workspace/venv` if present

## Model Storage (R2 Bucket)

Models are stored in Cloudflare R2 bucket `comfyui-models/` with this structure:
```
s3://comfyui-models/
├── clip/
├── clip_vision/
├── controlnet/
├── diffusion_models/
├── embeddings/
├── ipadapter/
├── loras/
├── pulid/
├── text_encoders/
├── upscale_models/
└── vae/
```

## Environment Variables

### Required for R2 Model Sync
- `R2_ENDPOINT`: Cloudflare R2 endpoint URL
- `R2_ACCESS_KEY_ID`: R2 access key ID
- `R2_SECRET_ACCESS_KEY`: R2 secret access key
- `SYNC_MODELS`: Set to `true` to sync models from R2 on startup

### HuggingFace Downloads (alternative to R2)
- `HF_TOKEN`: HuggingFace token for gated models
- `DOWNLOAD_WAN`: Set to `true` to download Wan 2.1 models
- `DOWNLOAD_FLUX`: Set to `true` to download Flux models

### Optional
- `PUBLIC_KEY`: SSH public key for pod access
- `AI_TOOLKIT_AUTH`: Password for AI-Toolkit UI (default: 'changeme')

## Runpod Setup

### Pod Configuration
1. Use the `comfyui-without-flux` Docker image
2. Attach a network volume to `/workspace`
3. **Expose HTTP port 8080** in pod settings
4. Set environment variables for R2 or HuggingFace

### Access URLs
- ComfyUI: `https://[POD_ID]-8080.proxy.runpod.net`
- JupyterLab: `https://[POD_ID]-8888.proxy.runpod.net`
- AI-Toolkit: `https://[POD_ID]-8675.proxy.runpod.net`

## Key Commands

### Sync Models from R2 (inside container)
The startup script automatically syncs models when `SYNC_MODELS=true`. To manually sync:
```bash
rclone sync r2:comfyui-models/ /workspace/ComfyUI/models/ --progress
```

### LoRA Training
```bash
cd /workspace/ai-toolkit
python3 flux_train_ui.py                    # UI-based training
python3 run.py config/train_lora.yaml       # Command-line training
python3 caption_images.py /workspace/training_set "A photo of X."  # Auto-caption
```

## Architecture

### Service Ports
- **8080**: ComfyUI Web UI (custom, for Runpod proxy)
- **8888**: JupyterLab (file management)
- **7860**: Gradio Apps
- **8675**: AI-Toolkit UI

### Persistent Volume Strategy
- Uses `/workspace` for data persistence across pod restarts
- Scripts move app directories to `/workspace` and symlink back
- Models synced from R2 are cached locally in `/workspace/ComfyUI/models/`

## Important Files

| File | Purpose |
|------|---------|
| `start-ssh-only.sh` | Main startup script with R2 sync |
| `start-original.sh` | User-customizable startup (copied to /workspace) |
| `comfyui-on-workspace.sh` | Moves ComfyUI to /workspace for persistence |
| `ai-toolkit-on-workspace.sh` | Moves AI-Toolkit to /workspace for persistence |
| `Dockerfile` | Docker image build configuration |
| `download_*.sh` | Model download scripts (HuggingFace alternative) |
| `ai-toolkit/train_lora.yaml` | LoRA training config template |
| `examples/api_example.py` | Python API client example |
| `SECRETS.local.md` | Local secrets file (gitignored) |

## Workflow Files

32+ pre-configured workflows in `comfyui-without-flux/workflows/`:
- txt2img, img2img, LoRa
- ControlNet, Inpainting, Outpainting
- Wan 2.1/2.2 Text2Video, Image2Video
- CogVideoX, AdvancedLivePortrait
- FaceSwap, Upscale (LDSR, SUPIR)
- VibeVoice (single/multiple speaker)
- Flux2 Text2Image, ImageEdit

## Custom Nodes to Install

These custom nodes should be cloned to `/workspace/ComfyUI/custom_nodes/`:

| Node | Repository | Purpose |
|------|------------|---------|
| ComfyUI-Manager | `ltdrdata/ComfyUI-Manager` | Node management, model downloads |
| x-flux-comfyui | `XLabs-AI/x-flux-comfyui` | XLabs IPAdapter + ControlNet for Flux |
| ComfyUI-IPAdapter-Flux | `Shakker-Labs/ComfyUI-IPAdapter-Flux` | Shakker-Labs/InstantX IPAdapter for Flux |
| ComfyUI-Impact-Pack | `ltdrdata/ComfyUI-Impact-Pack` | Detailer, Upscaler, SAM integration |
| comfyui_controlnet_aux | `Fannovel16/comfyui_controlnet_aux` | ControlNet preprocessors |
| ComfyUI-GGUF | `city96/ComfyUI-GGUF` | Quantized model support (GGUF) |
| rgthree-comfy | `rgthree/rgthree-comfy` | Power LoRA Loader, utilities |
| ComfyUI-PuLID-Flux | `balazik/ComfyUI-PuLID-Flux` | Face swap/identity preservation for Flux |
| efficiency-nodes-comfyui | `jags111/efficiency-nodes-comfyui` | Batch processing utilities |
| ComfyUI-KJNodes | `kijai/ComfyUI-KJNodes` | Various useful utilities |

## Setup Commands Reference

See `SECRETS.local.md` for commands with API keys filled in.

### Check Network Volume via API
```bash
curl -s -X POST "https://api.runpod.io/graphql" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "query { myself { networkVolumes { id name size dataCenterId } } }"}'
```

### Create Pod via GraphQL (IMPORTANT: volumeInGb must match network volume size)
```bash
curl -s -X POST "https://api.runpod.io/graphql" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation { podFindAndDeployOnDemand(input: { name: \"comfyui-setup\", imageName: \"runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04\", gpuTypeId: \"NVIDIA A40\", gpuCount: 1, volumeInGb: 100, containerDiskInGb: 30, networkVolumeId: \"VOLUME_ID_HERE\", ports: \"8080/http,8888/http,22/tcp\", dataCenterId: \"CA-MTL-1\", startSsh: true }) { id name } }"
  }'
```

### Check Pod Status
```bash
curl -s -X POST "https://api.runpod.io/graphql" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "query { pod(input: {podId: \"POD_ID_HERE\"}) { id name desiredStatus runtime { uptimeInSeconds ports { ip isIpPublic privatePort publicPort type } } } }"}'
```
