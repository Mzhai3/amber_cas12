#!/bin/bash
#SBATCH -A loni_crispr1
#SBATCH -p gpu2
#SBATCH --gres=gpu:1
#SBATCH -N 1
#SBATCH -n 24
#SBATCH -t 0-00:15:00
#SBATCH -o /work/mzhai/crispr_pipeline_manual/output/minim_common_%j.out
#SBATCH -e /work/mzhai/crispr_pipeline_manual/error/minim_common_%j.err
#SBATCH -J minim_common_wt_complex
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
OUTDIR="${MDDIR}/minim_complex/common"

# ---------- CHECK IF YOU'RE USING THE CORRECT MDIN FILES ----------
MDINDIR="/work/mzhai/crispr_pipeline_manual/amber/scripts/minim_params_cas12complex" #complex vs crrna

PARM="${MDDIR}/${NAME}.parm7"
STARTCRD="${MDDIR}/${NAME}.rst7"
MDIN="${MDINDIR}/00_Min.mdin"

mkdir -p "${OUTDIR}"

OUT="${OUTDIR}/00_Min"

# ---------------------------------------------------------
# Check input files
# ---------------------------------------------------------
for file in "${PARM}" "${STARTCRD}" "${MDIN}"; do
    if [[ ! -f "${file}" ]]; then
        echo "ERROR: missing file:"
        echo "${file}"
        exit 1
    fi
done

# ---------------------------------------------------------
# Skip if minimization already completed
# ---------------------------------------------------------
if [[ -f "${OUT}.mdout" ]] && \
   grep -q "Total wall time" "${OUT}.mdout" && \
   [[ -f "${OUT}.rst7" ]]; then

    echo "Common minimization already completed."
    echo "Restart: ${OUT}.rst7"
    exit 0
fi

# ---------------------------------------------------------
# Run common minimization
# ---------------------------------------------------------
echo "Running common minimization..."

${LAUNCH} "${EXE}" -O \
    -i "${MDIN}" \
    -o "${OUT}.mdout" \
    -p "${PARM}" \
    -c "${STARTCRD}" \
    -r "${OUT}.rst7" \
    -ref "${STARTCRD}" \
    -inf "${OUT}.mdinfo"

# ---------------------------------------------------------
# Verify completion
# ---------------------------------------------------------
if [[ ! -f "${OUT}.rst7" ]]; then
    echo "ERROR: minimization restart was not created."
    exit 1
fi

if grep -q "Total wall time" "${OUT}.mdout" || \
   grep -q "wallclock() was called" "${OUT}.mdout"; then

    echo "Common minimization completed successfully."
    echo "Restart:"
    echo "${OUT}.rst7"

else

    echo "ERROR: minimization did not finish correctly."
    exit 1
fi