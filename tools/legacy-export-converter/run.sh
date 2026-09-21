#!/usr/bin/env bash
# Usage: ./run.sh <input.txt> <output.csv>
# Example: ./run.sh sample/input.txt /tmp/converted.csv
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
java -cp build LegacyExportConverter "$1" "$2"
