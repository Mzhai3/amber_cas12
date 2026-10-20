#!/bin/bash
#SBATCH -A loni_crispr1
#SBATCH -p gpu2
#SBATCH --gres=gpu:1
#SBATCH -N 1
#SBATCH -n 24
#SBATCH -t 1-00:00:00
#SBATCH -o /work/mzhai/crispr_pipeline_manual/output/40k_top1_relaxation_%j.out
#SBATCH -e /work/mzhai/crispr_pipeline_manual/error/40k_top_1_relaxation_%j.err
#SBATCH -J 40k_top1_relaxation
#SBATCH --mail-user=mzhai@tulane.edu
#SBATCH --mail-type=BEGIN,END,FAIL

module purge
# qbc version
module load amber/22/gcc-9.4.0-cuda-11.3.1-intel-mpi-2019.5.281

source $AMBERHOME/amber.sh

HOME=/ddnB/work/mzhai/crispr_pipeline_manual/amber

#----------------EDIT HERE----------------
# Put paths for prmtop and inpcrd files generated from tleap
PDIR=$HOME/afm/wt_complex_validation
NAME=wt_complex_val
PRMTOP="${PDIR}/${NAME}_ion.prmtop"
INPCRD="${PDIR}/${NAME}_ion.inpcrd"
# Put unique identifier for sample you're minimizing
SUFFIX=$NAME
#----------------EDIT HERE----------------


mkdir -p $PDIR/minim
OUTDIR=$PDIR/minim

cd $HOME/scripts/all_relax

pwd

echo "starting 1min at $(date)"

srun -n1 pmemd -O -i 1min.in \
            -o "$OUTDIR/1min_${SUFFIX}.out" -p $PRMTOP -c $INPCRD -r "$OUTDIR/1min_${SUFFIX}.rst7" \
            -inf "$OUTDIR/1min_${SUFFIX}.info" -ref $INPCRD -x "$OUTDIR/mdcrd_${SUFFIX}.1min"
echo "ending 1min at $(date)"

echo "starting 2mdheat at $(date)"

srun -n1 pmemd.cuda -O -i 2mdheat.in\
            -o "$OUTDIR/2mdheat_${SUFFIX}.out" -p $PRMTOP -c "$OUTDIR/1min_${SUFFIX}.rst7" -r "$OUTDIR/2mdheat_${SUFFIX}.rst7" \
            -inf "$OUTDIR/2mdheat_${SUFFIX}.info" -ref "$OUTDIR/1min_${SUFFIX}.rst7" -x "$OUTDIR/mdcrd_${SUFFIX}.2mdheat"
echo "ending 2mdheat at $(date)"

echo "starting 3md at $(date)"

srun -n1 pmemd.cuda -O -i 3md.in\
            -o "$OUTDIR/3md_${SUFFIX}.out" -p $PRMTOP -c "$OUTDIR/2mdheat_${SUFFIX}.rst7" -r "$OUTDIR/3md_${SUFFIX}.rst7" \
            -inf "$OUTDIR/3md_${SUFFIX}.info" -ref "$OUTDIR/2mdheat_${SUFFIX}.rst7" -x "$OUTDIR/mdcrd_${SUFFIX}.3md"
echo "ending 3md at $(date)"

echo "starting 4md at $(date)"

srun -n1 pmemd.cuda -O -i 4md.in\
            -o "$OUTDIR/4md_${SUFFIX}.out" -p $PRMTOP -c "$OUTDIR/3md_${SUFFIX}.rst7" -r "$OUTDIR/4md_${SUFFIX}.rst7" \
            -inf "$OUTDIR/4md_${SUFFIX}.info" -ref "$OUTDIR/3md_${SUFFIX}.rst7" -x "$OUTDIR/mdcrd_${SUFFIX}.4md"
echo "ending 4md at $(date)"

echo "starting 5min at $(date)"

srun -n1 pmemd -O -i 5min.in\
            -o "$OUTDIR/5min_${SUFFIX}.out" -p $PRMTOP -c "$OUTDIR/4md_${SUFFIX}.rst7" -r "$OUTDIR/5min_${SUFFIX}.rst7" \
            -inf "$OUTDIR/5min_${SUFFIX}.info" -ref "$OUTDIR/4md_${SUFFIX}.rst7" -x "$OUTDIR/mdcrd_${SUFFIX}.5min"
echo "ending 5min at $(date)"

echo "starting 6md at $(date)"

srun -n1 pmemd.cuda -O -i 6md.in\
            -o "$OUTDIR/6md_${SUFFIX}.out" -p $PRMTOP -c "$OUTDIR/5min_${SUFFIX}.rst7" -r "$OUTDIR/6md_${SUFFIX}.rst7" \
            -inf "$OUTDIR/6md_${SUFFIX}.info" -ref "$OUTDIR/5min_${SUFFIX}.rst7" -x "$OUTDIR/mdcrd_${SUFFIX}.6md"
echo "ending 6md at $(date)"

echo "starting 7md at $(date)"

srun -n1 pmemd.cuda -O -i 7md.in\
            -o "$OUTDIR/7md_${SUFFIX}.out" -p $PRMTOP -c "$OUTDIR/6md_${SUFFIX}.rst7" -r "$OUTDIR/7md_${SUFFIX}.rst7" \
            -inf "$OUTDIR/7md_${SUFFIX}.info" -ref "$OUTDIR/6md_${SUFFIX}.rst7" -x "$OUTDIR/mdcrd_${SUFFIX}.7md"
echo "ending 7md at $(date)"

echo "starting 8md at $(date)"

srun -n1 pmemd.cuda -O -i 8md.in\
            -o "$OUTDIR/8md_${SUFFIX}.out" -p $PRMTOP -c "$OUTDIR/7md_${SUFFIX}.rst7" -r "$OUTDIR/8md_${SUFFIX}.rst7" \
            -inf "$OUTDIR/8md_${SUFFIX}.info" -ref "$OUTDIR/7md_${SUFFIX}.rst7" -x "$OUTDIR/mdcrd_${SUFFIX}.8md"
echo "ending 8md at $(date)"

echo "starting 9md at $(date)"

srun -n1 pmemd.cuda -O -i 9md.in\
            -o "$OUTDIR/9md_${SUFFIX}.out" -p $PRMTOP -c "$OUTDIR/8md_${SUFFIX}.rst7" -r "$OUTDIR/9md_${SUFFIX}.rst7" \
            -inf "$OUTDIR/9md_${SUFFIX}.info" -ref "$OUTDIR/8md_${SUFFIX}.rst7" -x "$OUTDIR/mdcrd_${SUFFIX}.9md"
echo "ending 9md at $(date)"

