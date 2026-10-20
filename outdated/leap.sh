#!/bin/bash
#SBATCH -A loni_crispr1
#SBATCH -p single
#SBATCH -n 12
#SBATCH -t 1-00:00:00
#SBATCH -o /work/mzhai/crispr_pipeline_manual/output/leap_%j.out
#SBATCH -e /work/mzhai/crispr_pipeline_manual/error/leap_%j.err
#SBATCH -J Leap_rank1
#SBATCH --mail-user=mzhai@tulane.edu
#SBATCH --mail-type=BEGIN,END,FAIL

module purge
# qbc version
module load amber/22/intel-19.0.5-intel-mpi-2019.5.281

source $AMBERHOME/amber.sh

SCRIPTS=/work/mzhai/crispr_pipeline_manual/amber/scripts

srun -n1 tleap -f $SCRIPTS/leap.in

echo "------------Done------------"

