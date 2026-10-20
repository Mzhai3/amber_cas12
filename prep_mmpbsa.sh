#!/bin/bash
#SBATCH -A loni_crispr1
#SBATCH -p single
#SBATCH -n 4
#SBATCH -t 0-06:00:00
#SBATCH -o /work/mzhai/crispr_pipeline_manual/output/mmpbsa_prep_%j.out
#SBATCH -e /work/mzhai/crispr_pipeline_manual/error/mmpbsa_prep_%j.err
#SBATCH -J mmpbsa_prep_wt_crrna
#SBATCH --mail-user=mzhai@tulane.edu
#SBATCH --mail-type=BEGIN,END,FAIL

set -eo pipefail

# --------------------------------------------------
# Load AMBER
# --------------------------------------------------
module purge

# QBC version - AMBER 22
module load amber/22/intel-19.0.5-intel-mpi-2019.5.281

source "${AMBERHOME}/amber.sh"

# readline 6 compatibility shim
export LD_LIBRARY_PATH="$HOME/libcompat:${LD_LIBRARY_PATH:-}"

# --------------------------------------------------
# Verify executables
# --------------------------------------------------
echo "Checking AMBER installation..."

cpptraj --version || {
    echo "ERROR: cpptraj failed to initialize."
    exit 1
}

for CMD in ante-MMPBSA.py cpptraj; do
    command -v "$CMD" >/dev/null || {
        echo "ERROR: $CMD not found."
        exit 1
    }
done

echo "AMBER successfully loaded."

# --------------------------------------------------
# Paths
# --------------------------------------------------
NAME="wt_crrna"
BASE="/work/mzhai/crispr_pipeline_manual/amber/add_mg"

TOP="$BASE/$NAME/${NAME}.parm7"
TRAJ_DIR="$BASE/$NAME/md"
OUT_DIR="$BASE/$NAME/mmpbsa"

TOP_DIR="$OUT_DIR/topology"
LOG_DIR="$OUT_DIR/log"
DRY_DIR="$OUT_DIR/trajectories/production"

mkdir -p "$TOP_DIR" "$LOG_DIR" "$DRY_DIR"

# --------------------------------------------------
# Component definitions
# --------------------------------------------------
# Protein: residues 1-1228
# crRNA: residues 1229-1249
# Catalytic Mg2+: residues 1250-1251

LIGAND_MASK=":1229-1251"

# Strip everything except protein, RNA and 2 Mg2+ ions
STRIP_MASK="!:1-1251"

# --------------------------------------------------
# Trajectory sampling settings
# --------------------------------------------------

# Select every 100th saved frame
FRAME_INTERVAL=100

# Number of selected frames per replicate
NUM_FRAMES=200

# Last original frame needed:
# 1, 101, 201, ..., 19901
LAST_FRAME=$((1 + (NUM_FRAMES - 1) * FRAME_INTERVAL))

# --------------------------------------------------
# Output topology files
# --------------------------------------------------
COM_TOP="$TOP_DIR/complex.parm7"
REC_TOP="$TOP_DIR/protein.parm7"
LIG_TOP="$TOP_DIR/crRNA_Mg.parm7"

# --------------------------------------------------
# Validate input topology
# --------------------------------------------------
if [[ ! -s "$TOP" ]]; then
    echo "ERROR: Topology not found: $TOP" >&2
    exit 1
fi

# --------------------------------------------------
# Inspect residue assignments
# --------------------------------------------------
echo "Checking protein, RNA, and Mg2+ boundaries..."

cpptraj -p "$TOP" > "$LOG_DIR/residue_check.log" 2>&1 <<EOF
resinfo :1225-1255
quit
EOF

echo "Residue information saved to:"
echo "$LOG_DIR/residue_check.log"

# --------------------------------------------------
# Generate MM/PBSA topologies
# --------------------------------------------------
echo "Generating MM/PBSA topologies..."

if ! ante-MMPBSA.py \
    -p "$TOP" \
    -c "$COM_TOP" \
    -r "$REC_TOP" \
    -l "$LIG_TOP" \
    -s "$STRIP_MASK" \
    -n "$LIGAND_MASK" \
    --radii mbondi2 \
    > "$LOG_DIR/topology.log" 2>&1
then
    echo "ERROR: Topology generation failed."
    echo "Check: $LOG_DIR/topology.log"
    exit 1
fi

# --------------------------------------------------
# Validate generated topologies
# --------------------------------------------------
for FILE in "$COM_TOP" "$REC_TOP" "$LIG_TOP"; do
    if [[ ! -s "$FILE" ]]; then
        echo "ERROR: Missing generated topology: $FILE" >&2
        exit 1
    fi
done

# --------------------------------------------------
# Print topology summaries
# --------------------------------------------------
echo "Inspecting generated topologies..."

for FILE in "$COM_TOP" "$REC_TOP" "$LIG_TOP"; do

    echo "Topology: $FILE"

    cpptraj -p "$FILE" <<EOF
resinfo :*
quit
EOF

done > "$LOG_DIR/generated_topologies.log" 2>&1

echo "Topologies generated successfully."

# --------------------------------------------------
# Find replicate directories
# --------------------------------------------------
shopt -s nullglob

REPS=("$TRAJ_DIR"/rep[0-9]*)

if (( ${#REPS[@]} == 0 )); then
    echo "ERROR: No replicate directories found." >&2
    exit 1
fi

# --------------------------------------------------
# Prepare solvent-free trajectories
# --------------------------------------------------
echo "----------------------------------------"
echo "Preparing solvent-free trajectories"
echo "Sampling every $FRAME_INTERVAL frames"
echo "Selected frames per replicate: $NUM_FRAMES"
echo "Original frames: 1 to $LAST_FRAME"
echo "----------------------------------------"

for REP_DIR in "${REPS[@]}"; do

    [[ -d "$REP_DIR" ]] || continue

    REP=$(basename "$REP_DIR")

    TRAJECTORIES=("$REP_DIR"/*.nc)

    if (( ${#TRAJECTORIES[@]} != 1 )); then
        echo "ERROR: Expected one .nc file in $REP_DIR" >&2
        echo "Found: ${#TRAJECTORIES[@]}" >&2
        exit 1
    fi

    TRAJ="${TRAJECTORIES[0]}"
    DRY_TRAJ="$DRY_DIR/${REP}_dry.nc"
    PREP_LOG="$LOG_DIR/${REP}_prepare.log"

    echo "----------------------------------------"
    echo "Processing $REP"
    echo "Input:  $TRAJ"
    echo "Output: $DRY_TRAJ"
    echo "----------------------------------------"

    # ----------------------------------------------
    # Extract 200 frames and strip solvent
    # ----------------------------------------------
    if ! cpptraj -p "$TOP" > "$PREP_LOG" 2>&1 <<EOF
trajin "$TRAJ" 1 $LAST_FRAME $FRAME_INTERVAL

# Reimage molecules into the primary box
autoimage

# Remove solvent and bulk ions
# Retain Cas12a, crRNA and both catalytic Mg2+ ions
strip $STRIP_MASK

# Write 200 selected snapshots
trajout "$DRY_TRAJ" netcdf

run
EOF
    then
        echo "ERROR: cpptraj failed for $REP" >&2
        echo "Check: $PREP_LOG" >&2
        exit 1
    fi

    # ----------------------------------------------
    # Validate output trajectory
    # ----------------------------------------------
    if [[ ! -s "$DRY_TRAJ" ]]; then
        echo "ERROR: Missing dry trajectory for $REP" >&2
        exit 1
    fi

    # Read trajectory frame count using cpptraj
    CHECK_LOG="$LOG_DIR/${REP}_verify.log"

    cpptraj -p "$COM_TOP" > "$CHECK_LOG" 2>&1 <<EOF
trajin "$DRY_TRAJ"
run
EOF

    # Extract frame count from NetCDF header
    if command -v ncdump >/dev/null 2>&1; then

        FRAME_COUNT=$(
            ncdump -h "$DRY_TRAJ" |
            sed -n 's/.*frame = UNLIMITED ; \/\/ (\([0-9]*\) currently).*/\1/p' |
            head -n 1
        )

        if [[ -n "$FRAME_COUNT" ]]; then

            echo "Frames extracted: $FRAME_COUNT"

            if (( FRAME_COUNT != NUM_FRAMES )); then
                echo "ERROR: Expected $NUM_FRAMES frames, got $FRAME_COUNT" >&2
                exit 1
            fi

        else
            echo "WARNING: Could not parse NetCDF frame count."
        fi
    fi

    echo "Completed $REP successfully."

done

echo "----------------------------------------"
echo "MM/PBSA preparation complete."
echo ""
echo "Topologies:   $TOP_DIR"
echo "Trajectories: $DRY_DIR"
echo "Logs:         $LOG_DIR"
echo "----------------------------------------"
