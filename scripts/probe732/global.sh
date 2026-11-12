#!/usr/bin/env bash
# vfox#732 probe, part 1: make java@<A> the global version in a fresh bash.
# Usage: global.sh <majorA>
exec 2>&1
set +e
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

A=${1:?majorA}

vfox --version
echo "vfox config path.mode before: $(vfox config path.mode 2>&1 | tr -d '\r')"

section "activate, then vfox use -g java@$A"
eval "$(vfox activate bash)"
prompt
timeout 180 vfox use -g java@"$A"
echo "vfox use -g exit: $?"
prompt
show_java "after use -g $A in the same shell"

section "done"
