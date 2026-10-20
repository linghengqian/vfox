#!/usr/bin/env bash
# vfox#335 probe: drop the global java choice again (used to reset state between scenarios).
exec 2>&1
set +e
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

eval "$(vfox activate bash)"
prompt
timeout 120 vfox unuse -g java
timeout 60 vfox current java
section "done"
