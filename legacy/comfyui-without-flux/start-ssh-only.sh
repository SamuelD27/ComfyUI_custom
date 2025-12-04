#!/bin/bash

echo "pod started"

if [[ $PUBLIC_KEY ]]
then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    cd ~/.ssh
    echo $PUBLIC_KEY >> authorized_keys
    chmod 700 -R ~/.ssh
    cd /
    service ssh start
fi

# Move text-generation-webui's folder to $VOLUME so models and all config will persist
/comfyui-on-workspace.sh

# Move ai-toolkit's folder to $VOLUME so models and all config will persist
/ai-toolkit-on-workspace.sh

if [[ -z "${HF_TOKEN}" ]] || [[ "${HF_TOKEN}" == "enter_your_huggingface_token_here" ]]
then
    echo "HF_TOKEN is not set"
else
    echo "HF_TOKEN is set, logging in..."
    huggingface-cli login --token ${HF_TOKEN}
fi

# Sync models from R2 bucket
sync_models_from_r2() {
    echo "Syncing models from R2 bucket..."

    # Ensure required environment variables are set
    if [[ -z "${R2_ENDPOINT}" ]] || [[ -z "${R2_ACCESS_KEY_ID}" ]] || [[ -z "${R2_SECRET_ACCESS_KEY}" ]]; then
        echo "WARNING: R2 credentials not set. Skipping model sync."
        echo "Set R2_ENDPOINT, R2_ACCESS_KEY_ID, and R2_SECRET_ACCESS_KEY environment variables."
        return 1
    fi

    # Configure rclone for R2
    mkdir -p ~/.config/rclone
    cat > ~/.config/rclone/rclone.conf << EOF
[r2]
type = s3
provider = Cloudflare
access_key_id = ${R2_ACCESS_KEY_ID}
secret_access_key = ${R2_SECRET_ACCESS_KEY}
endpoint = ${R2_ENDPOINT}
acl = private
EOF

    # Sync models from R2 to ComfyUI models directory
    # Uses --ignore-existing to skip files that already exist locally
    echo "Syncing models from r2:comfyui-models/ to /workspace/ComfyUI/models/"
    rclone sync r2:comfyui-models/ /workspace/ComfyUI/models/ \
        --ignore-existing \
        --progress \
        --transfers 4 \
        --checkers 8 \
        --log-level INFO

    if [ $? -eq 0 ]; then
        echo "Model sync completed successfully"
    else
        echo "WARNING: Model sync encountered errors"
    fi
}

# Sync models from R2 if SYNC_MODELS is set to true
if [[ "${SYNC_MODELS}" == "true" ]]; then
    sync_models_from_r2
fi

# Start AI-Toolkit UI in the background (prebuilt artifacts preferred)
if [ -d "/workspace/ai-toolkit/ui" ]; then
    echo "Starting AI-Toolkit UI in background on port 8675"
    cd /workspace/ai-toolkit/ui
    if [ -d .next ] && [ -f dist/worker.js ]; then
        echo "Prebuilt artifacts found. Running: npm run start"
        nohup npm run start > /workspace/ai-toolkit/ui/server.log 2>&1 &
    else
        echo "Prebuilt artifacts not found. Falling back to: npm run build_and_start (this may take a while)"
        nohup npm run build_and_start > /workspace/ai-toolkit/ui/server.log 2>&1 &
    fi
    cd - >/dev/null 2>&1 || true
else
    echo "AI-Toolkit UI directory not found at /workspace/ai-toolkit/ui; skipping UI startup"
fi

# Check and run the download scripts based on environment variables
if [[ "${DOWNLOAD_WAN}" == "true" ]]; then
    /download_wan2.1.sh
fi

if [[ "${DOWNLOAD_FLUX}" == "true" ]]; then
    /download_Files.sh
fi

# Start nginx as reverse proxy to enable api access
service nginx start

# Start JupyterLab
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.allow_origin='*' &
echo "JupyterLab started"

# Check if the flux model is present
bash /check_files.sh

# Check if there is a venv directory, if so, activate it
if [ -d "/workspace/venv" ]; then
    echo "venv directory found, activating it"
    source /workspace/venv/bin/activate
fi

# Check if user's script exists in /workspace
if [ ! -f /workspace/start_user.sh ]; then
    # If not, copy the original script to /workspace
    cp /start-original.sh /workspace/start_user.sh
fi

# Execute the user's script
bash /workspace/start_user.sh

sleep infinity
