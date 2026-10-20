#!/bin/bash
#SBATCH -A loni_space01
#SBATCH -p single
#SBATCH -n 2
#SBATCH -t 1-00:00:00
#SBATCH -o /work/mzhai/crispr_pipeline_manual/output/mmpbsa_test_%j.out
#SBATCH -e /work/mzhai/crispr_pipeline_manual/error/mmpbsa_test_%j.err
#SBATCH -J mmpbsa_test1frame
#SBATCH --mail-user=mzhai@tulane.edu
#SBATCH --mail-type=BEGIN,END,FAIL

set -eo pipefail

# NOTE for Cas12 + crRNA + DNA systems the topology will be numbered like this
# protein  1-1228
# DNA      1229-1266
# RNA      1267-1306
# ion      1307-1373
# water    1374-44027

# for Cas12 + crRNA the topology will be numbered like this
# protein  1-1228
# RNA      1229-1268
# ion      1269-1299
# water    1300-41954

# =================EDIT HERE=================
isComplex=true
NAME="wt_complex_val"

AMBER="/work/mzhai/crispr_pipeline_manual/amber"
TOP="${AMBER}/afm/${NAME}/minim_complex/${NAME}.parm7"
TRAJ="${AMBER}/afm/${NAME}/md_complex/${NAME}_md.nc"
OUTDIR="${AMBER}/afm/${NAME}/mmpbsa"

WORK="${OUTDIR}/work_1frame"
mkdir -p "$WORK" && cd "$WORK"

if [[ "$isComplex" == true ]]; then
    RANGE=":1229-1266"
    COMPLEX="${OUTDIR}/${NAME}_drycomp.parm7"
    RECEPTOR="${OUTDIR}/${NAME}_cas12_crrna.parm7"
    LIGAND="${OUTDIR}/${NAME}_dna.parm7"
    MMPBSAIN="${AMBER}/scripts/mmpbsa_complex.in"
else
    RANGE=":1229-1268"
    COMPLEX="${OUTDIR}/${NAME}_drycomp.parm7"
    RECEPTOR="${OUTDIR}/${NAME}_cas12.parm7"
    LIGAND="${OUTDIR}/${NAME}_crrna.parm7"
    MMPBSAIN="${AMBER}/scripts/mmpbsa_crrna.in"
fi
module purge
module load amber/22/intel-19.0.5-intel-mpi-2019.5.281
: "${AMBERHOME:?AMBERHOME unset - module load failed}"
source "$AMBERHOME/amber.sh"

export LD_LIBRARY_PATH=$HOME/libcompat:$LD_LIBRARY_PATH

cpptraj --version || { echo "cpptraj broken, aborting"; exit 1; }

# one analyzed frame, PB only, interactive
cat > time_1frame.in << 'EOF'
&general
   startframe=1, endframe=1, interval=1, verbose=1,
   receptor_mask=":1-1228,1267-1306",
   ligand_mask=":1229-1266",
/
&pb
   istrng=0.150, inp=1, radiopt=0,
   indi=1.0, exdi=80.0, scale=2.0, fillratio=2.0,
/
EOF

time $AMBERHOME/bin/MMPBSA.py -O -i time_1frame.in -o t.dat \
  -sp "$TOP" -cp "$COMPLEX" -rp "$RECEPTOR" -lp "$LIGAND" -y "$TRAJ"
