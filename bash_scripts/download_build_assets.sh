#!/bin/bash
set -e

CACHE_DIR="build_cache"
mkdir -p $CACHE_DIR/torch/hub/checkpoints

echo "Checking for ESM weights..."
# ESM2 650M model
ESM_MODEL="$CACHE_DIR/torch/hub/checkpoints/esm2_t33_650M_UR50D.pt"
if [ ! -f "$ESM_MODEL" ]; then
    echo "Downloading ESM model..."
    wget -P $CACHE_DIR/torch/hub/checkpoints/ https://dl.fbaipublicfiles.com/fair-esm/models/esm2_t33_650M_UR50D.pt
else
    echo "ESM model already exists. Skipping."
fi

# Contact regression
ESM_REGRESSION="$CACHE_DIR/torch/hub/checkpoints/esm2_t33_650M_UR50D-contact-regression.pt"
if [ ! -f "$ESM_REGRESSION" ]; then
    echo "Downloading ESM contact regression..."
    wget -P $CACHE_DIR/torch/hub/checkpoints/ https://dl.fbaipublicfiles.com/fair-esm/regression/esm2_t33_650M_UR50D-contact-regression.pt
else
    echo "ESM contact regression already exists. Skipping."
fi

echo "Checking for PyMesh wheel..."
PYMESH_WHEEL="$CACHE_DIR/pymesh2-0.3.1-cp310-cp310-linux_x86_64.whl"
if [ ! -f "$PYMESH_WHEEL" ]; then
    echo "Downloading PyMesh wheel..."
    wget -P $CACHE_DIR/ https://github.com/nuvolos-cloud/PyMesh/releases/download/v0.3.1/pymesh2-0.3.1-cp310-cp310-linux_x86_64.whl
else
    echo "PyMesh wheel already exists. Skipping."
fi

echo "All assets cached in $CACHE_DIR"
