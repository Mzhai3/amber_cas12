#!/bin/bash
#SBATCH -A loni_crispr1
#SBATCH -p single
#SBATCH -n 1
#SBATCH -t 0-01:00:00
#SBATCH -o /work/mzhai/crispr_pipeline_manual/output/rmsf_%j.out
#SBATCH -e /work/mzhai/crispr_pipeline_manual/error/rmsf_%j.err
#SBATCH -J rmsf_wt_complex
#SBATCH --mail-user=mzhai@tulane.edu
#SBATCH --mail-type=BEGIN,END,FAIL

set -eo pipefail

# --------------------------------------------------
# Load AMBER
# --------------------------------------------------
module purge
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
REF="$BASE/$NAME/minim_complex/common/00_Min.rst7"
TRAJ_DIR="$BASE/$NAME/md"
OUT_DIR="$BASE/$NAME/rmsf"

# --------------------------------------------------
# Atom selections
# --------------------------------------------------

# Protein backbone for alignment
PROTEIN_MASK=":1-1228@CA,C,N"

# crRNA backbone for independent alignment
RNA_MASK=":1269-1289@P,O5',C5',C4',C3',O3'"

# DNA backbone for independent alignment
DNA_RES=":DA,DC,DG,DT,DA3,DA5,DC3,DC5,DG3,DG5,DT3,DT5"
DNA_MASK="${DNA_RES}@P,O5',C5',C4',C3',O3'"

# Protein C-alpha for per-residue RMSF
PROTEIN_RMSF_MASK=":1-1228@CA"

# crRNA C4' for per-nucleotide RMSF
RNA_RMSF_MASK=":1269-1289@C4'"

# DNA C4' for per-nucleotide RMSF
DNA_RMSF_MASK="${DNA_RES}@C4'"

# --------------------------------------------------
# Validate paths
# --------------------------------------------------
for FILE in "$TOP" "$REF"; do
    if [[ ! -f "$FILE" ]]; then
        echo "ERROR: File not found: $FILE" >&2
        exit 1
    fi
done

command -v cpptraj >/dev/null || {
    echo "ERROR: cpptraj not found." >&2
    exit 1
}

# --------------------------------------------------
# Create output directories
# --------------------------------------------------
mkdir -p "$OUT_DIR"/{protein_rmsf,crRNA_rmsf,dna_rmsf,crRNA_protein_aligned,dna_protein_aligned,log}

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

    echo "----------------------------------------"
    echo "Processing $REP"
    echo "Trajectory: $TRAJ"
    echo "----------------------------------------"

    # ----------------------------------------------
    # 1. Protein-aligned analysis
    # ----------------------------------------------
    # Calculates:
    #   - Protein RMSF
    #   - Protein-aligned crRNA RMSF
    #   - Protein-aligned DNA RMSF
    # ----------------------------------------------

    LOG="$OUT_DIR/log/${REP}_protein_fit.log"

    if ! cpptraj -p "$TOP" > "$LOG" 2>&1 <<EOF
reference "$REF"
trajin "$TRAJ"

autoimage

# Align trajectory using protein backbone
rms ProteinFit $PROTEIN_MASK reference

# Protein RMSF, per residue
atomicfluct ProteinRMSF $PROTEIN_RMSF_MASK byres out "$OUT_DIR/protein_rmsf/${REP}_protein_rmsf.dat"

# crRNA RMSF after protein alignment
atomicfluct RNA_ProteinAligned $RNA_RMSF_MASK byres out "$OUT_DIR/crRNA_protein_aligned/${REP}_crRNA_protein_aligned_rmsf.dat"

# DNA RMSF after protein alignment
atomicfluct DNA_ProteinAligned $DNA_RMSF_MASK byres out "$OUT_DIR/dna_protein_aligned/${REP}_dna_protein_aligned_rmsf.dat"

run
EOF
    then
        echo "ERROR: Protein-aligned analysis failed for $REP"
        echo "Check log: $LOG"
        exit 1
    fi

    # ----------------------------------------------
    # 2. Independently aligned crRNA analysis
    # ----------------------------------------------
    # Calculates:
    #   - crRNA RMSF after aligning on crRNA
    # ----------------------------------------------

    LOG="$OUT_DIR/log/${REP}_crRNA_fit.log"

    if ! cpptraj -p "$TOP" > "$LOG" 2>&1 <<EOF
reference "$REF"
trajin "$TRAJ"

autoimage

# Align trajectory using crRNA backbone
rms RNAFit $RNA_MASK reference

# crRNA RMSF, per nucleotide
atomicfluct RNA_RMSF $RNA_RMSF_MASK byres out "$OUT_DIR/crRNA_rmsf/${REP}_crRNA_rmsf.dat"

run
EOF
    then
        echo "ERROR: crRNA analysis failed for $REP"
        echo "Check log: $LOG"
        exit 1
    fi

    # ----------------------------------------------
    # 3. Independently aligned DNA analysis
    # ----------------------------------------------
    # Calculates:
    #   - DNA RMSF after aligning on DNA
    # ----------------------------------------------

    LOG="$OUT_DIR/log/${REP}_dna_fit.log"

    if ! cpptraj -p "$TOP" > "$LOG" 2>&1 <<EOF
reference "$REF"
trajin "$TRAJ"

autoimage

# Align trajectory using DNA backbone
rms DNAFit $DNA_MASK reference

# DNA RMSF, per nucleotide
atomicfluct DNA_RMSF $DNA_RMSF_MASK byres out "$OUT_DIR/dna_rmsf/${REP}_dna_rmsf.dat"

run
EOF
    then
        echo "ERROR: DNA analysis failed for $REP"
        echo "Check log: $LOG"
        exit 1
    fi

    echo "Completed $REP successfully."

done

echo "----------------------------------------"
echo "All RMSF calculations completed."
echo "Results saved to: $OUT_DIR"

