#!/bin/bash
#SBATCH -A loni_crispr1
#SBATCH -p single
#SBATCH -n 4
#SBATCH -t 1-00:00:00
#SBATCH -o /work/mzhai/crispr_pipeline_manual/output/sasa_shortcut_%j.out
#SBATCH -e /work/mzhai/crispr_pipeline_manual/error/sasa_shortcut_%j.err
#SBATCH -J sasa_shortcut
#SBATCH --mail-user=mzhai@tulane.edu
#SBATCH --mail-type=BEGIN,END,FAIL
# ---------------------------------------------------------------------------
# sasa_shortcut.sh — SASA for a single trajectory, written to CSV.
#
#   Edit the EDIT THESE block below, then:  sbatch sasa_shortcut.sh
#   RUN ON QBC
#
# Output: <prefix>_sasa.csv   (one row per frame, one column per measurement)
#         <prefix>_sasa_mean.csv (mean +/- SD per column)
# ---------------------------------------------------------------------------
set -euo pipefail
module purge
module load amber/18/intel-19.0.5-mvapich-2.3.3
set +u
source $AMBERHOME/amber.sh
set -u
# ========================= EDIT THESE =======================================
NAMES=("wt_complex_val" "Lb000_crrna" "Lb001_crrna" "Lb004_crrna" "Lb005_crrna" "Lb011_crrna" "Lb014_crrna" "Lb024_crrna" "Lb025_crrna" "Lb029_crrna" "Lb033_crrna" "Lb001_complex" "Lb004_complex" "Lb005_complex" "Lb011_complex" "Lb014_complex" "Lb024_complex" "Lb025_complex" "Lb029_complex" "Lb033_complex")
# ============================================================================
ALL="/work/mzhai/crispr_pipeline_manual/amber/afm/sasa_shortcut_all.csv"
echo "name,total_molsurf_A2" > "$ALL"

for NAME in "${NAMES[@]}"; do
#  TOP="/work/mzhai/crispr_pipeline_manual/amber/afm/${NAME}/minim_complex/${NAME}.parm7"
  PDB="/work/mzhai/crispr_pipeline_manual/amber/afm/${NAME}/${NAME}_toleap.pdb"

  OUTDIR="/work/mzhai/crispr_pipeline_manual/amber/afm/${NAME}/sasa_shortcut"


  # ------------------------- analysis settings -------------------------------
  SOLVENT=":WAT,HOH,Na+,Cl-,K+,MG"
  SOLUTE="!(${SOLVENT})"
  PROBE=1.4

#  [[ -r "$TOP"  ]] || { echo "ERROR: cannot read topology  $TOP"  >&2; exit 1; }
  [[ -r "$PDB" ]] || { echo "ERROR: cannot read pdb $PDB" >&2; exit 1; }

  mkdir -p "$OUTDIR"

  CPPTRAJ="cpptraj.OMP"; export OMP_NUM_THREADS=4

  RAW="${OUTDIR}/${NAME}_sasa_shortcut.dat"
  IN="${OUTDIR}/${NAME}.cpptraj.in"

  # ---- cpptraj input --------------------------------------------------------
  {
  cat <<EOF
  parm ${PDB}
  trajin ${PDB}

  molsurf total_molsurf ${SOLUTE} probe ${PROBE} out ${RAW} radii parse

  run
  quit

EOF
  } > "$IN"

  echo "[$(date)] running ${CPPTRAJ} on ${NAME}"
  "$CPPTRAJ" -i "$IN"

  # ---- convert cpptraj .dat -> CSV ------------------------------------------
  CSV="${OUTDIR}/${NAME}_sasa_shortcut.csv"
  sed -e 's/^#*[[:space:]]*//' -e 's/[[:space:]]\+/,/g' -e 's/,$//' "$RAW" > "$CSV"

  val=$(awk -F, 'NR>1{print $2; exit}' "$CSV")
  [[ -n "$val" ]] || { echo "ERROR: no SASA value parsed from $CSV" >&2; exit 1; }

  printf '%s,%s\n' "$NAME" "$val" >> "$ALL"

  echo "[$(date)] done"
  echo "per-frame: $CSV"

done
