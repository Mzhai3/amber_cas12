#!/bin/bash
#SBATCH -A loni_crispr1
#SBATCH -p single
#SBATCH -n 1
#SBATCH -t 0-01:00:00
#SBATCH -o /work/mzhai/crispr_pipeline_manual/output/rmsd_%j.out
#SBATCH -e /work/mzhai/crispr_pipeline_manual/error/rmsd_%j.err
#SBATCH -J rmsd_wt_complex
#SBATCH --mail-user=mzhai@tulane.edu
#SBATCH --mail-type=BEGIN,END,FAIL

set -eo pipefail

# ---------------------------------------------------------
# Load AMBER
# ---------------------------------------------------------
module purge
#qbd version
module load ambertools/25/intel-2021.5.1-intel-mpi-2021.5.1

test -f "${AMBERHOME}/amber.sh" && source "${AMBERHOME}/amber.sh"

# --------------------------------------------------
# Paths
# --------------------------------------------------
NAME="wt_complex"
BASE="/work/mzhai/crispr_pipeline_manual/amber/add_mg"
TOP="$BASE/$NAME/${NAME}.parm7"
REF="$BASE/$NAME/minim_complex/common/00_Min.rst7"
TRAJ_DIR="$BASE/$NAME/md/"
OUT_DIR="$BASE/$NAME/rmsd"

# --------------------------------------------------
# Atom selections
# --------------------------------------------------

# Cas12a protein backbone
PROTEIN_MASK=":1-1228@CA,C,N"

# crRNA sugar-phosphate backbone
RNA_MASK=":1269-1289@P,O5',C5',C4',C3',O3'"

# DNA sugar-phosphate backbone
# Uses AMBER DNA residue names, including terminal residues
DNA_MASK=":DA,DC,DG,DT,DA3,DA5,DC3,DC5,DG3,DG5,DT3,DT5@P,O5',C5',C4',C3',O3'"

# --------------------------------------------------
# Create output directories
# --------------------------------------------------
mkdir -p "$OUT_DIR/protein_rmsd"
mkdir -p "$OUT_DIR/crRNA_rmsd"
mkdir -p "$OUT_DIR/dna_rmsd"
mkdir -p "$OUT_DIR/crRNA_protein_aligned"
mkdir -p "$OUT_DIR/dna_protein_aligned"
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
# Process each trajectory
# --------------------------------------------------
for TRAJ in "${TRAJECTORIES[@]}"; do

    REP=$(basename "$(dirname "$TRAJ")")
    TRAJ_NAME=$(basename "$TRAJ" .nc)
    PREFIX="${REP}_${TRAJ_NAME}"

    echo "Processing $REP: $TRAJ_NAME"

    cpptraj -p "$TOP" > "$OUT_DIR/log/${PREFIX}.log" 2>&1 <<EOF
reference "$REF"
trajin "$TRAJ"

autoimage

# --------------------------------------------------
# Independently fitted RMSD calculations
# --------------------------------------------------

# 1. Protein backbone RMSD
rms ProteinRMSD $PROTEIN_MASK reference nomod \
    out "$OUT_DIR/protein_rmsd/${PREFIX}_protein_rmsd.dat"

# 2. crRNA backbone RMSD
rms RNA_RMSD $RNA_MASK reference nomod \
    out "$OUT_DIR/crRNA_rmsd/${PREFIX}_crRNA_rmsd.dat"

# 3. DNA backbone RMSD
rms DNA_RMSD $DNA_MASK reference nomod \
    out "$OUT_DIR/dna_rmsd/${PREFIX}_dna_rmsd.dat"

# --------------------------------------------------
# Protein-aligned RMSD calculations
# --------------------------------------------------

# 4. Align the entire complex using the protein
rms ProteinFit $PROTEIN_MASK reference

# 5. crRNA RMSD after protein alignment
rms RNA_ProteinAligned $RNA_MASK reference nofit \
    out "$OUT_DIR/crRNA_protein_aligned/${PREFIX}_crRNA_protein_aligned.dat"

# 6. DNA RMSD after protein alignment
rms DNA_ProteinAligned $DNA_MASK reference nofit \
    out "$OUT_DIR/dna_protein_aligned/${PREFIX}_dna_protein_aligned.dat"

run
EOF

done

echo "RMSD analysis complete."

