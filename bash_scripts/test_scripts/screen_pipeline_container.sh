#!/bin/bash
# screen_pipeline_container.sh
# Optimized for SurfDock Apptainer container

# Check if we are in the container
if [ -z "$SURFDOCK_ROOT" ]; then
    echo "Error: SURFDOCK_ROOT not set. Are you running this inside the SurfDock container?"
    exit 1
fi

cat << 'EOF'
  ____  _     _ _   _ _   _ ____  _     _____ ____  _   _ ____  _     _     ____  _     ____  _        _ 
  ____              __ ____             _      ____       _         __     __            _             
 / ___| _   _ _ __ / _|  _ \  ___   ___| | __ | __ )  ___| |_ __ _  \ \   / /__ _ __ ___(_) ___  _ __  
 \___ \| | | | '__| |_| | | |/ _ \ / __| |/ / |  _ \ / _ \ __/ _` |  \ \ / / _ \ '__/ __| |/ _ \| '_ \ 
  ___) | |_| | |  |  _| |_| | (_) | (__|   <  | |_) |  __/ || (_| |   \ V /  __/ |  \__ \ | (_) | | | | 
 |____/ \__,_|_|  |_| |____/ \___/ \___|_|\_\ |____/ \___|\__\__,_|    \_/ \___|_|  |___/_|\___/|_| |_| 
                                                                                                        
EOF

# The environment is already activated by Apptainer %environment section
# No need to source conda/mamba

SurfDockdir=$SURFDOCK_ROOT
echo "SurfDockdir : ${SurfDockdir}"

# Use current directory for outputs if not specified
WORKDIR=${WORKDIR:-$(pwd)}
project_name=${PROJECT_NAME:-'SurfDock_Screen_Container'}

#------------------------------------------------------------------------------------------------#
#------------------------------------ Step1 : Setup Params --------------------------------------#
#------------------------------------------------------------------------------------------------#

## Please set the GPU devices you want to use
gpu_string=${CUDA_VISIBLE_DEVICES:-"0"}
echo "Using GPU devices: ${gpu_string}"
IFS=',' read -ra gpu_array <<< "$gpu_string"
NUM_GPUS=${#gpu_array[@]}

## Please set the main Parameters
main_process_port=${PORT:-29570}

target_have_processed=${target_have_processed:-false}
pocket_radius=${POCKET_RADIUS:-8.0}

## Paths
surface_out_dir=${WORKDIR}/processed_data/${project_name}/surface
data_dir=${DATA_DIR:-${SurfDockdir}/data/Screen_sample_dirs/test_samples}
out_csv_dir=${WORKDIR}/processed_data/${project_name}/input_csv_files
out_csv_file=${out_csv_dir}/test_samples.csv
esmbedding_dir=${WORKDIR}/processed_data/${project_name}/esmbedding
Screen_lib_path=${SCREEN_LIB:-${SurfDockdir}/data/Screen_sample_dirs/test_samples/1a0q/1a0q_ligand_for_Screen.sdf}
docking_out_dir=${WORKDIR}/docking_result/${project_name}

#------------------------------------------------------------------------------------------------#
# -----------------------Step1 : Processed Target Structure -------------------------------------#
#------------------------------------------------------------------------------------------------#
mkdir -p $surface_out_dir
if [ "$target_have_processed" = true ]; then
  echo "Target structure has been processed, skipping this step."
else
  echo "Processing target structure with OpenBabel..."
  # BABEL_LIBDIR is already set in the container environment
  python ${SurfDockdir}/comp_surface/protein_process/openbabel_reduce_openbabel.py \
    --data_path ${data_dir} \
    --save_path ${surface_out_dir}
fi

#------------------------------------------------------------------------------------------------#
#----------------------------- Step2 : Compute Target Surface -----------------------------------#
#------------------------------------------------------------------------------------------------#
cd $surface_out_dir
python ${SurfDockdir}/comp_surface/prepare_target/computeTargetMesh_test_samples.py \
  --data_dir ${data_dir} \
  --out_dir ${surface_out_dir} \
  --dist_threshold ${pocket_radius}

#------------------------------------------------------------------------------------------------#
#--------------------------------  Step3 : Get Input CSV File -----------------------------------#
#------------------------------------------------------------------------------------------------#
mkdir -p $out_csv_dir
python ${SurfDockdir}/inference_utils/construct_csv_input.py \
  --data_dir ${data_dir} \
  --surface_out_dir ${surface_out_dir} \
  --output_csv_file ${out_csv_file} \
  --Screen_ligand_library_file ${Screen_lib_path}

#------------------------------------------------------------------------------------------------#
#--------------------------------  Step4 : Get Pocket ESM Embedding  ----------------------------#
#------------------------------------------------------------------------------------------------#
mkdir -p $esmbedding_dir
esm_dir=/opt/esm
sequence_out_file="${esmbedding_dir}/test_samples.fasta"
protein_pocket_csv=${out_csv_file}
full_protein_esm_embedding_dir="${esmbedding_dir}/esm_embedding_output"
pocket_emb_save_dir="${esmbedding_dir}/esm_embedding_pocket_output"
pocket_emb_save_to_single_file="${esmbedding_dir}/esm_embedding_pocket_output_for_train/esm2_3billion_pdbbind_embeddings.pt"

# get fasta sequence
python ${SurfDockdir}/datasets/esm_embedding_preparation.py \
  --out_file ${sequence_out_file} \
  --protein_ligand_csv ${protein_pocket_csv}

# esm embedding preparation
mkdir -p $full_protein_esm_embedding_dir
python ${esm_dir}/scripts/extract.py \
  "esm2_t33_650M_UR50D" \
  ${sequence_out_file} \
  ${full_protein_esm_embedding_dir} \
  --repr_layers 33 \
  --include "per_tok" \
  --truncation_seq_length 4096

# map pocket esm embedding
mkdir -p $pocket_emb_save_dir
python ${SurfDockdir}/datasets/get_pocket_embedding.py \
  --protein_pocket_csv ${protein_pocket_csv} \
  --embeddings_dir ${full_protein_esm_embedding_dir} \
  --pocket_emb_save_dir ${pocket_emb_save_dir}

# save pocket esm embedding to single file 
mkdir -p $(dirname $pocket_emb_save_to_single_file)
python ${SurfDockdir}/datasets/esm_pocket_embeddings_to_pt.py \
  --esm_embeddings_path ${pocket_emb_save_dir} \
  --output_path ${pocket_emb_save_to_single_file}

#------------------------------------------------------------------------------------------------#
#------------------------  Step5 : Start Sampling Ligand Confromers  ----------------------------#
#------------------------------------------------------------------------------------------------#
diffusion_model_dir=${SurfDockdir}/model_weights/docking
confidence_model_base_dir=${SurfDockdir}/model_weights/posepredict
protein_embedding=${pocket_emb_save_to_single_file}
test_data_csv=${out_csv_file}

mkdir -p $docking_out_dir

accelerate launch \
  --num_processes ${NUM_GPUS} \
  --main_process_port ${main_process_port} \
  ${SurfDockdir}/inference_accelerate.py \
  --data_csv ${test_data_csv} \
  --model_dir ${diffusion_model_dir} \
  --ckpt best_ema_inference_epoch_model.pt \
  --confidence_model_dir ${confidence_model_base_dir} \
  --confidence_ckpt best_model.pt \
  --save_docking_result \
  --mdn_dist_threshold_test 3.0 \
  --esm_embeddings_path ${protein_embedding} \
  --run_name ${project_name}_docking \
  --project ${project_name} \
  --out_dir ${docking_out_dir} \
  --batch_size 400 \
  --batch_size_molecule 10 \
  --samples_per_complex 40 \
  --save_docking_result_number 40 \
  --inference_mode Screen \
  --wandb_dir ${WORKDIR}/wandb

#------------------------------------------------------------------------------------------------#
#---------------- Step6 : Start Rescoring the Pose For Screening  -----------------#
#------------------------------------------------------------------------------------------------#
echo '---------------- Step6 : Start Rescoring the Pose For Screening  -----------------'
rescore_csv_file=${out_csv_dir}/score_inplace.csv

python ${SurfDockdir}/inference_utils/construct_csv_input.py \
  --data_dir ${data_dir} \
  --surface_out_dir ${surface_out_dir} \
  --output_csv_file ${rescore_csv_file} \
  --Screen_ligand_library_file ${Screen_lib_path} \
  --is_docking_result_dir \
  --docking_result_dir ${docking_out_dir}

screen_model_dir=${SurfDockdir}/model_weights/screen

accelerate launch \
  --num_processes 1 \
  --main_process_port $((main_process_port + 1)) \
  ${SurfDockdir}/evaluate_score_in_place.py \
  --data_csv ${rescore_csv_file} \
  --confidence_model_dir ${screen_model_dir} \
  --confidence_ckpt best_model.pt \
  --model_version version6 \
  --mdn_dist_threshold_test 3.0 \
  --esm_embeddings_path ${protein_embedding} \
  --run_name ${project_name}_screening \
  --project ${project_name} \
  --out_dir ${docking_out_dir} \
  --batch_size 40 \
  --wandb_dir ${WORKDIR}/wandb

echo "Screening complete. Results in ${docking_out_dir}"
