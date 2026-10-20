#!/bin/bash
#SBATCH -A loni_crispr1
#SBATCH -p single
#SBATCH -n 32
#SBATCH -t 0-01:00:00
#SBATCH -o /work/mzhai/crispr_pipeline_manual/output/cluster_md_centroids_%j.out
#SBATCH -e /work/mzhai/crispr_pipeline_manual/error/cluster_md_centroids_%j.err
#SBATCH -J Cluster_md_centroids_crrna_Lb000
#SBATCH --mail-user=mzhai@tulane.edu
#SBATCH --mail-type=BEGIN,END,FAIL

module purge
# qbc version -- this is the only one where cpptraj works
module load amber/18/intel-19.0.5-mvapich-2.3.3

source $AMBERHOME/amber.sh

set -euo pipefail
MDDIR="/work/mzhai/crispr_pipeline_manual/amber/afm"            # EDIT HERE
NAME="Lb000_crrna"                                             # EDIT HERE
SAMPLEDIR="${MDDIR}/${NAME}"
TOP="${SAMPLEDIR}/minim_complex/${NAME}.parm7"
TRAJ="${SAMPLEDIR}/md_complex/${NAME}_md.nc"                                # CHECK HERE

STRIDE=10                                                           # every Nth frame for the pre-run

OUTDIR="$SAMPLEDIR/cluster"
# PREDIR=$OUTDIR/prerun # i ain't doing this
FULLDIR="$OUTDIR/fullrun"
mkdir -p "$OUTDIR" "$FULLDIR"

# ----------------------------------------------------------------------
# STAGE 1: strided pre-run -- fast sanity check on parameters + memory
# ----------------------------------------------------------------------
# cd "$PREDIR"
# srun -n1 cpptraj -p "$TOP" <<EOF
# trajin $TRAJ 1 last $STRIDE
# strip :WAT,Na+,Cl-
# cluster C1 hieragglo epsilon 2.0 rms :1-1378@CA \
#     out cnumvtime.dat summary summary.dat \
#     repout cluster repfmt pdb
# EOF



# echo "==== PRE-RUN SUMMARY ===="
# cat "$PREDIR/summary.dat"
# echo "========================="

# ----------------------------------------------------------------------
# STAGE 2: full run -- all frames
# Inspect the pre-run summary first; comment this stage out until you've
# confirmed epsilon 2.0 gives a sane number of clusters.
# ----------------------------------------------------------------------

# uncomment when ready and comment out the first one
cd "$FULLDIR"
cpptraj -p "$TOP" <<EOF
trajin $TRAJ
autoimage
strip :WAT,Na+,Cl-
cluster C1 hieragglo epsilon 2.0 rms @CA \
    out cnumvtime.dat summary summary.dat \
    repout cluster repfmt pdb
EOF