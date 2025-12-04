# ComfyUI with Flux - Repository Analysis

## Repository Overview

This repository provides Docker images for running ComfyUI with Flux.1-dev on RunPod.io. It consists of two main image configurations:

1. **comfyui-without-flux** - Base image (~15GB) with ComfyUI and custom nodes, no Flux models
2. **comfyui-with-flux** - Extended image (~35GB) includes Flux.1-dev models

## System Configuration

### Python Environment
- **Python Version**: 3.10+ (system Python with venv)
- **Virtual Environment**: `/opt/venv`
- **Package Manager**: pip + uv (for ComfyUI-Manager compatibility)

### CUDA/PyTorch Stack
- **CUDA Version**: 12.8.0
- **PyTorch Version**: 2.8.0
- **TorchVision**: 0.23.0
- **TorchAudio**: 2.8.0
- **Base Image**: `nvidia/cuda:12.8.0-runtime-ubuntu22.04`

### Directory Structure

```
/ComfyUI/
├── models/
│   ├── checkpoints/          # SD checkpoints
│   ├── clip/                 # CLIP & T5 text encoders
│   ├── controlnet/           # ControlNet models
│   ├── diffusion_models/     # Flux diffusion models (flux1-dev.sft)
│   ├── facerestore_models/   # Face restoration models
│   ├── insightface/          # InsightFace models (inswapper_128.onnx)
│   ├── loras/                # LoRA models
│   ├── LLM/                  # Language models
│   ├── ultralytics/bbox/     # YOLO face detection
│   ├── upscale_models/       # Upscaler models (4x-UltraSharp.pth)
│   ├── vae/                  # VAE models (ae.sft)
│   ├── vibevoice/            # VibeVoice audio models
│   └── xlabs/loras/          # XLabs LoRA models
├── custom_nodes/             # Pre-installed custom nodes
├── input/                    # Input files
├── output/                   # Generated outputs
├── user/default/workflows/   # User workflows
└── web/                      # Web interface

/workspace/                   # Persistent storage (RunPod network volume)
├── ComfyUI/                  # Symlinked from /ComfyUI for persistence
└── ai-toolkit/               # AI-Toolkit for LoRA training
```

## Pre-installed Custom Nodes

The base image includes these custom nodes:

| Node | Purpose |
|------|---------|
| ComfyUI-Manager | Node management and installation |
| ComfyUI-Custom-Scripts | Utility scripts |
| x-flux-comfyui | XLabs Flux integration |
| ComfyUI-Flowty-LDSR | LDSR upscaling |
| ComfyUI-SUPIR | SUPIR upscaling |
| ComfyUI-KJNodes | Utility nodes |
| rgthree-comfy | RGB Three utilities |
| ComfyUI_JPS-Nodes | JPS nodes |
| ComfyUI_Comfyroll_CustomNodes | Comfyroll nodes |
| comfy-plasma | Plasma effects |
| ComfyUI-VideoHelperSuite | Video processing |
| ComfyUI-AdvancedLivePortrait | Live portrait animation |
| ComfyUI-Impact-Pack | Impact pack utilities |
| ComfyUI-Impact-Subpack | Impact subpack |
| comfyui_controlnet_aux | ControlNet preprocessors |
| ComfyUI_UltimateSDUpscale | Ultimate SD upscaler |
| ComfyUI-Easy-Use | Easy use nodes |
| ComfyUI-Florence2 | Florence-2 vision |
| was-node-suite-comfyui | WAS node suite |
| ComfyUI-Logic | Logic nodes |
| ComfyUI_essentials | Essential nodes |
| cg-image-picker | Image picker |
| ComfyUI_LayerStyle | Layer styling |
| comfyui-mixlab-nodes | Mixlab nodes |
| comfyui-reactor-node | Face swap reactor |
| cg-use-everywhere | Use everywhere nodes |
| ComfyUI-CogVideoXWrapper | CogVideoX integration |
| ComfyUI-WanVideoWrapper | Wan2.x video |
| ComfyUI-MelBandRoFormer | Audio separation |
| ComfyUI-Frame-Interpolation | Frame interpolation |
| VibeVoice-ComfyUI | Voice synthesis |
| ComfyUI-segment-anything-2 | SAM2 segmentation |
| ComfyUI-VFI | Video frame interpolation |

## Existing Models (in base image)

### Included in Docker Build
- `/ComfyUI/models/checkpoints/v1-5-pruned-emaonly-fp16.safetensors` - SD 1.5
- `/ComfyUI/models/ultralytics/bbox/face_yolov8m.pt` - Face detection
- `/ComfyUI/models/insightface/inswapper_128.onnx` - Face swapper

### Downloaded via Dockerfile (comfyui-with-flux)
- `/ComfyUI/models/vae/ae.sft` - Flux VAE (~335MB)
- `/ComfyUI/models/diffusion_models/flux1-dev.sft` - Flux model (~23GB)
- `/ComfyUI/models/clip/clip_l.safetensors` - CLIP-L text encoder
- `/ComfyUI/models/clip/t5xxl_fp8_e4m3fn.safetensors` - T5 XXL FP8

## Identified Gaps for Flux Enhancement

### Missing Custom Nodes
1. **ComfyUI-IPAdapter-Flux** - Required for IP-Adapter Flux support
2. **PuLID-ComfyUI** - Required for PuLID face identity

### Missing Models for Full Flux Support

| Model | Location | Source |
|-------|----------|--------|
| Flux IP-Adapter | `/ComfyUI/models/ipadapter/` | InstantX/FLUX.1-dev-IP-Adapter |
| SigLIP Vision | `/ComfyUI/models/clip_vision/` | google/siglip-so400m-patch14-384 |
| PuLID Flux | `/ComfyUI/models/pulid/` | guozinan/PuLID |
| ControlNet Union Pro 2.0 | `/ComfyUI/models/controlnet/` | Shakker-Labs |
| ControlNet Upscaler | `/ComfyUI/models/controlnet/` | jasperai |
| Super Realism LoRA | `/ComfyUI/models/loras/` | strangerzonehf |

### Dependency Issues

1. **NumPy Compatibility**: Many nodes require numpy<2.0 (1.26.x)
2. **ONNX Runtime**: IP-Adapter Flux needs onnxruntime-gpu
3. **InsightFace**: PuLID requires insightface with specific version

## Startup Flow Analysis

Current startup sequence:
1. `start-ssh-only.sh` - Main entrypoint
   - Configures SSH with public key
   - Calls `/comfyui-on-workspace.sh` - Moves ComfyUI to /workspace
   - Calls `/ai-toolkit-on-workspace.sh` - Moves AI-Toolkit to /workspace
   - Logs into HuggingFace if HF_TOKEN is set
   - Starts AI-Toolkit UI on port 8675
   - Conditionally downloads models based on env vars
   - Starts nginx reverse proxy
   - Starts JupyterLab on port 8888
   - Runs file check
   - Executes user script `/workspace/start_user.sh`
   - Launches ComfyUI via start_user.sh

## Recommendations

1. **Create Enhanced Startup Script**: Add comprehensive model downloading with progress
2. **Add Validation Script**: Pre-flight checks for all dependencies
3. **Pin Dependencies**: Lock numpy, onnxruntime, insightface versions
4. **Add IPAdapter-Flux Node**: Clone and install the custom node
5. **Idempotent Downloads**: Skip already-downloaded models
6. **Comprehensive Error Handling**: Log failures and provide troubleshooting

## Port Mappings

| Port | Service |
|------|---------|
| 8188 | ComfyUI |
| 8888 | JupyterLab |
| 7860 | Gradio (unused) |
| 8675 | AI-Toolkit UI |
