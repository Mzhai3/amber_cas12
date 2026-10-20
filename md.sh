#!/bin/bash
#SBATCH -A loni_crispr2
#SBATCH -p gpu2
#SBATCH --gres=gpu:1
#SBATCH -N 1
#SBATCH -n 24
#SBATCH -t 3-00:00:00
#SBATCH --array=1-5
#SBATCH -o /work/mzhai/crispr_pipeline_manual/output/Prod_rep_%A_%a.out
#SBATCH -e /work/mzhai/crispr_pipeline_manual/error/Prod_rep_%A_%a.err
#SBATCH -J prod_wt_complex
#SBATCH --mail-user=mzhai@tulane.edu
#SBATCH --mail-type=BEGIN,END,FAIL

set -eo pipefail

# ---------------------------------------------------------
# Load AMBER
# ---------------------------------------------------------
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
MDINDIR="/work/mzhai/crispr_pipeline_manual/amber/scripts/minim_params_cas12complex"

PARM="${MDDIR}/${NAME}.parm7"
MDIN="${MDINDIR}/07_Prod_NVT_200ns.mdin"

# Replica number from SLURM array
REP="${SLURM_ARRAY_TASK_ID}"

# Final equilibrated restart for this replica
EQUILDIR="${MDDIR}/minim_complex/rep${REP}"
STARTCRD="${EQUILDIR}/06_Density_NPT_10ns.rst7"

# Production output directory
PRODDIR="${MDDIR}/md/rep${REP}"
mkdir -p "${PRODDIR}"

OUT="${PRODDIR}/Prod_200ns"

# ---------------------------------------------------------
# Check required files
# ---------------------------------------------------------
if [[ ! -f "${PARM}" ]]; then
    echo "ERROR: topology not found:"
    echo "${PARM}"
    exit 1
fi

if [[ ! -f "${STARTCRD}" ]]; then
    echo "ERROR: equilibrated restart not found:"
    echo "${STARTCRD}"
    exit 1
fi

if [[ ! -f "${MDIN}" ]]; then
    echo "ERROR: production mdin not found:"
    echo "${MDIN}"
    exit 1
fi

# ---------------------------------------------------------
# Skip if already completed
# ---------------------------------------------------------
if [[ -f "${OUT}.mdout" ]] && \
   { grep -q "Total wall time" "${OUT}.mdout" || \
     grep -q "wallclock() was called" "${OUT}.mdout"; }; then

    echo "Replica ${REP} production already completed."

    if [[ -f "${OUT}.rst7" ]]; then
        echo "Final restart:"
        echo "${OUT}.rst7"
        exit 0
    else
        echo "ERROR: completed mdout found but restart is missing."
        exit 1
    fi
fi

# ---------------------------------------------------------
# Run 200 ns production
# ---------------------------------------------------------
echo
echo "=================================================="
echo "Replica ${REP}"
echo "Starting 200 ns production"
echo "Input restart:"
echo "${STARTCRD}"
echo "=================================================="
echo

${LAUNCH} "${EXE}" -O \
    -i "${MDIN}" \
    -o "${OUT}.mdout" \
    -p "${PARM}" \
    -c "${STARTCRD}" \
    -r "${OUT}.rst7" \
    -x "${OUT}.nc" \
    -inf "${OUT}.mdinfo"

# ---------------------------------------------------------
# Verify completion
# ---------------------------------------------------------
if [[ ! -f "${OUT}.rst7" ]]; then
    echo "ERROR: production restart was not created."
    exit 1
fi

if grep -q "Total wall time" "${OUT}.mdout" || \
   grep -q "wallclock() was called" "${OUT}.mdout"; then

    echo
    echo "=================================================="
    echo "Replica ${REP} completed 200 ns successfully"
    echo "Trajectory:"
    echo "${OUT}.nc"
    echo "Final restart:"
    echo "${OUT}.rst7"
    echo "=================================================="

else

    echo "ERROR: production did not finish correctly."
    echo "Check:"
    echo "${OUT}.mdout"
    exit 1
fi
