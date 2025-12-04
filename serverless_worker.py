#!/usr/bin/env python3
"""
RunPod Serverless Worker for ComfyUI
=====================================
Based on the official runpod-workers/worker-comfyui implementation.

This worker handles image generation requests via ComfyUI workflows using
WebSocket communication for reliable status monitoring.

Input Schema:
    {
        "workflow": { ... },           # ComfyUI workflow in API format (required)
        "images": [                    # Optional: input images to upload
            {"name": "input.png", "image": "base64_or_data_uri"}
        ]
    }

Output Schema:
    {
        "images": [
            {"filename": "ComfyUI_00001_.png", "type": "base64", "data": "..."}
        ],
        "errors": ["optional error messages"]
    }
"""

import os
import sys
import json
import time
import base64
import uuid
import tempfile
import traceback
import subprocess
from io import BytesIO
from typing import Optional
import logging

import requests

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
logger = logging.getLogger("worker-comfyui")

# =============================================================================
# Configuration
# =============================================================================

# ComfyUI server settings
COMFY_HOST = os.environ.get("COMFY_HOST", "127.0.0.1:8188")
COMFYUI_DIR = os.environ.get("COMFYUI_DIR", "/comfyui")

# API check settings
COMFY_API_AVAILABLE_INTERVAL_MS = 50
COMFY_API_AVAILABLE_MAX_RETRIES = 500

# WebSocket reconnection settings
WEBSOCKET_RECONNECT_ATTEMPTS = int(os.environ.get("WEBSOCKET_RECONNECT_ATTEMPTS", 5))
WEBSOCKET_RECONNECT_DELAY_S = int(os.environ.get("WEBSOCKET_RECONNECT_DELAY_S", 3))

# Optional S3 upload (set BUCKET_ENDPOINT_URL to enable)
BUCKET_ENDPOINT_URL = os.environ.get("BUCKET_ENDPOINT_URL")

# Global ComfyUI process reference
comfy_process = None


# =============================================================================
# Helper Functions
# =============================================================================

def check_server(url: str, retries: int = 500, delay: int = 50) -> bool:
    """
    Check if a server is reachable via HTTP GET request.

    Args:
        url: The URL to check
        retries: Number of retry attempts
        delay: Delay in milliseconds between retries

    Returns:
        True if server is reachable, False otherwise
    """
    logger.info(f"Checking API server at {url}...")

    for i in range(retries):
        try:
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                logger.info("API is reachable")
                return True
        except requests.Timeout:
            pass
        except requests.RequestException:
            pass

        time.sleep(delay / 1000)

    logger.error(f"Failed to connect to server at {url} after {retries} attempts")
    return False


def start_comfyui_server():
    """Start the ComfyUI server as a background process."""
    global comfy_process

    if comfy_process is not None and comfy_process.poll() is None:
        logger.info("ComfyUI server already running")
        return

    logger.info(f"Starting ComfyUI server from {COMFYUI_DIR}...")

    comfy_process = subprocess.Popen(
        [
            sys.executable, "main.py",
            "--disable-auto-launch",
            "--disable-metadata",
            "--listen", "127.0.0.1",
            "--port", "8188"
        ],
        cwd=COMFYUI_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT
    )

    # Wait for server to be ready
    if not check_server(
        f"http://{COMFY_HOST}/",
        COMFY_API_AVAILABLE_MAX_RETRIES,
        COMFY_API_AVAILABLE_INTERVAL_MS
    ):
        raise RuntimeError("ComfyUI server failed to start")


def validate_input(job_input: dict) -> tuple[Optional[dict], Optional[str]]:
    """
    Validate the input for the handler function.

    Returns:
        Tuple of (validated_data, error_message)
    """
    if job_input is None:
        return None, "Please provide input"

    # Handle string input (parse as JSON)
    if isinstance(job_input, str):
        try:
            job_input = json.loads(job_input)
        except json.JSONDecodeError:
            return None, "Invalid JSON format in input"

    # Validate workflow
    workflow = job_input.get("workflow")
    if workflow is None:
        return None, "Missing 'workflow' parameter"

    if not isinstance(workflow, dict):
        return None, "'workflow' must be a JSON object"

    if len(workflow) == 0:
        return None, "'workflow' cannot be empty"

    # Validate images if provided
    images = job_input.get("images")
    if images is not None:
        if not isinstance(images, list):
            return None, "'images' must be a list"
        for img in images:
            if not isinstance(img, dict):
                return None, "Each image must be an object"
            if "name" not in img or "image" not in img:
                return None, "'images' must contain objects with 'name' and 'image' keys"

    return {
        "workflow": workflow,
        "images": images
    }, None


def upload_images(images: list) -> dict:
    """
    Upload base64 encoded images to ComfyUI's input folder.

    Args:
        images: List of {"name": str, "image": str} dicts

    Returns:
        Dict with status, message, and details
    """
    if not images:
        return {"status": "success", "message": "No images to upload", "details": []}

    responses = []
    errors = []

    logger.info(f"Uploading {len(images)} image(s)...")

    for image in images:
        try:
            name = image["name"]
            image_data = image["image"]

            # Strip Data URI prefix if present
            if "," in image_data:
                base64_data = image_data.split(",", 1)[1]
            else:
                base64_data = image_data

            blob = base64.b64decode(base64_data)

            # Upload to ComfyUI
            files = {
                "image": (name, BytesIO(blob), "image/png"),
                "overwrite": (None, "true"),
            }

            response = requests.post(
                f"http://{COMFY_HOST}/upload/image",
                files=files,
                timeout=30
            )
            response.raise_for_status()

            responses.append(f"Successfully uploaded {name}")
            logger.info(f"Successfully uploaded {name}")

        except base64.binascii.Error as e:
            error_msg = f"Error decoding base64 for {image.get('name', 'unknown')}: {e}"
            logger.error(error_msg)
            errors.append(error_msg)
        except requests.RequestException as e:
            error_msg = f"Error uploading {image.get('name', 'unknown')}: {e}"
            logger.error(error_msg)
            errors.append(error_msg)
        except Exception as e:
            error_msg = f"Unexpected error uploading {image.get('name', 'unknown')}: {e}"
            logger.error(error_msg)
            errors.append(error_msg)

    if errors:
        return {"status": "error", "message": "Some images failed to upload", "details": errors}

    return {"status": "success", "message": "All images uploaded successfully", "details": responses}


def queue_workflow(workflow: dict, client_id: str) -> dict:
    """
    Queue a workflow for processing by ComfyUI.

    Returns:
        Response JSON containing prompt_id
    """
    payload = {"prompt": workflow, "client_id": client_id}
    data = json.dumps(payload).encode("utf-8")

    response = requests.post(
        f"http://{COMFY_HOST}/prompt",
        data=data,
        headers={"Content-Type": "application/json"},
        timeout=30
    )

    # Handle validation errors
    if response.status_code == 400:
        logger.error(f"ComfyUI returned 400: {response.text}")
        try:
            error_data = response.json()
            error_msg = "Workflow validation failed"

            if "error" in error_data:
                error_info = error_data["error"]
                if isinstance(error_info, dict):
                    error_msg = error_info.get("message", error_msg)
                else:
                    error_msg = str(error_info)

            # Add node errors if present
            if "node_errors" in error_data:
                details = []
                for node_id, node_error in error_data["node_errors"].items():
                    if isinstance(node_error, dict):
                        for error_type, msg in node_error.items():
                            details.append(f"Node {node_id} ({error_type}): {msg}")
                    else:
                        details.append(f"Node {node_id}: {node_error}")
                if details:
                    error_msg += ":\n" + "\n".join(f"• {d}" for d in details)

            raise ValueError(error_msg)
        except json.JSONDecodeError:
            raise ValueError(f"ComfyUI validation failed: {response.text}")

    response.raise_for_status()
    return response.json()


def get_history(prompt_id: str) -> dict:
    """Retrieve the history of a given prompt."""
    response = requests.get(
        f"http://{COMFY_HOST}/history/{prompt_id}",
        timeout=30
    )
    response.raise_for_status()
    return response.json()


def get_image_data(filename: str, subfolder: str, image_type: str) -> Optional[bytes]:
    """Fetch image bytes from the ComfyUI /view endpoint."""
    logger.info(f"Fetching image: type={image_type}, subfolder={subfolder}, filename={filename}")

    params = {"filename": filename, "subfolder": subfolder, "type": image_type}

    try:
        response = requests.get(
            f"http://{COMFY_HOST}/view",
            params=params,
            timeout=60
        )
        response.raise_for_status()
        logger.info(f"Successfully fetched {filename}")
        return response.content
    except Exception as e:
        logger.error(f"Error fetching {filename}: {e}")
        return None


def process_with_websocket(workflow: dict, client_id: str, prompt_id: str) -> tuple[bool, list]:
    """
    Monitor workflow execution via WebSocket.

    Returns:
        Tuple of (execution_done, errors)
    """
    import websocket

    ws_url = f"ws://{COMFY_HOST}/ws?clientId={client_id}"
    logger.info(f"Connecting to websocket: {ws_url}")

    errors = []
    execution_done = False
    ws = None

    try:
        ws = websocket.WebSocket()
        ws.connect(ws_url, timeout=10)
        logger.info("WebSocket connected")

        while True:
            try:
                out = ws.recv()
                if isinstance(out, str):
                    message = json.loads(out)
                    msg_type = message.get("type")

                    if msg_type == "status":
                        status_data = message.get("data", {}).get("status", {})
                        queue_remaining = status_data.get("exec_info", {}).get("queue_remaining", "N/A")
                        logger.info(f"Status: {queue_remaining} items in queue")

                    elif msg_type == "executing":
                        data = message.get("data", {})
                        if data.get("node") is None and data.get("prompt_id") == prompt_id:
                            logger.info(f"Execution finished for prompt {prompt_id}")
                            execution_done = True
                            break

                    elif msg_type == "execution_error":
                        data = message.get("data", {})
                        if data.get("prompt_id") == prompt_id:
                            error_details = (
                                f"Node Type: {data.get('node_type')}, "
                                f"Node ID: {data.get('node_id')}, "
                                f"Message: {data.get('exception_message')}"
                            )
                            logger.error(f"Execution error: {error_details}")
                            errors.append(f"Workflow execution error: {error_details}")
                            break

            except websocket.WebSocketTimeoutException:
                logger.info("WebSocket receive timed out, still waiting...")
                continue
            except websocket.WebSocketConnectionClosedException as e:
                logger.error(f"WebSocket connection closed: {e}")
                # Try reconnection
                for attempt in range(WEBSOCKET_RECONNECT_ATTEMPTS):
                    logger.info(f"Reconnect attempt {attempt + 1}/{WEBSOCKET_RECONNECT_ATTEMPTS}...")
                    try:
                        time.sleep(WEBSOCKET_RECONNECT_DELAY_S)
                        ws = websocket.WebSocket()
                        ws.connect(ws_url, timeout=10)
                        logger.info("Reconnected successfully")
                        break
                    except Exception as reconn_err:
                        logger.error(f"Reconnect failed: {reconn_err}")
                        if attempt == WEBSOCKET_RECONNECT_ATTEMPTS - 1:
                            raise
                continue
            except json.JSONDecodeError:
                logger.warning("Received invalid JSON via WebSocket")
                continue

    finally:
        if ws and ws.connected:
            ws.close()
            logger.info("WebSocket closed")

    return execution_done, errors


def process_with_polling(prompt_id: str, timeout: int = 600) -> tuple[bool, list]:
    """
    Fallback: Monitor workflow execution via HTTP polling.
    Used when websocket-client is not available.

    Returns:
        Tuple of (execution_done, errors)
    """
    logger.info("Using HTTP polling for execution monitoring (websocket-client not available)")

    errors = []
    start_time = time.time()

    while time.time() - start_time < timeout:
        try:
            queue_resp = requests.get(f"http://{COMFY_HOST}/queue", timeout=10)
            queue_data = queue_resp.json()

            queue_pending = queue_data.get("queue_pending", [])
            queue_running = queue_data.get("queue_running", [])

            # Check if our prompt is still in queue
            in_queue = any(prompt_id in str(item) for item in queue_pending + queue_running)

            if not in_queue:
                # Check history to confirm completion
                history = get_history(prompt_id)
                if prompt_id in history:
                    logger.info(f"Execution finished for prompt {prompt_id}")
                    return True, errors

        except Exception as e:
            logger.warning(f"Queue check failed: {e}")

        time.sleep(1)

    errors.append(f"Workflow execution timed out after {timeout} seconds")
    return False, errors


# =============================================================================
# Main Handler
# =============================================================================

def handler(job: dict) -> dict:
    """
    RunPod Serverless handler function.

    Processes ComfyUI workflow requests and returns generated images.
    """
    job_input = job.get("input", {})
    job_id = job.get("id", "unknown")

    logger.info(f"Processing job: {job_id}")

    # Validate input
    validated_data, error_message = validate_input(job_input)
    if error_message:
        return {"error": error_message}

    workflow = validated_data["workflow"]
    input_images = validated_data.get("images")

    # Start ComfyUI server
    try:
        start_comfyui_server()
    except Exception as e:
        return {"error": f"Failed to start ComfyUI server: {e}"}

    # Ensure server is reachable
    if not check_server(
        f"http://{COMFY_HOST}/",
        COMFY_API_AVAILABLE_MAX_RETRIES,
        COMFY_API_AVAILABLE_INTERVAL_MS
    ):
        return {"error": f"ComfyUI server ({COMFY_HOST}) not reachable"}

    # Upload input images if provided
    if input_images:
        upload_result = upload_images(input_images)
        if upload_result["status"] == "error":
            return {
                "error": "Failed to upload input images",
                "details": upload_result["details"]
            }

    client_id = str(uuid.uuid4())
    output_data = []
    errors = []

    try:
        # Queue the workflow
        logger.info("Queuing workflow...")
        queued = queue_workflow(workflow, client_id)
        prompt_id = queued.get("prompt_id")

        if not prompt_id:
            raise ValueError(f"Missing 'prompt_id' in queue response: {queued}")

        logger.info(f"Workflow queued with prompt_id: {prompt_id}")

        # Monitor execution
        try:
            import websocket
            execution_done, exec_errors = process_with_websocket(workflow, client_id, prompt_id)
        except ImportError:
            execution_done, exec_errors = process_with_polling(prompt_id)

        errors.extend(exec_errors)

        if not execution_done and not errors:
            raise ValueError("Workflow monitoring exited without completion or error")

        # Fetch history and collect outputs
        logger.info(f"Fetching history for prompt {prompt_id}...")
        history = get_history(prompt_id)

        if prompt_id not in history:
            error_msg = f"Prompt ID {prompt_id} not found in history"
            logger.error(error_msg)
            if not errors:
                return {"error": error_msg}
            errors.append(error_msg)
            return {"error": "Job processing failed", "details": errors}

        prompt_history = history.get(prompt_id, {})
        outputs = prompt_history.get("outputs", {})

        if not outputs:
            logger.warning(f"No outputs found for prompt {prompt_id}")
            if not errors:
                errors.append("Workflow produced no outputs")

        # Process output images
        logger.info(f"Processing {len(outputs)} output nodes...")

        for node_id, node_output in outputs.items():
            if "images" in node_output:
                for image_info in node_output["images"]:
                    filename = image_info.get("filename")
                    subfolder = image_info.get("subfolder", "")
                    img_type = image_info.get("type")

                    # Skip temp images
                    if img_type == "temp":
                        logger.info(f"Skipping temp image: {filename}")
                        continue

                    if not filename:
                        errors.append(f"Missing filename in node {node_id}")
                        continue

                    image_bytes = get_image_data(filename, subfolder, img_type)

                    if image_bytes:
                        if BUCKET_ENDPOINT_URL:
                            # S3 upload
                            try:
                                from runpod.serverless.utils import rp_upload

                                file_ext = os.path.splitext(filename)[1] or ".png"
                                with tempfile.NamedTemporaryFile(suffix=file_ext, delete=False) as f:
                                    f.write(image_bytes)
                                    temp_path = f.name

                                s3_url = rp_upload.upload_image(job_id, temp_path)
                                os.remove(temp_path)

                                output_data.append({
                                    "filename": filename,
                                    "type": "s3_url",
                                    "data": s3_url
                                })
                                logger.info(f"Uploaded {filename} to S3")
                            except Exception as e:
                                logger.error(f"S3 upload failed for {filename}: {e}")
                                errors.append(f"S3 upload failed: {e}")
                        else:
                            # Return as base64
                            try:
                                b64_image = base64.b64encode(image_bytes).decode("utf-8")
                                output_data.append({
                                    "filename": filename,
                                    "type": "base64",
                                    "data": b64_image
                                })
                                logger.info(f"Encoded {filename} as base64")
                            except Exception as e:
                                logger.error(f"Base64 encoding failed for {filename}: {e}")
                                errors.append(f"Base64 encoding failed: {e}")
                    else:
                        errors.append(f"Failed to fetch image data for {filename}")

    except ValueError as e:
        logger.error(f"Validation error: {e}")
        return {"error": str(e)}
    except requests.RequestException as e:
        logger.error(f"HTTP error: {e}")
        traceback.print_exc()
        return {"error": f"HTTP communication error: {e}"}
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        traceback.print_exc()
        return {"error": f"Unexpected error: {e}"}

    # Build final result
    result = {}

    if output_data:
        result["images"] = output_data

    if errors:
        result["errors"] = errors
        logger.warning(f"Job completed with errors: {errors}")

    if not output_data and errors:
        logger.error("Job failed with no output images")
        return {"error": "Job processing failed", "details": errors}

    if not output_data and not errors:
        logger.info("Job completed but produced no images")
        result["status"] = "success_no_images"
        result["images"] = []

    logger.info(f"Job completed. Returning {len(output_data)} image(s)")
    return result


# =============================================================================
# Entry Point
# =============================================================================

def run_local_test(dry_run: bool = False):
    """Run a local test of the handler.

    Args:
        dry_run: If True, only validate input without starting ComfyUI
    """
    # Load test input - check both / and script directory
    test_paths = [
        "/test_input.json",  # Docker container path
        os.path.join(os.path.dirname(__file__), "test_input.json"),  # Local dev
    ]

    test_data = None
    for test_path in test_paths:
        if os.path.exists(test_path):
            logger.info(f"Loading test input from: {test_path}")
            with open(test_path) as f:
                test_data = json.load(f)
            break

    if test_data is None:
        # Fallback: minimal test workflow for validation
        logger.info("No test_input.json found, using minimal test workflow")
        test_data = {
            "input": {
                "workflow": {
                    "1": {
                        "class_type": "CheckpointLoaderSimple",
                        "inputs": {"ckpt_name": "flux1-dev-fp8.safetensors"}
                    }
                }
            }
        }

    test_job = {
        "id": "test-job-001",
        "input": test_data.get("input", test_data)
    }

    if dry_run:
        # Dry run: only validate input, don't start ComfyUI
        logger.info("Running dry-run validation (no ComfyUI)...")
        validated, error = validate_input(test_job.get("input"))
        if error:
            print(json.dumps({"status": "validation_failed", "error": error}, indent=2))
            return {"status": "error", "error": error}

        print(json.dumps({
            "status": "validation_passed",
            "message": "Input is valid",
            "workflow_nodes": len(validated.get("workflow", {})),
            "test_job_id": test_job["id"]
        }, indent=2))
        return {"status": "success"}

    logger.info("Running local test...")
    result = handler(test_job)
    print(json.dumps(result, indent=2))
    return result


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="ComfyUI Serverless Worker")
    parser.add_argument("--test", action="store_true", help="Run local test (starts ComfyUI)")
    parser.add_argument("--dry-run", action="store_true", help="Validate input only (no ComfyUI)")
    parser.add_argument("--rp_serve_api", action="store_true", help="Serve API locally")
    parser.add_argument("--rp_api_host", default="0.0.0.0", help="API host")
    args = parser.parse_args()

    if args.test or args.dry_run:
        run_local_test(dry_run=args.dry_run)
    else:
        try:
            import runpod
            logger.info("Starting RunPod Serverless worker...")

            if args.rp_serve_api:
                runpod.serverless.start({
                    "handler": handler,
                    "rp_serve_api": True,
                    "rp_api_host": args.rp_api_host
                })
            else:
                runpod.serverless.start({"handler": handler})

        except ImportError:
            logger.error("runpod package not installed. Install with: pip install runpod")
            sys.exit(1)
