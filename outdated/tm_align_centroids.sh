#!/bin/bash
#SBATCH -A loni_crispr1
#SBATCH -p single
#SBATCH -n 4
#SBATCH -t 0-01:00:00
#SBATCH -o /work/mzhai/crispr_pipeline_manual/output/tm_align_centroids_%j.out
#SBATCH -e /work/mzhai/crispr_pipeline_manual/error/tm_align_centroids_%j.err
#SBATCH -J tm_align_centroids_crrna_Lb000
#SBATCH --mail-user=mzhai@tulane.edu
#SBATCH --mail-type=BEGIN,END,FAIL


set -euo pipefail
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate /work/mzhai/envs/cas12

REPO=/work/mzhai/crispr_pipeline_manual
SCRIPTS="${REPO}/scripts"

AMBER="${REPO}/amber"

REFERENCEPDB="${AMBER}/reference/5XUS.pdb"
NAME="Lb000_crrna"													# Edit here
QUERYDIR="${AMBER}/afm/${NAME}/cluster/fullrun"			
OUTPUTNAME="${QUERYDIR}/centroid_tm_align"

python "${SCRIPTS}/tm_align_compare.py" \
	--reference "$REFERENCEPDB" \
	--query_dir "$QUERYDIR" \
	--output "${OUTPUTNAME}_global.csv" 

# domains gotten from uniprot annotation of LbCas12a (https://www.uniprot.org/uniprotkb/A0A5S8WF58/entry)
python "${SCRIPTS}/tm_align_compare.py" \
	--reference "$REFERENCEPDB" \
	--query_dir "$QUERYDIR" \
	--output "${OUTPUTNAME}_domains.csv" \
	--domains REC1:49:280 REC2:297:512 PI:587:678 RUVC:810:1225