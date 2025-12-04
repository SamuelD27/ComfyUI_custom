#!/usr/bin/env python3
"""
ComfyUI + Flux Environment Validation Script

This script performs comprehensive pre-flight checks to ensure the environment
is properly configured for running ComfyUI with Flux models.

Checks performed:
- Python version compatibility
- Critical package imports (torch, numpy, onnxruntime)
- CUDA availability
- Model file existence and size verification
- Custom node installation
- Folder structure validation
"""

import sys
import os
from pathlib import Path
from typing import List, Tuple, Dict, Optional
import importlib.util

# ANSI color codes for terminal output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    BOLD = '\033[1m'
    NC = '\033[0m'  # No Color


def print_header(text: str) -> None:
    """Print a section header."""
    print(f"\n{Colors.BLUE}{Colors.BOLD}=== {text} ==={Colors.NC}\n")


def print_success(text: str) -> None:
    """Print a success message."""
    print(f"{Colors.GREEN}[PASS]{Colors.NC} {text}")


def print_warning(text: str) -> None:
    """Print a warning message."""
    print(f"{Colors.YELLOW}[WARN]{Colors.NC} {text}")


def print_error(text: str) -> None:
    """Print an error message."""
    print(f"{Colors.RED}[FAIL]{Colors.NC} {text}")


def print_info(text: str) -> None:
    """Print an info message."""
    print(f"[INFO] {text}")


class ValidationResult:
    """Stores validation results."""

    def __init__(self):
        self.errors: List[str] = []
        self.warnings: List[str] = []
        self.passed: int = 0
        self.failed: int = 0

    def add_error(self, message: str) -> None:
        self.errors.append(message)
        self.failed += 1

    def add_warning(self, message: str) -> None:
        self.warnings.append(message)

    def add_pass(self) -> None:
        self.passed += 1

    @property
    def is_valid(self) -> bool:
        # Errors are fatal, warnings are not
        return len(self.errors) == 0


def get_comfyui_dir() -> Path:
    """Get the ComfyUI directory from environment or default."""
    comfyui_dir = os.environ.get('COMFYUI_DIR', '/ComfyUI')

    # If not found, try to find it
    if not Path(comfyui_dir).exists():
        possible_paths = [
            Path('/ComfyUI'),
            Path('/workspace/ComfyUI'),
            Path.cwd() / 'ComfyUI',
            Path.cwd().parent / 'ComfyUI',
        ]
        for path in possible_paths:
            if path.exists():
                return path

    return Path(comfyui_dir)


def validate_python_version(result: ValidationResult) -> None:
    """Check Python version is 3.10+."""
    print_header("Python Version Check")

    version = sys.version_info
    version_str = f"{version.major}.{version.minor}.{version.micro}"

    if version.major < 3 or (version.major == 3 and version.minor < 10):
        print_error(f"Python {version_str} detected - requires 3.10+")
        result.add_error(f"Python 3.10+ required, found {version_str}")
    else:
        print_success(f"Python {version_str}")
        result.add_pass()


def validate_critical_imports(result: ValidationResult) -> None:
    """Check that critical packages can be imported."""
    print_header("Critical Package Imports")

    packages = [
        ('torch', 'PyTorch'),
        ('numpy', 'NumPy'),
        ('PIL', 'Pillow'),
        ('cv2', 'OpenCV'),
    ]

    optional_packages = [
        ('onnxruntime', 'ONNX Runtime'),
        ('insightface', 'InsightFace'),
    ]

    # Check required packages
    for module_name, display_name in packages:
        try:
            module = __import__(module_name)
            version = getattr(module, '__version__', 'unknown')
            print_success(f"{display_name}: {version}")
            result.add_pass()
        except ImportError as e:
            print_error(f"{display_name}: Not installed")
            result.add_error(f"{display_name} import failed: {e}")

    # Check optional packages
    for module_name, display_name in optional_packages:
        try:
            module = __import__(module_name)
            version = getattr(module, '__version__', 'unknown')
            print_success(f"{display_name}: {version}")
            result.add_pass()
        except ImportError:
            print_warning(f"{display_name}: Not installed (optional)")
            result.add_warning(f"{display_name} not installed")


def validate_numpy_version(result: ValidationResult) -> None:
    """Check NumPy version compatibility (must be < 2.0 for InsightFace)."""
    print_header("NumPy Compatibility Check")

    try:
        import numpy as np
        version = np.__version__
        major_version = int(version.split('.')[0])

        if major_version >= 2:
            print_warning(f"NumPy {version} may cause compatibility issues")
            print_info("Recommended: numpy==1.26.4 for InsightFace/IPAdapter")
            result.add_warning(f"NumPy {version} may cause issues with InsightFace")
        else:
            print_success(f"NumPy {version} (compatible)")
            result.add_pass()
    except ImportError:
        print_error("NumPy not installed")
        result.add_error("NumPy not installed")


def validate_cuda(result: ValidationResult) -> None:
    """Check CUDA availability and configuration."""
    print_header("CUDA Availability Check")

    try:
        import torch

        if torch.cuda.is_available():
            device_count = torch.cuda.device_count()
            print_success(f"CUDA available with {device_count} device(s)")

            for i in range(device_count):
                device_name = torch.cuda.get_device_name(i)
                device_memory = torch.cuda.get_device_properties(i).total_memory / (1024**3)
                print_info(f"  GPU {i}: {device_name} ({device_memory:.1f} GB)")

            cuda_version = torch.version.cuda
            print_info(f"  CUDA Version: {cuda_version}")
            result.add_pass()
        else:
            print_warning("CUDA not available - running on CPU")
            print_info("Flux models require significant GPU memory (24GB+ recommended)")
            result.add_warning("CUDA not available")
    except ImportError:
        print_error("PyTorch not installed - cannot check CUDA")
        result.add_error("PyTorch not installed")


def validate_model_files(result: ValidationResult, comfyui_dir: Path) -> None:
    """Check that required model files exist and have reasonable sizes."""
    print_header("Model Files Check")

    models_dir = comfyui_dir / 'models'

    # Model definitions: (relative_path, min_size_bytes, required)
    required_models: List[Tuple[str, int, bool]] = [
        # Core Flux models
        ('vae/ae.sft', 300_000_000, False),  # ~335MB VAE
        ('diffusion_models/flux1-dev.sft', 20_000_000_000, False),  # ~23GB
        ('clip/clip_l.safetensors', 200_000_000, False),  # CLIP-L
        ('clip/t5xxl_fp8_e4m3fn.safetensors', 4_000_000_000, False),  # T5 XXL
    ]

    optional_models: List[Tuple[str, int]] = [
        # IP-Adapter
        ('ipadapter/FLUX.1-dev-IP-Adapter.bin', 100_000_000),
        ('clip_vision/sigclip_vision_patch14_384.safetensors', 500_000_000),
        # PuLID
        ('pulid/pulid_flux_v0.9.1.safetensors', 500_000_000),
        # ControlNets
        ('controlnet/flux_controlnet_union_pro_2.0.safetensors', 500_000_000),
        # Upscalers
        ('upscale_models/4x-UltraSharp.pth', 50_000_000),
    ]

    # Check required models
    for rel_path, min_size, required in required_models:
        model_path = models_dir / rel_path
        filename = os.path.basename(rel_path)

        if model_path.exists():
            actual_size = model_path.stat().st_size
            size_gb = actual_size / (1024**3)

            if actual_size >= min_size * 0.95:  # Allow 5% tolerance
                print_success(f"{filename} ({size_gb:.2f} GB)")
                result.add_pass()
            else:
                print_warning(f"{filename} may be incomplete ({size_gb:.2f} GB)")
                result.add_warning(f"{filename} may be incomplete")
        else:
            if required:
                print_error(f"{filename}: Not found")
                result.add_error(f"Required model missing: {rel_path}")
            else:
                print_warning(f"{filename}: Not found (will download on startup)")
                result.add_warning(f"Model not found: {rel_path}")

    print()
    print_info("Optional models:")

    # Check optional models
    for rel_path, min_size in optional_models:
        model_path = models_dir / rel_path
        filename = os.path.basename(rel_path)

        if model_path.exists():
            actual_size = model_path.stat().st_size
            size_mb = actual_size / (1024**2)
            print_success(f"  {filename} ({size_mb:.1f} MB)")
        else:
            print_info(f"  {filename}: Not installed")


def validate_custom_nodes(result: ValidationResult, comfyui_dir: Path) -> None:
    """Check that critical custom nodes are installed."""
    print_header("Custom Nodes Check")

    custom_nodes_dir = comfyui_dir / 'custom_nodes'

    if not custom_nodes_dir.exists():
        print_error("custom_nodes directory not found")
        result.add_error("custom_nodes directory missing")
        return

    # Critical nodes for Flux workflows
    critical_nodes = [
        'ComfyUI-Manager',
    ]

    # Recommended nodes for enhanced Flux support
    recommended_nodes = [
        'ComfyUI-IPAdapter-Flux',
        'x-flux-comfyui',
        'comfyui_controlnet_aux',
    ]

    # Check critical nodes
    for node_name in critical_nodes:
        node_path = custom_nodes_dir / node_name
        if node_path.exists():
            print_success(f"{node_name}")
            result.add_pass()
        else:
            print_warning(f"{node_name}: Not installed (recommended)")
            result.add_warning(f"Recommended node not installed: {node_name}")

    # Check recommended nodes
    print()
    print_info("Recommended nodes:")
    for node_name in recommended_nodes:
        node_path = custom_nodes_dir / node_name
        if node_path.exists():
            print_success(f"  {node_name}")
        else:
            print_info(f"  {node_name}: Not installed")


def validate_folder_structure(result: ValidationResult, comfyui_dir: Path) -> None:
    """Validate the folder structure is correct."""
    print_header("Folder Structure Check")

    required_dirs = [
        'models',
        'models/checkpoints',
        'models/clip',
        'models/controlnet',
        'models/diffusion_models',
        'models/loras',
        'models/vae',
        'custom_nodes',
        'input',
        'output',
    ]

    for dir_rel_path in required_dirs:
        dir_path = comfyui_dir / dir_rel_path
        if dir_path.exists():
            print_success(f"{dir_rel_path}/")
            result.add_pass()
        else:
            print_warning(f"{dir_rel_path}/ missing (will be created)")
            result.add_warning(f"Directory missing: {dir_rel_path}")


def validate_folder_paths_config(result: ValidationResult, comfyui_dir: Path) -> None:
    """Check if ComfyUI folder_paths configuration is accessible."""
    print_header("ComfyUI Configuration Check")

    # Try to import folder_paths from ComfyUI
    folder_paths_file = comfyui_dir / 'folder_paths.py'

    if folder_paths_file.exists():
        print_success("folder_paths.py found")
        result.add_pass()

        # Try to import and check configuration
        try:
            sys.path.insert(0, str(comfyui_dir))
            import folder_paths

            # Check some common paths
            models_dir = getattr(folder_paths, 'models_dir', None)
            if models_dir:
                print_info(f"  models_dir: {models_dir}")
            result.add_pass()
        except Exception as e:
            print_warning(f"Could not load folder_paths: {e}")
            result.add_warning(f"Could not load folder_paths: {e}")
        finally:
            sys.path.pop(0)
    else:
        print_info("folder_paths.py not found (may be generated on first run)")


def print_summary(result: ValidationResult) -> None:
    """Print validation summary."""
    print_header("Validation Summary")

    total_checks = result.passed + result.failed
    print(f"Checks passed: {Colors.GREEN}{result.passed}{Colors.NC}/{total_checks}")

    if result.warnings:
        print(f"Warnings: {Colors.YELLOW}{len(result.warnings)}{Colors.NC}")

    if result.errors:
        print(f"Errors: {Colors.RED}{len(result.errors)}{Colors.NC}")
        print()
        print(f"{Colors.RED}Validation FAILED{Colors.NC}")
        print()
        print("Errors that must be fixed:")
        for error in result.errors:
            print(f"  - {error}")
    else:
        print()
        print(f"{Colors.GREEN}{Colors.BOLD}Validation PASSED{Colors.NC}")

    if result.warnings:
        print()
        print("Warnings (non-fatal):")
        for warning in result.warnings:
            print(f"  - {warning}")


def main() -> int:
    """Main validation function."""
    print()
    print(f"{Colors.BOLD}ComfyUI + Flux Environment Validation{Colors.NC}")
    print("=" * 50)

    result = ValidationResult()
    comfyui_dir = get_comfyui_dir()

    print(f"\nComfyUI directory: {comfyui_dir}")

    if not comfyui_dir.exists():
        print_error(f"ComfyUI directory not found at {comfyui_dir}")
        result.add_error(f"ComfyUI directory not found: {comfyui_dir}")
        print_summary(result)
        return 1

    # Run all validations
    validate_python_version(result)
    validate_critical_imports(result)
    validate_numpy_version(result)
    validate_cuda(result)
    validate_folder_structure(result, comfyui_dir)
    validate_model_files(result, comfyui_dir)
    validate_custom_nodes(result, comfyui_dir)
    validate_folder_paths_config(result, comfyui_dir)

    # Print summary
    print_summary(result)

    return 0 if result.is_valid else 1


if __name__ == "__main__":
    sys.exit(main())
