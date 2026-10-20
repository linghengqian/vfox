#!/usr/bin/env bash
# vfox#335 probe, scenario X: no global java at all, but one unrelated vfox directory sits in the Windows PATH
# (what `vfox use -g` of any other SDK leaves behind). Then a session `use` of java.
# Usage: probe-fakedir.sh <majorB>
exec 2>&1
set +e
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

B=${1:?majorB}

env_banner
echo "inherited JAVA_HOME=[$JAVA_HOME]"
winpath_diag
echo "global java per vfox: $(timeout 60 vfox current java 2>&1 | head -2 | tr '\n' ' ')"

section "activate (what .bashrc does)"
eval "$(vfox activate bash)"
prompt
show "X0: new shell, no global java, a vfox dir in the inherited PATH"

section "vfox use java@$B (session) + prompt"
timeout 120 vfox use java@"$B"
prompt
show "X1: session $B"

section "done"
