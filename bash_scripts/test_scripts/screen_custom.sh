#!/bin/bash
# screen_custom.sh
# Usage: ./screen_custom.sh --protein protein.pdb --ligands ligands.smi --pocket_center "10.5,12.0,-5.0" --radius 8.0 --out_dir ./results

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --protein) PROTEIN="$2"; shift 2 ;;
    --ligands) LIGANDS="$2"; shift 2 ;;
    --pocket_center) CENTER="$2"; shift 2 ;;
    --radius) RADIUS="$2"; shift 2 ;;
    --out_dir) OUT_DIR="$2"; shift 2 ;;
    *) echo "Unknown parameter $1"; exit 1 ;;
  esac
done

if [ -z "$PROTEIN" ] || [ -z "$LIGANDS" ] || [ -z "$CENTER" ] || [ -z "$OUT_DIR" ]; then
    echo "Usage: $0 --protein protein.pdb --ligands ligands.smi --pocket_center \"x,y,z\" [--radius 8.0] --out_dir results"
    exit 1
fi

# Set default radius if not provided
RADIUS=${RADIUS:-8.0}

# 1. Prepare data
mkdir -p "$OUT_DIR"
python /opt/SurfDock/inference_utils/prepare_custom_screening.py \
    --protein "$PROTEIN" \
    --ligands "$LIGANDS" \
    --pocket_center "$CENTER" \
    --out_dir "$OUT_DIR"

# 2. Run screening pipeline
# We use the container-optimized script but point to our newly prepared data
export DATA_DIR="$OUT_DIR/data"
export SCREEN_LIB="$OUT_DIR/data/custom_target/library.sdf"
export WORKDIR="$OUT_DIR"
export PROJECT_NAME="Custom_Screen"
export POCKET_RADIUS="$RADIUS"

bash /opt/SurfDock/bash_scripts/test_scripts/screen_pipeline_container.sh
