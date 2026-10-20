#!/bin/bash
set -euo pipefail

# Usage:
# bash cleanup.sh /path/to/directory
# bash cleanup.sh /path/to/directory --delete
# It deletes .frc and .nc files cause they're fat af

DIR="${1:?Please provide a directory path}"
MODE="${2:---preview}"

# Check directory exists
if [[ ! -d "$DIR" ]]; then
    echo "Error: Directory does not exist: $DIR"
    exit 1
fi

# Convert to absolute path
DIR=$(realpath "$DIR")

# Prevent accidental deletion from root
if [[ "$DIR" == "/" ]]; then
    echo "Error: Cannot run on root directory."
    exit 1
fi

echo "Target directory: $DIR"

if [[ "$MODE" == "--preview" ]]; then
    echo "Files that would be deleted:"
    find "$DIR" -type f \( -name "*.frc" -o -name "*.nc" \) -print

elif [[ "$MODE" == "--delete" ]]; then
    echo "Deleting .frc and .nc files..."
    find "$DIR" -type f \( -name "*.frc" -o -name "*.nc" \) -print -delete
    echo "Cleanup complete!"

else
    echo "Error: Use --preview or --delete"
    exit 1
fi
