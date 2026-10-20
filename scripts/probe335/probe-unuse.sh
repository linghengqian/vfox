#!/usr/bin/env bash
# vfox#335 probe: drop the global java choice again (used to reset state between scenarios; 1.x only).
exec 2>&1
set +e
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

eval "$("$VFOX" activate bash)"
prompt
$TIMEOUT 120 "$VFOX" unuse -g java
$TIMEOUT 60 "$VFOX" current java
section "done"
