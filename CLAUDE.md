# ComfyUI Custom Project - Claude Code Context

## Project Overview

This is a customized ComfyUI setup for Flux.1-dev image generation, running on RunPod with a persistent network volume. The project is based on ValyrianTech's ComfyUI_with_Flux template but has been customized for specific workflows.

## Infrastructure

### RunPod Setup
- **Network Volume ID**: `6mojc04f9w` (US-KS-2 datacenter)
- **Volume Size**: 150GB
- **Preferred GPU**: RTX PRO 6000 (96GB VRAM) or RTX A6000 (48GB)
- **Docker Image**: `runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04`
- **Required Ports**: `8188/http` (ComfyUI), `8888/http` (JupyterLab), `22/tcp` (SSH)

### Cloudflare R2 Storage
Models are backed up to R2 for persistence across pod recreations.
- **Bucket**: `comfyui-models`
- **Endpoint**: Configured in `.secrets` file

### Credentials Location
All API keys and secrets are stored in `.secrets` (gitignored):
- `RUNPOD_API_KEY`
- `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT`

## Network Volume Structure

```
/workspace/
├── ComfyUI/
│   ├── models/
│   │   ├── checkpoints/      # Base models (flux1-dev.safetensors - 23GB)
│   │   ├── clip/             # CLIP models (clip_l, t5xxl_fp8)
│   │   ├── clip_vision/      # CLIP vision models (sigclip)
│   │   ├── controlnet/       # ControlNet models (union, upscaler)
│   │   ├── ipadapter/        # IP-Adapter models
│   │   ├── ipadapter-flux/   # Flux-specific IP-Adapter (ip-adapter.bin)
│   │   ├── loras/            # LoRA models
│   │   ├── pulid/            # PuLID face models
│   │   ├── unet/             # UNet/diffusion models
│   │   ├── upscale_models/   # Upscalers (4x-UltraSharp)
│   │   └── vae/              # VAE models (ae.safetensors)
│   ├── custom_nodes/         # ComfyUI extensions
│   └── user/default/workflows/  # Saved workflows (.json)
├── comfyui.log               # ComfyUI server log
└── download.log              # Model download log
```

## Installed Models

### Base Model
- `flux1-dev.safetensors` (23GB) - in `/models/checkpoints/`

### CLIP/Text Encoders
- `clip_l.safetensors` (235MB)
- `t5xxl_fp8_e4m3fn.safetensors` (4.6GB)

### ControlNet
- `flux_controlnet_union_instantx.safetensors` (6.2GB)
- `flux_controlnet_union_pro_2.0.safetensors` (4GB)
- `flux_controlnet_upscaler_jasperai.safetensors` (3.4GB)

### IP-Adapter
- `ip-adapter.bin` (5GB) - in `/models/ipadapter-flux/`
- `sigclip_vision_patch14_384/` - CLIP vision model directory

### LoRAs
- `GracePenelopeTargaryenV5.safetensors` (165MB)
- `VideoAditor_flux_realism_lora.safetensors` (22MB)
- `Xlabs-AI_flux-RealismLora.safetensors` (22MB)
- Custom training LoRAs (my_first_lora_v1, v2)

### Other
- VAE: `ae.safetensors` (320MB)
- Upscaler: `4x-UltraSharp.pth` (64MB)
- PuLID: `pulid_flux_v0.9.1.safetensors`, `EVA02_CLIP_L_336_psz14_s6B.pt`

## Custom Nodes Installed

### Working
- **ComfyUI-Manager** - Node manager (requires `pip install gitpython`)
- **ComfyUI-IPAdapter-Flux** - Flux IP-Adapter support (Shakker-Labs)
- **ComfyUI_IPAdapter_plus** - General IP-Adapter
- **ComfyUI-FluxTrainer** - LoRA training in ComfyUI (kijai)
- **ComfyUI_Flux_Lora_Merger** - Merge Flux LoRAs
- **ComfyUI_essentials** - Essential utility nodes
- **rgthree-comfy** - QoL improvements
- **ComfyUI-Custom-Scripts** - Utility scripts
- **sd-dynamic-thresholding** - CFG improvements

### May Need Dependencies
These nodes may fail to import without additional pip packages:
- `comfyui_controlnet_aux` - needs `opencv-python`
- `ComfyUI-VideoHelperSuite` - needs `opencv-python`, `imageio-ffmpeg`
- `ComfyUI-KJNodes` - needs various packages
- `was-node-suite-comfyui` - needs various packages
- `ComfyUI-GGUF` - GGUF model support

## Common Operations

### Create a New Pod
```bash
# Read API key from .secrets
source .secrets

# Create pod via GraphQL API
curl -X POST "https://api.runpod.io/graphql" \
  -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -d '{"query": "mutation { podFindAndDeployOnDemand(input: {
    gpuTypeId: \"NVIDIA RTX PRO 6000 Blackwell Server Edition\",
    volumeInGb: 150,
    networkVolumeId: \"6mojc04f9w\",
    ports: \"8188/http,8888/http,22/tcp\",
    imageName: \"runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04\",
    volumeMountPath: \"/workspace\",
    startSsh: true
  }) { id } }"}'
```

### SSH to Pod
```bash
ssh root@<IP> -p <PORT> -i ~/.ssh/id_ed25519
```

### Start ComfyUI
```bash
cd /workspace/ComfyUI
pip install -r requirements.txt
nohup python main.py --listen 0.0.0.0 --port 8188 > /workspace/comfyui.log 2>&1 &
```

### Configure rclone for R2
```bash
mkdir -p ~/.config/rclone
cat > ~/.config/rclone/rclone.conf << 'EOF'
[r2]
type = s3
provider = Cloudflare
access_key_id = <from .secrets>
secret_access_key = <from .secrets>
endpoint = <from .secrets>
acl = private
EOF
```

### Sync Models from R2
```bash
rclone copy r2:comfyui-models/diffusion_models/flux1-dev.safetensors /workspace/ComfyUI/models/checkpoints/
```

### Upload Models to R2
```bash
rclone copy /workspace/ComfyUI/models/<folder>/<file> r2:comfyui-models/<folder>/
```

## Workflows

Workflows are stored in `/workspace/ComfyUI/user/default/workflows/`:
- `Test.json` - Basic test workflow
- `Controlnet-test.json` - ControlNet workflow
- `training.json` - LoRA training workflow

## R2 Bucket Contents

The `comfyui-models` bucket contains backups of all models:
```
clip/
clip_vision/
controlnet/
diffusion_models/    # flux1-dev.safetensors, flux1-kontext-dev.safetensors
ipadapter/
loras/
pulid/
upscale_models/
vae/
```

## Notes

1. **Flux1-dev location**: The model works in `/models/checkpoints/` for standard checkpoint loading, OR in `/models/unet/` for UNet-only loading. Currently placed in checkpoints.

2. **IP-Adapter for Flux**: Requires `ComfyUI-IPAdapter-Flux` node and models in `/models/ipadapter-flux/` (not regular ipadapter folder).

3. **CLIP Vision for Flux IP-Adapter**: Needs full `siglip-so400m-patch14-384` model directory in `/models/clip_vision/`.

4. **Pod termination**: Network volume persists, but ComfyUI process stops. Need to restart ComfyUI on new pod.

5. **Missing dependencies**: Some custom nodes fail on fresh pods. Install with:
   ```bash
   pip install opencv-python gitpython imageio-ffmpeg
   ```
