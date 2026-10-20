#!/usr/bin/env bash
# vfox#335 probe, scenario G part 1: make java@<A> the global version (this writes the Windows registry).
# Usage: probe-global-1.sh <majorA>
exec 2>&1
set +e
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

A=${1:?majorA}

env_banner

section "activate, then vfox use -g java@$A"
eval "$(vfox activate bash)"
prompt
timeout 120 vfox use -g java@"$A"
prompt
show "G-1: after use -g $A in the same shell"

section "done"
