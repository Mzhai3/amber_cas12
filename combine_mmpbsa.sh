#!/bin/bash
#SBATCH -A loni_crispr1
#SBATCH -p single
#SBATCH -n 1
#SBATCH -t 00:30:00
#SBATCH -o /work/mzhai/crispr_pipeline_manual/output/combine_mmpbsa_%j.out
#SBATCH -e /work/mzhai/crispr_pipeline_manual/error/combine_mmpbsa_%j.err
#SBATCH -J combine_mmpbsa_Lb033_crrna
#SBATCH --mail-user=mzhai@tulane.edu
#SBATCH --mail-type=BEGIN,END,FAIL

set -euo pipefail

source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate /work/mzhai/envs/cas12

NAME="Lb033_crrna"               # EDIT HERE
AMBER="/work/mzhai/crispr_pipeline_manual/amber"
INPUT_DIR="${AMBER}/afm/${NAME}/mmpbsa"

python "${AMBER}/scripts/combine_mmpbsa.py" \
    -i "$INPUT_DIR" \
    -p "work_*/${NAME}_chunk*.csv" \
    -o "${INPUT_DIR}/${NAME}_combined_energies"
