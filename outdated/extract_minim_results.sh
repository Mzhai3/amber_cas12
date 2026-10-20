#!/bin/bash
#SBATCH -A loni_crispr1
#SBATCH -p single
#SBATCH -n 1
#SBATCH -t 0-01:00:00
#SBATCH -o /work/mzhai/crispr_pipeline_manual/output/extract_minim_results_%j.out
#SBATCH -e /work/mzhai/crispr_pipeline_manual/error/extract_minim_results_%j.err
#SBATCH -J extract_minim_000
#SBATCH --mail-user=mzhai@tulane.edu
#SBATCH --mail-type=BEGIN,END,FAIL

module purge
# qbc version
module load amber/22/gcc-9.4.0-cuda-11.3.1-intel-mpi-2019.5.281

echo "AMBERHOME is $AMBERHOME"
test -f ${AMBERHOME}/amber.sh && source ${AMBERHOME}/amber.sh

set -uo pipefail

RESDIR="/work/mzhai/crispr_pipeline_manual/amber/afm"
SAMPLES=("Lb000_crrna")
#SAMPLES=("Lb001_crrna" "Lb004_crrna" "Lb005_crrna" "Lb011_crrna" "Lb014_crrna" "Lb024_crrna" "Lb025_crrna" "Lb029_crrna" "Lb033_crrna")	# EDIT HERE
steps=("000_Min" "001_NPT" "002_NPT" "003_NPT" "01_Min" "02_Heat" "03_Equil_NPT_solvent" "04_Min_solute" "05_Heat_solute" "06_Equil_solute" "07_Equil_solute" "08_Equil_solute" "09_Equil_solute")
min_steps=("000_Min" "01_Min" "04_Min_solute")

shopt -s nullglob

for sample in "${SAMPLES[@]}"; do

	MINIMDIR="$RESDIR/${sample}/minim_complex"

	cd "$MINIMDIR" || { echo "skipping $sample — cannot cd to $MINIMDIR"; continue; }

	for step in "${steps[@]}"; do
		mkdir -p "$step"
		files=( "${step}"*.mdout )
		(( ${#files[@]} )) && mv "${files[@]}" "$step"/

		files=( "$step"/"${step}"*.mdout )
  		(( ${#files[@]} )) || continue

		(
			cd "$step" || exit
			if [[ " ${min_steps[*]} " =~ " ${step} " ]]; then
				process_minout.perl "${step}"*.mdout
			else
				process_mdout.perl "${step}"*.mdout
			fi
		)
	done
done








