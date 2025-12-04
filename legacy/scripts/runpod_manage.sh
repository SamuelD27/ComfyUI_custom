#!/bin/bash
set -euo pipefail

# =============================================================================
# RunPod Management Script
# =============================================================================
# Manages network volumes and pods for ComfyUI deployment.
# Usage: ./runpod_manage.sh <command> [options]
# =============================================================================

# Load secrets if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../.secrets" ]]; then
    source "${SCRIPT_DIR}/../.secrets"
fi

# Verify API key
if [[ -z "${RUNPOD_API_KEY:-}" ]]; then
    echo "ERROR: RUNPOD_API_KEY not set"
    echo "Either set it in environment or create .secrets file"
    exit 1
fi

# RunPod API base URL
RUNPOD_API="https://api.runpod.io/graphql"

# Helper function for GraphQL queries
runpod_query() {
    local query=$1
    curl -s -X POST "$RUNPOD_API" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${RUNPOD_API_KEY}" \
        -d "{\"query\": \"$query\"}"
}

# List available GPU types
list_gpus() {
    echo "Fetching available GPU types..."
    local query='query { gpuTypes { id displayName memoryInGb secureCloud communityCloud lowestPrice { minimumBidPrice } } }'
    runpod_query "$query" | python3 -c "
import sys, json
data = json.load(sys.stdin)
gpus = data.get('data', {}).get('gpuTypes', [])
print(f'{'GPU ID':<25} {'Name':<30} {'VRAM':<8} {'Min Price':>10}')
print('-' * 75)
for gpu in sorted(gpus, key=lambda x: x.get('lowestPrice', {}).get('minimumBidPrice', 999) or 999):
    price = gpu.get('lowestPrice', {}).get('minimumBidPrice', 'N/A')
    if price != 'N/A':
        price = f'\${price:.3f}/hr'
    print(f\"{gpu['id']:<25} {gpu['displayName']:<30} {gpu['memoryInGb']:<8} {price:>10}\")
"
}

# List network volumes
list_volumes() {
    echo "Fetching network volumes..."
    local query='query { myself { networkVolumes { id name size dataCenterId } } }'
    runpod_query "$query" | python3 -c "
import sys, json
data = json.load(sys.stdin)
volumes = data.get('data', {}).get('myself', {}).get('networkVolumes', [])
print(f'{'Volume ID':<25} {'Name':<25} {'Size (GB)':<10} {'Data Center':<15}')
print('-' * 75)
for vol in volumes:
    print(f\"{vol['id']:<25} {vol['name']:<25} {vol['size']:<10} {vol['dataCenterId']:<15}\")
"
}

# Create a network volume
create_volume() {
    local name="${1:-comfyui-models}"
    local size="${2:-75}"  # Default 75GB
    local datacenter="${3:-US-OR-1}"  # Oregon by default

    echo "Creating network volume: $name ($size GB) in $datacenter..."

    local query="mutation { createNetworkVolume(input: { name: \\\"$name\\\", size: $size, dataCenterId: \\\"$datacenter\\\" }) { id name size dataCenterId } }"

    runpod_query "$query" | python3 -c "
import sys, json
data = json.load(sys.stdin)
vol = data.get('data', {}).get('createNetworkVolume', {})
if vol:
    print(f\"Created volume: {vol['id']}\")
    print(f\"  Name: {vol['name']}\")
    print(f\"  Size: {vol['size']} GB\")
    print(f\"  Data Center: {vol['dataCenterId']}\")
else:
    errors = data.get('errors', [])
    print(f\"Error: {errors}\")
"
}

# Create a pod
create_pod() {
    local gpu_type="${1:-NVIDIA RTX 4090}"
    local volume_id="${2:-}"
    local name="${3:-comfyui-flux}"

    # Docker image from Docker Hub (you'll need to push your image there)
    local image="valyriantech/comfyui-without-flux:latest"

    echo "Creating pod: $name with $gpu_type..."

    # Build the volume mount if provided
    local volume_mount=""
    if [[ -n "$volume_id" ]]; then
        volume_mount=", networkVolumeId: \\\"$volume_id\\\""
    fi

    # Environment variables for R2 download
    local env_vars="[
        {key: \\\"R2_ACCESS_KEY_ID\\\", value: \\\"${R2_ACCESS_KEY_ID}\\\"},
        {key: \\\"R2_SECRET_ACCESS_KEY\\\", value: \\\"${R2_SECRET_ACCESS_KEY}\\\"},
        {key: \\\"R2_ENDPOINT\\\", value: \\\"${R2_ENDPOINT}\\\"},
        {key: \\\"DOWNLOAD_FLUX\\\", value: \\\"true\\\"}
    ]"

    local query="mutation {
        podFindAndDeployOnDemand(input: {
            name: \\\"$name\\\",
            imageName: \\\"$image\\\",
            gpuTypeId: \\\"$gpu_type\\\"$volume_mount,
            volumeInGb: 20,
            containerDiskInGb: 20,
            minVcpuCount: 2,
            minMemoryInGb: 16,
            ports: \\\"8188/http,22/tcp,8888/http\\\",
            env: $env_vars
        }) {
            id
            name
            imageName
            gpuTypeId
        }
    }"

    runpod_query "$query" | python3 -c "
import sys, json
data = json.load(sys.stdin)
pod = data.get('data', {}).get('podFindAndDeployOnDemand', {})
if pod:
    print(f\"Created pod: {pod.get('id')}\")
    print(f\"  Name: {pod.get('name')}\")
    print(f\"  Image: {pod.get('imageName')}\")
    print(f\"  GPU: {pod.get('gpuTypeId')}\")
else:
    errors = data.get('errors', [])
    print(f\"Error: {errors}\")
    print(f\"Full response: {data}\")
"
}

# List pods
list_pods() {
    echo "Fetching pods..."
    local query='query { myself { pods { id name imageName gpuTypeId desiredStatus runtime { uptimeInSeconds } } } }'
    runpod_query "$query" | python3 -c "
import sys, json
data = json.load(sys.stdin)
pods = data.get('data', {}).get('myself', {}).get('pods', [])
print(f'{'Pod ID':<25} {'Name':<20} {'GPU':<20} {'Status':<15} {'Uptime':<10}')
print('-' * 90)
for pod in pods:
    uptime = pod.get('runtime', {}).get('uptimeInSeconds', 0) or 0
    hours = uptime // 3600
    mins = (uptime % 3600) // 60
    print(f\"{pod['id']:<25} {pod['name']:<20} {pod['gpuTypeId']:<20} {pod['desiredStatus']:<15} {hours}h {mins}m\")
"
}

# Stop a pod
stop_pod() {
    local pod_id=$1
    echo "Stopping pod: $pod_id..."
    local query="mutation { podStop(input: { podId: \\\"$pod_id\\\" }) { id desiredStatus } }"
    runpod_query "$query"
}

# Terminate a pod
terminate_pod() {
    local pod_id=$1
    echo "Terminating pod: $pod_id..."
    local query="mutation { podTerminate(input: { podId: \\\"$pod_id\\\" }) }"
    runpod_query "$query"
}

# Help
show_help() {
    echo "RunPod Management Script"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  gpus                    - List available GPU types with prices"
    echo "  volumes                 - List network volumes"
    echo "  create-volume [name] [size] [datacenter]"
    echo "                          - Create network volume (default: 75GB in US-OR-1)"
    echo "  pods                    - List pods"
    echo "  create-pod [gpu] [volume_id] [name]"
    echo "                          - Create a pod (default: RTX 4090)"
    echo "  stop <pod_id>           - Stop a pod"
    echo "  terminate <pod_id>      - Terminate a pod"
    echo ""
    echo "Examples:"
    echo "  $0 gpus"
    echo "  $0 create-volume comfyui-models 75 US-OR-1"
    echo "  $0 create-pod 'NVIDIA RTX 4090' vol_xxx comfyui-test"
    echo ""
    echo "GPU type examples (use quotes):"
    echo "  'NVIDIA RTX 4090'       - \$0.44/hr (24GB) - Good for testing"
    echo "  'NVIDIA RTX A6000'      - \$0.79/hr (48GB) - Good for large models"
    echo "  'NVIDIA H100 PCIe'      - \$2.49/hr (80GB) - Maximum performance"
}

# Main
case "${1:-help}" in
    gpus)
        list_gpus
        ;;
    volumes)
        list_volumes
        ;;
    create-volume)
        create_volume "${2:-comfyui-models}" "${3:-75}" "${4:-US-OR-1}"
        ;;
    pods)
        list_pods
        ;;
    create-pod)
        create_pod "${2:-NVIDIA RTX 4090}" "${3:-}" "${4:-comfyui-flux}"
        ;;
    stop)
        if [[ -z "${2:-}" ]]; then
            echo "Usage: $0 stop <pod_id>"
            exit 1
        fi
        stop_pod "$2"
        ;;
    terminate)
        if [[ -z "${2:-}" ]]; then
            echo "Usage: $0 terminate <pod_id>"
            exit 1
        fi
        terminate_pod "$2"
        ;;
    *)
        show_help
        ;;
esac
