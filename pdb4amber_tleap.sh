#!/bin/bash
#SBATCH -A loni_crispr1
#SBATCH -p single
#SBATCH -n 4
#SBATCH -t 0-01:00:00
#SBATCH -o /work/mzhai/crispr_pipeline_manual/output/pdb4amber_tleap_%j.out
#SBATCH -e /work/mzhai/crispr_pipeline_manual/error/pdb4amber_tleap_%j.err
#SBATCH -J pdb4amber_tleap_wt_complex
#SBATCH --mail-user=mzhai@tulane.edu
#SBATCH --mail-type=BEGIN,END,FAIL

set -eo pipefail

module purge

#QBC VERSION
module load amber/22/gcc-9.4.0-cuda-11.3.1-intel-mpi-2019.5.281

test -f "${AMBERHOME}/amber.sh" && source "${AMBERHOME}/amber.sh"

# ---------------------------------------------------------
# User settings
# ---------------------------------------------------------
NAME="wt_complex"                         # EDIT HERE
MDDIR="/work/mzhai/crispr_pipeline_manual/amber/add_mg/${NAME}"
PREF="${MDDIR}/${NAME}"

NACL_M=0.050       # 50 mM NaCl
MGCL2_M=0.010      # 10 mM MgCl2
PADDING=10.0       # Angstroms

cd "$MDDIR"

# ---------------------------------------------------------
# Prepare PDB
# ---------------------------------------------------------
pdb4amber \
    -i "${PREF}.pdb" \
    -o "${PREF}_toleap.pdb"

# ---------------------------------------------------------
# PASS 1: Solvate and determine box volume
# ---------------------------------------------------------
echo "===== TLEAP PASS 1: SOLVATION ====="

tleap -f - > "${PREF}_pass1.log" 2>&1 <<EOF
source leaprc.protein.ff14SB
source leaprc.RNA.OL3
source leaprc.DNA.OL15
source leaprc.water.opc
loadAmberParams frcmod.ionslm_126_opc

complex = loadPdb "${PREF}_toleap.pdb"

solvateOct complex OPCBOX ${PADDING}

saveAmberParm complex "${PREF}_preview.parm7" "${PREF}_preview.rst7"

quit
EOF

# ---------------------------------------------------------
# Calculate numbers of NaCl and MgCl2 formula units
# using the periodic box volume.
# Works for non-orthogonal (octahedral) boxes.
# ---------------------------------------------------------
echo "===== CALCULATING SALT COUNTS ====="

ION_INFO=$(python3 - "${PREF}_preview.rst7" \
    "$NACL_M" "$MGCL2_M" <<'PY'
import sys
import math

rst_file = sys.argv[1]
nacl_M = float(sys.argv[2])
mgcl2_M = float(sys.argv[3])

# Last line of an AMBER restart contains:
# a, b, c, alpha, beta, gamma
with open(rst_file) as f:
    lines = [line.strip() for line in f if line.strip()]

box = [float(x) for x in lines[-1].split()]
if len(box) != 6:
    raise ValueError("Could not read periodic box dimensions")

a, b, c, alpha, beta, gamma = box

alpha, beta, gamma = map(
    math.radians, (alpha, beta, gamma)
)

ca = math.cos(alpha)
cb = math.cos(beta)
cg = math.cos(gamma)

volume = a * b * c * math.sqrt(
    1 + 2*ca*cb*cg - ca**2 - cb**2 - cg**2
)

# 1 M = 0.000602214076 ions / Å^3
factor = 0.000602214076

n_nacl = round(nacl_M * factor * volume)
n_mgcl2 = round(mgcl2_M * factor * volume)

print(n_nacl, n_mgcl2, f"{volume:.2f}")
PY
)

read -r N_NACL N_MGCL2 BOX_VOLUME <<< "$ION_INFO"

echo "Box volume: ${BOX_VOLUME} A^3"
echo "NaCl pairs: ${N_NACL}"
echo "MgCl2 units: ${N_MGCL2}"

# Avoid passing count 0 to addIonsRand:
# in tleap, zero requests charge neutralization.
if (( N_NACL < 1 || N_MGCL2 < 1 )); then
    echo "ERROR: Calculated ion count is zero."
    exit 1
fi

# ---------------------------------------------------------
# PASS 2: Solvate, neutralize, and add salts
# ---------------------------------------------------------
echo "===== TLEAP PASS 2: ADDING IONS ====="

tleap -f - > "${PREF}_pass2.log" 2>&1 <<EOF
source leaprc.protein.ff14SB
source leaprc.RNA.OL3
source leaprc.DNA.OL15
source leaprc.water.opc
loadAmberParams frcmod.ionslm_126_opc

complex = loadPdb "${PREF}_toleap.pdb"

solvateOct complex OPCBOX ${PADDING}

# Neutralize complex
addIonsRand complex Na+ 0
addIonsRand complex Cl- 0

# Add 50 mM NaCl
addIonsRand complex Na+ ${N_NACL} Cl- ${N_NACL}

# Add 10 mM MgCl2
addIonsRand complex MG ${N_MGCL2} Cl- $((2 * N_MGCL2))

check complex
charge complex

saveAmberParm complex "${PREF}.parm7" "${PREF}.rst7"

quit
EOF

# ---------------------------------------------------------
# Cleanup temporary files
# ---------------------------------------------------------
rm -f "${PREF}_preview.parm7" \
      "${PREF}_preview.rst7"

echo "===== COMPLETED ====="
echo "Structure: ${NAME}"
echo "NaCl pairs added: ${N_NACL}"
echo "MgCl2 units added: ${N_MGCL2}"
echo "Topology: ${PREF}.parm7"
echo "Coordinates: ${PREF}.rst7"
echo "Done!"
