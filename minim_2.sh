#!/bin/bash
#SBATCH -A loni_crispr1
#SBATCH -p gpu2
#SBATCH --gres=gpu:1
#SBATCH -N 1
#SBATCH -n 24
#SBATCH -t 1-0:00:00
#SBATCH --array=1-5
#SBATCH -o /work/mzhai/crispr_pipeline_manual/output/minim_rep_%A_%a.out
#SBATCH -e /work/mzhai/crispr_pipeline_manual/error/minim_rep_%A_%a.err
#SBATCH -J minim_replicates_wt_complex
#SBATCH --mail-user=mzhai@tulane.edu
#SBATCH --mail-type=BEGIN,END,FAIL

set -eo pipefail

module purge
# QBD -- change -n to 32
#module load amber/22/intel-2021.5.1-cuda-11.5.2-intel-mpi-2021.5.1

#QBC -- change -n to 24
module load amber/22/gcc-9.4.0-cuda-11.3.1-intel-mpi-2019.5.281

test -f "${AMBERHOME}/amber.sh" && source "${AMBERHOME}/amber.sh"

LAUNCH="srun --ntasks=1 --kill-on-bad-exit"
EXE="${AMBERHOME}/bin/pmemd.cuda_SPFP"

# ---------------------------------------------------------
# User settings
# ---------------------------------------------------------
NAME="wt_complex"

MDDIR="/work/mzhai/crispr_pipeline_manual/amber/add_mg/${NAME}"

# ---------- CHECK IF YOU'RE USING THE CORRECT MDIN FILES ----------
MDINDIR="/work/mzhai/crispr_pipeline_manual/amber/scripts/minim_params_cas12complex" #complex vs crrna

PARM="${MDDIR}/${NAME}.parm7"

COMMON_MIN="${MDDIR}/minim_complex/common/00_Min.rst7"

REP="${SLURM_ARRAY_TASK_ID}"
REPDIR="${MDDIR}/minim_complex/rep${REP}"

mkdir -p "${REPDIR}"

# ---------------------------------------------------------
# Explicit random seeds
# ---------------------------------------------------------
SEEDS=(
    71277
    43891
    92153
    35629
    87314
)

SEED="${SEEDS[$((REP - 1))]}"

echo "=========================================="
echo "Replica: ${REP}"
echo "Random seed: ${SEED}"
echo "Directory: ${REPDIR}"
echo "=========================================="

# ---------------------------------------------------------
# Check required files
# ---------------------------------------------------------
if [[ ! -f "${PARM}" ]]; then
    echo "ERROR: topology missing:"
    echo "${PARM}"
    exit 1
fi

if [[ ! -f "${COMMON_MIN}" ]]; then
    echo "ERROR: common minimization restart missing:"
    echo "${COMMON_MIN}"
    exit 1
fi

# ---------------------------------------------------------
# Equilibration stages
# ---------------------------------------------------------
steps="\
01_Heat_0_50K \
02_Heat_50_100K \
03_Heat_100_200K_NPT \
04_Heat_200_300K_NPT \
05_Equil_300K_NPT_500ps \
06_Density_NPT_10ns \
"

# Every replica begins from exactly the same minimized coordinates.
ICRD="${COMMON_MIN}"

# ---------------------------------------------------------
# Run stages sequentially
# ---------------------------------------------------------
for step in ${steps}; do

    ORIGINAL_MDIN="${MDINDIR}/${step}.mdin"
    MDIN="${REPDIR}/${step}.mdin"
    OUT="${REPDIR}/${step}"

    if [[ ! -f "${ORIGINAL_MDIN}" ]]; then
        echo "ERROR: mdin missing:"
        echo "${ORIGINAL_MDIN}"
        exit 1
    fi

    # -----------------------------------------------------
    # Make a replica-specific copy of the input
    # -----------------------------------------------------
    cp "${ORIGINAL_MDIN}" "${MDIN}"

    # Only the first dynamics stage generates velocities.
    # Replace ig=-1 with this replica's explicit seed.
    if [[ "${step}" == "01_Heat_0_50K" ]]; then

        sed -i -E \
            "s/ig[[:space:]]*=[[:space:]]*-1/ig=${SEED}/" \
            "${MDIN}"

        echo "Using seed ${SEED} for ${step}"

    fi

    echo
    echo "=========================================="
    echo "Replica ${REP}"
    echo "Starting ${step}"
    echo "Input: ${ICRD}"
    echo "=========================================="

    # -----------------------------------------------------
    # Skip completed stage
    # -----------------------------------------------------
    if [[ -f "${OUT}.mdout" ]] && \
       { grep -q "Total wall time" "${OUT}.mdout" || \
         grep -q "wallclock() was called" "${OUT}.mdout"; }; then

        if [[ -f "${OUT}.rst7" ]]; then

            echo "${step} already complete; skipping."
            ICRD="${OUT}.rst7"
            continue

        else

            echo "ERROR: completed output exists but restart is missing."
            exit 1

        fi
    fi

    # -----------------------------------------------------
    # Run dynamics
    # -----------------------------------------------------
    ${LAUNCH} "${EXE}" -O \
        -i "${MDIN}" \
        -o "${OUT}.mdout" \
        -p "${PARM}" \
        -c "${ICRD}" \
        -r "${OUT}.rst7" \
        -x "${OUT}.nc" \
        -ref "${ICRD}" \
        -inf "${OUT}.mdinfo"

    # -----------------------------------------------------
    # Verify completion
    # -----------------------------------------------------
    if [[ ! -f "${OUT}.rst7" ]]; then
        echo "ERROR: ${step} restart was not created."
        exit 1
    fi

    if grep -q "Total wall time" "${OUT}.mdout" || \
       grep -q "wallclock() was called" "${OUT}.mdout"; then

        echo "${step} completed successfully."

    else

        echo "ERROR: ${step} did not finish correctly."
        echo "Check:"
        echo "${OUT}.mdout"
        exit 1

    fi

    # Feed this replica's restart to its next stage.
    ICRD="${OUT}.rst7"

done

echo
echo "=========================================="
echo "Replica ${REP} equilibration complete"
echo "Final restart:"
echo "${ICRD}"
echo "=========================================="
