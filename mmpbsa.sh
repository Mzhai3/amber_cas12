#!/bin/bash
#SBATCH -A loni_crispr1
#SBATCH -p single
#SBATCH -n 2
#SBATCH -t 0-06:00:00
#SBATCH --array=0-39%20
#SBATCH -o /work/mzhai/crispr_pipeline_manual/output/mmpbsa_%A_%a.out
#SBATCH -e /work/mzhai/crispr_pipeline_manual/error/mmpbsa_%A_%a.err
#SBATCH -J mmpbsa_array
#SBATCH --mail-user=mzhai@tulane.edu
#SBATCH --mail-type=END,FAIL

set -eo pipefail

# --------------------------------------------------
# Load AMBER 22
# --------------------------------------------------
module purge
module load amber/22/intel-19.0.5-intel-mpi-2019.5.281

source "${AMBERHOME}/amber.sh"

# readline compatibility
export LD_LIBRARY_PATH="$HOME/libcompat:${LD_LIBRARY_PATH:-}"

# --------------------------------------------------
# Paths
# --------------------------------------------------
NAME="wt_crrna"
BASE="/work/mzhai/crispr_pipeline_manual/amber/add_mg"

OUT_DIR="$BASE/$NAME/mmpbsa"

COM_TOP="$OUT_DIR/topology/complex.parm7"
REC_TOP="$OUT_DIR/topology/protein.parm7"
LIG_TOP="$OUT_DIR/topology/crRNA_Mg.parm7"

# --------------------------------------------------
# Array configuration
# --------------------------------------------------

NUM_REPS=5
CHUNKS_PER_REP=8
FRAMES_PER_CHUNK=25

TASK_ID="${SLURM_ARRAY_TASK_ID}"

# Array indices 0-7 correspond to rep1,
# 8-15 to rep2, and so on.
REP_NUM=$((TASK_ID / CHUNKS_PER_REP + 1))
CHUNK_NUM=$((TASK_ID % CHUNKS_PER_REP + 1))

REP="rep${REP_NUM}"

# Frame range in the prepared trajectory
START_FRAME=$(((CHUNK_NUM - 1) * FRAMES_PER_CHUNK + 1))
END_FRAME=$((CHUNK_NUM * FRAMES_PER_CHUNK))

# --------------------------------------------------
# Input trajectory
# --------------------------------------------------
DRY_TRAJ="$OUT_DIR/trajectories/production/${REP}_dry.nc"

# --------------------------------------------------
# Unique output directory for each task
# --------------------------------------------------
CHUNK_DIR="$OUT_DIR/results/array/$REP/chunk${CHUNK_NUM}"

mkdir -p "$CHUNK_DIR"

INPUT="$CHUNK_DIR/mmpbsa.in"

# --------------------------------------------------
# Validate required files
# --------------------------------------------------
for FILE in \
    "$COM_TOP" \
    "$REC_TOP" \
    "$LIG_TOP" \
    "$DRY_TRAJ"
do
    if [[ ! -s "$FILE" ]]; then
        echo "ERROR: Missing input: $FILE" >&2
        exit 1
    fi
done

command -v MMPBSA.py >/dev/null || {
    echo "ERROR: Serial MMPBSA.py not available." >&2
    exit 1
}

# --------------------------------------------------
# Create chunk-specific MM/PBSA input
# --------------------------------------------------
cat > "$INPUT" <<EOF
&general
    startframe=$START_FRAME,
    endframe=$END_FRAME,
    interval=1,
    keep_files=0,
    verbose=1,
/
&pb
    istrng=0.080,
    radiopt=0,
/
EOF

# --------------------------------------------------
# Report task information
# --------------------------------------------------
echo "----------------------------------------"
echo "Replicate: $REP"
echo "Chunk: $CHUNK_NUM"
echo "Frames: $START_FRAME to $END_FRAME"
echo "Working directory: $CHUNK_DIR"
echo "----------------------------------------"

# --------------------------------------------------
# Run serial MM/PBSA
# --------------------------------------------------
cd "$CHUNK_DIR"

MMPBSA.py -O \
    -i "$INPUT" \
    -o "${REP}_chunk${CHUNK_NUM}_FINAL_RESULTS.dat" \
    -eo "${REP}_chunk${CHUNK_NUM}_ENERGY.csv" \
    -cp "$COM_TOP" \
    -rp "$REC_TOP" \
    -lp "$LIG_TOP" \
    -y "$DRY_TRAJ"

# --------------------------------------------------
# Validate output
# --------------------------------------------------
RESULT="${REP}_chunk${CHUNK_NUM}_FINAL_RESULTS.dat"
ENERGY="${REP}_chunk${CHUNK_NUM}_ENERGY.csv"

if [[ ! -s "$RESULT" || ! -s "$ENERGY" ]]; then
    echo "ERROR: Missing MM/PBSA results." >&2
    exit 1
fi

echo "Completed $REP chunk $CHUNK_NUM."
