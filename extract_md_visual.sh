#!/bin/bash
#SBATCH -A loni_crispr1
#SBATCH -p single
#SBATCH -n 1
#SBATCH -t 0-01:00:00
#SBATCH -o /work/mzhai/crispr_pipeline_manual/output/extract_md_visual_%j.out
#SBATCH -e /work/mzhai/crispr_pipeline_manual/error/extract_md_visual_%j.err
#SBATCH -J extract_md_visual
#SBATCH --mail-user=mzhai@tulane.edu
#SBATCH --mail-type=BEGIN,END,FAIL

module purge
# qbc version -- this is the only one where cpptraj works
module load amber/18/intel-19.0.5-mvapich-2.3.3

source $AMBERHOME/amber.sh

set -euo pipefail

MDDIR=/work/mzhai/crispr_pipeline_manual/amber/afm/rank01            # EDIT HERE
NAME=n0g2_000267_rank01                                             # EDIT HERE
TOP="${MDDIR}/${NAME}_ion.prmtop"
TRAJ="${MDDIR}/md/${NAME}_md_full.nc"                                # CHECK HERE

cd "$MDDIR"
# Pass 1: make the dry topology
cpptraj -p $TOP <<EOF
parmstrip :WAT,Na+,Cl-
parmwrite out ${NAME}_dry.prmtop
EOF

# Pass 2: make the dry, imaged, aligned trajectory
cpptraj -p $TOP <<EOF
trajin $TRAJ
autoimage
strip :WAT,Na+,Cl-
rms first :1-1378@CA
trajout ${NAME}_movie.pdb pdb
EOF
