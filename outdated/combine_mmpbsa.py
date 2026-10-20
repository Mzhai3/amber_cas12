#!/usr/bin/env python3
"""
Combine per-chunk MMPBSA CSV output into one CSV per
(method, section) pair.

Example:
    python combine_energy_chunks.py \
        --input-dir /scratch/mzhai/mmpbsa_run \
        --pattern 'work_*/wt_complex_val_chunk*.csv' \
        --output-dir combined_energy_csvs
"""

import argparse
import io
import re
import sys
from collections import defaultdict
from pathlib import Path

import pandas as pd


# ---------------------------------------------------------
# LABELS USED INSIDE THE MMPBSA CSV FILES
# ---------------------------------------------------------

METHOD_LABELS = {
    "GENERALIZED BORN:": "Generalized_born",
    "POISSON BOLTZMANN:": "Poisson_boltzmann",
}

SECTION_LABELS = {
    "Complex Energy Terms": "complex",
    "Receptor Energy Terms": "receptor",
    "Ligand Energy Terms": "ligand",
    "DELTA Energy Terms": "delta",
}


def log(msg=""):
    """Print and flush immediately so output survives job buffering."""
    print(msg, flush=True)


# ---------------------------------------------------------
# GET CHUNK NUMBER FROM FILE NAME
# ---------------------------------------------------------

def chunk_number(path):
    """
    Extract chunk number from a filename like:

    wt_complex_val_chunk0.csv
    wt_complex_val_chunk12.csv
    """

    match = re.search(
        r"chunk(\d+)",
        Path(path).stem,
        flags=re.I
    )

    if not match:
        raise ValueError(
            f"Could not determine chunk number from filename: {path}"
        )

    return int(match.group(1))


# ---------------------------------------------------------
# PARSE ONE MMPBSA FILE
# ---------------------------------------------------------

def parse_energy_file(path):
    """
    Reads one MMPBSA chunk file and separates it into:

    Generalized Born:
        complex / receptor / ligand / delta

    Poisson Boltzmann:
        complex / receptor / ligand / delta
    """

    lines = Path(path).read_text().splitlines()

    tables = {}
    current_method = None
    i = 0

    while i < len(lines):

        line = lines[i].strip()

        # Detect GENERALIZED BORN or POISSON BOLTZMANN
        if line in METHOD_LABELS:
            current_method = METHOD_LABELS[line]
            i += 1
            continue

        # Detect Complex, Receptor, Ligand, or DELTA
        if line in SECTION_LABELS:

            if current_method is None:
                raise ValueError(
                    f"Found section '{line}' before an energy method "
                    f"in {path}"
                )

            section = SECTION_LABELS[line]

            # Next line should contain the column headers
            header = lines[i + 1].strip()

            data_lines = []
            i += 2

            # Read until we reach a blank line
            while i < len(lines) and lines[i].strip():
                data_lines.append(lines[i].strip())
                i += 1

            csv_block = "\n".join([header] + data_lines)

            df = pd.read_csv(io.StringIO(csv_block))

            tables[(current_method, section)] = df

            continue

        i += 1

    return tables


# ---------------------------------------------------------
# COMBINE ALL CHUNKS
# ---------------------------------------------------------

def combine_energy_chunks(
    input_dir=".",
    pattern="work_*/wt_complex_val_chunk*.csv",
    output_dir="combined_energy_csvs",
):

    input_dir = Path(input_dir).expanduser()

    output_path_base = Path(output_dir).expanduser()

    # Absolute output paths are respected; relative ones sit under input_dir
    if not output_path_base.is_absolute():
        output_path_base = input_dir / output_path_base

    output_path_base.mkdir(parents=True, exist_ok=True)

    # -----------------------------------------------------
    # FIND ALL FILES
    # -----------------------------------------------------

    files = sorted(input_dir.glob(pattern), key=chunk_number)

    if not files:
        raise FileNotFoundError(
            f"No files matching:\n"
            f"{pattern}\n"
            f"were found inside:\n"
            f"{input_dir.resolve()}"
        )

    log(f"\nFound {len(files)} chunk files.\n")

    # -----------------------------------------------------
    # EXPECTED SECTIONS
    # -----------------------------------------------------

    expected_sections = {
        (method, section)
        for method in METHOD_LABELS.values()
        for section in SECTION_LABELS.values()
    }

    combined = defaultdict(list)
    global_frame_offset = 0

    # -----------------------------------------------------
    # PROCESS EACH CHUNK
    # -----------------------------------------------------

    for path in files:

        chunk = chunk_number(path)

        log(f"Reading chunk {chunk}: {path}")

        tables = parse_energy_file(path)

        missing = expected_sections - set(tables)

        if missing:
            raise ValueError(
                f"\n{path} is missing sections:\n"
                f"{sorted(missing)}"
            )

        # -------------------------------------------------
        # CHECK FRAME COUNTS
        # -------------------------------------------------

        frame_counts = {key: len(df) for key, df in tables.items()}

        if len(set(frame_counts.values())) != 1:
            raise ValueError(
                f"\nDifferent sections contain different "
                f"numbers of frames in:\n"
                f"{path}\n\n"
                f"{frame_counts}"
            )

        n_frames = next(iter(frame_counts.values()))

        log(f"  {n_frames} frames found")

        # -------------------------------------------------
        # PROCESS EACH OF THE 8 TABLES
        # -------------------------------------------------

        for key, df in tables.items():

            df = df.copy()

            local_frame = pd.to_numeric(
                df["Frame #"],
                errors="raise"
            ).astype(int)

            df.insert(0, "Chunk", chunk)
            df.insert(1, "Local Frame #", local_frame)

            df["Frame #"] = local_frame + global_frame_offset

            column_order = [
                "Frame #",
                "Chunk",
                "Local Frame #",
            ] + [
                col
                for col in df.columns
                if col not in {"Frame #", "Chunk", "Local Frame #"}
            ]

            df = df[column_order]

            combined[key].append(df)

        global_frame_offset += n_frames

    # -----------------------------------------------------
    # WRITE OUTPUT FILES
    # -----------------------------------------------------

    log("\nCombining datasets...\n")

    for (method, section), dataframes in combined.items():

        final_df = pd.concat(dataframes, ignore_index=True)

        filename = f"{method}_{section}_energy.csv"

        out_file = output_path_base / filename

        final_df.to_csv(out_file, index=False)

        log(f"Created: {filename}")
        log(f"  Total frames: {len(final_df)}")
        log(
            f"  Frame range: "
            f"{final_df['Frame #'].min()} - "
            f"{final_df['Frame #'].max()}"
        )
        log()

    log("Finished!")
    log(f"\nOutput folder:\n{output_path_base.resolve()}\n")

    return output_path_base


# ---------------------------------------------------------
# COMMAND LINE INTERFACE
# ---------------------------------------------------------

def parse_args(argv=None):

    parser = argparse.ArgumentParser(
        description=(
            "Combine per-chunk MMPBSA CSV output into one CSV per "
            "method/section pair."
        ),
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )

    parser.add_argument(
        "-i", "--input-dir",
        default=".",
        help="Directory the glob pattern is applied to.",
    )

    parser.add_argument(
        "-p", "--pattern",
        default="work_*/wt_complex_val_chunk*.csv",
        help="Glob pattern (relative to --input-dir). Quote it in bash.",
    )

    parser.add_argument(
        "-o", "--output-dir",
        default="combined_energy_csvs",
        help=(
            "Output directory. Relative paths are created inside "
            "--input-dir; absolute paths are used as-is."
        ),
    )

    return parser.parse_args(argv)


def main(argv=None):

    args = parse_args(argv)

    try:
        combine_energy_chunks(
            input_dir=args.input_dir,
            pattern=args.pattern,
            output_dir=args.output_dir,
        )
    except (FileNotFoundError, ValueError, KeyError) as err:
        print(f"ERROR: {err}", file=sys.stderr, flush=True)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
