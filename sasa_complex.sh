#!/bin/bash
#SBATCH -A loni_crispr1
#SBATCH -p single
#SBATCH -n 2
#SBATCH -t 3-00:00:00
#SBATCH -o /work/mzhai/crispr_pipeline_manual/output/sasa_%j.out
#SBATCH -e /work/mzhai/crispr_pipeline_manual/error/sasa_%j.err
#SBATCH -J sasa_wt_complex
#SBATCH --mail-user=mzhai@tulane.edu
#SBATCH --mail-type=BEGIN,END,FAIL

set -eo pipefail

# --------------------------------------------------
# Load AMBER
# --------------------------------------------------
module purge
# qbd version
module load ambertools/25/intel-2021.5.1-intel-mpi-2021.5.1

if [[ -n "${AMBERHOME:-}" && -f "${AMBERHOME}/amber.sh" ]]; then
    source "${AMBERHOME}/amber.sh"
fi

# --------------------------------------------------
# Paths
# --------------------------------------------------
NAME="wt_complex"
BASE="/work/mzhai/crispr_pipeline_manual/amber/add_mg"

TOP="$BASE/$NAME/${NAME}.parm7"
TRAJ_DIR="$BASE/$NAME/md"
OUT_DIR="$BASE/$NAME/sasa"

# --------------------------------------------------
# Atom selections
# --------------------------------------------------

# Cas12a protein
PROTEIN_MASK=":1-1228"

# crRNA
RNA_MASK=":1269-1289"

# Entire protein-RNA-DNA complex
COMPLEX_MASK=":1-1289"

# DNA
DNA_MASK=":1231-1268"

# --------------------------------------------------
# Validate files
# --------------------------------------------------
if [[ ! -f "$TOP" ]]; then
    echo "ERROR: Topology not found: $TOP" >&2
    exit 1
fi

command -v cpptraj >/dev/null || {
    echo "ERROR: cpptraj not found." >&2
    exit 1
}

# --------------------------------------------------
# Create output directories
# --------------------------------------------------
mkdir -p \
    "$OUT_DIR/complex_sasa" \
    "$OUT_DIR/protein_sasa" \
    "$OUT_DIR/crRNA_sasa" \
    "$OUT_DIR/log"

# --------------------------------------------------
# Find replicate directories
# --------------------------------------------------
shopt -s nullglob

REPS=("$TRAJ_DIR"/rep[0-9]*)

if (( ${#REPS[@]} == 0 )); then
    echo "ERROR: No replicate directories found."
    exit 1
fi

# --------------------------------------------------
# Process each replicate
# --------------------------------------------------
for REP_DIR in "${REPS[@]}"; do

    [[ -d "$REP_DIR" ]] || continue

    REP=$(basename "$REP_DIR")

    TRAJECTORIES=("$REP_DIR"/*.nc)

    if (( ${#TRAJECTORIES[@]} != 1 )); then
        echo "ERROR: Expected exactly one .nc file in $REP_DIR"
        echo "Found: ${#TRAJECTORIES[@]}"
        exit 1
    fi

    TRAJ="${TRAJECTORIES[0]}"
    TRAJ_NAME=$(basename "$TRAJ" .nc)

    echo "----------------------------------------"
    echo "Processing $REP"
    echo "Trajectory: $TRAJ"
    echo "----------------------------------------"

    LOG="$OUT_DIR/log/${REP}_${TRAJ_NAME}.log"

    # ----------------------------------------------
    # Calculate SASA
    # ----------------------------------------------
    if ! cpptraj -p "$TOP" > "$LOG" 2>&1 <<EOF

trajin "$TRAJ"

# Correct periodic boundary imaging
autoimage

# Total complex SASA
surf ComplexSASA $COMPLEX_MASK \
    solutemask $COMPLEX_MASK \
    out "$OUT_DIR/complex_sasa/${REP}_complex_sasa.dat"

EOF

# # Protein contribution to complex SASA
# surf ProteinSASA $PROTEIN_MASK \
#     solutemask $COMPLEX_MASK \
#     out "$OUT_DIR/protein_sasa/${REP}_protein_sasa.dat"

# # crRNA contribution to complex SASA
# surf RNA_SASA $RNA_MASK \
#     solutemask $COMPLEX_MASK \
#     out "$OUT_DIR/crRNA_sasa/${REP}_crRNA_sasa.dat"

# run



# EOF
    then
        echo "ERROR: SASA calculation failed for $REP"
        echo "Check log: $LOG"
        exit 1
    fi

    echo "Completed $REP successfully."

done

echo "----------------------------------------"
echo "All SASA calculations completed."
echo "Results saved to: $OUT_DIR"

