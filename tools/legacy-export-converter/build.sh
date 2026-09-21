#!/usr/bin/env bash
# Compiles the converter. No Maven/Gradle -- plain javac is enough for one class.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
javac -d build src/LegacyExportConverter.java
echo "Built build/LegacyExportConverter.class"
