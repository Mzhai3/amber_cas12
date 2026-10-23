#!/bin/bash
#SBATCH -A loni_crispr1
#SBATCH -p single
#SBATCH -n 1
#SBATCH -t 0-01:00:00
#SBATCH -o /work/mzhai/crispr_pipeline_manual/output/rmsd_%j.out
#SBATCH -e /work/mzhai/crispr_pipeline_manual/error/rmsd_%j.err
#SBATCH -J rmsd_wt_crrna
#SBATCH --mail-user=mzhai@tulane.edu
#SBATCH --mail-type=BEGIN,END,FAIL

set -eo pipefail

# ---------------------------------------------------------
# Load AMBER
# ---------------------------------------------------------
module purge
# qbd version
module load ambertools/25/intel-2021.5.1-intel-mpi-2021.5.1

test -f "${AMBERHOME}/amber.sh" && source "${AMBERHOME}/amber.sh"


# --------------------------------------------------
# Paths
# --------------------------------------------------
NAME="wt_crrna"
BASE="/work/mzhai/crispr_pipeline_manual/amber/add_mg"
TOP="$BASE/$NAME/${NAME}.parm7"
REF="$BASE/$NAME/minim_complex/common/00_Min.rst7"
TRAJ_DIR="$BASE/$NAME/md/"
OUT_DIR="$BASE/$NAME/rmsd"

mkdir -p "$OUT_DIR"

# --------------------------------------------------
# Atom selections (EDIT THESE)
# --------------------------------------------------

# Cas12a protein backbone
PROTEIN_MASK=":1-1228@CA,C,N"

# crRNA backbone (RNA sugar-phosphate backbone)
RNA_MASK=":1229-1249@P,O5',C5',C4',C3',O3'"


# --------------------------------------------------
# Create output directories
# --------------------------------------------------
mkdir -p "$OUT_DIR/protein_rmsd"
mkdir -p "$OUT_DIR/crRNA_rmsd"
mkdir -p "$OUT_DIR/crRNA_protein_aligned"
mkdir -p "$OUT_DIR/log"

# --------------------------------------------------
# Find trajectories
# --------------------------------------------------
shopt -s nullglob
TRAJECTORIES=("$TRAJ_DIR"/rep*/*.nc)

if [ ${#TRAJECTORIES[@]} -eq 0 ]; then
    echo "No .nc trajectories found in replicate directories."
    exit 1
fi

# --------------------------------------------------
# Process each replicate
# --------------------------------------------------
for TRAJ in "${TRAJECTORIES[@]}"; do

    REP=$(basename "$(dirname "$TRAJ")")
    NAME=$(basename "$TRAJ" .nc)

    echo "Processing $REP: $NAME"

    cpptraj -p "$TOP" > "$OUT_DIR/log/${REP}_${NAME}.log" 2>&1 <<EOF
reference "$REF"
trajin "$TRAJ"

autoimage

# 1. Protein RMSD (independently fitted)
rms ProteinRMSD $PROTEIN_MASK reference nomod \
    out "$OUT_DIR/protein_rmsd/${REP}_protein_rmsd.dat"

# 2. crRNA RMSD (independently fitted)
rms RNA_RMSD $RNA_MASK reference nomod \
    out "$OUT_DIR/crRNA_rmsd/${REP}_crRNA_rmsd.dat"

# 3. Align the entire complex using the protein
rms ProteinFit $PROTEIN_MASK reference

# 4. Calculate crRNA RMSD without fitting it again
rms RNA_ProteinAligned $RNA_MASK reference nofit \
    out "$OUT_DIR/crRNA_protein_aligned/${REP}_crRNA_protein_aligned.dat"

run
EOF

done

echo "RMSD analysis complete."

