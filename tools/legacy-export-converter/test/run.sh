#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh
javac -cp build -d build src/LegacyExportConverter.java test/LegacyExportConverterTest.java
java -cp build LegacyExportConverterTest
