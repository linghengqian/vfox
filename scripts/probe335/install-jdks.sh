#!/usr/bin/env bash
# vfox#335 probe: register the java plugin zip and install two Temurin JDKs (11 and 21).
# Usage: install-jdks.sh <Windows path of the plugin zip>
exec 2>&1
set -o pipefail
zip=${1:?plugin zip (Windows path)}

vfox --version
vfox add --source "$zip" java 2>&1 | tr '\r' '\n' | tail -3
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "vfox add failed"; exit 1; }

for v in 11 21; do
  timeout 900 vfox install java@"$v"-tem 2>&1 | tr '\r' '\n' | tail -3
  [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "vfox install java@$v-tem failed"; exit 1; }
done
vfox list java
