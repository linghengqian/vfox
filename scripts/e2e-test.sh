#!/usr/bin/env bash
# Throwaway probe for version-fox/vfox#337 (not part of vfox).
#
# Question: when a login shell starts with vfox directories already in PATH
# (nested shell, tmux pane, VS Code terminal), does vfox put them back in front
# of /usr/bin after macOS path_helper moved the system directories first?
#
# It lives on a scratch branch only: it replaces scripts/e2e-test.sh there and
# writes nothing inside the checkout.
set -u

VERSIONS=${PROBE_VERSIONS:-"0.5.4 1.0.8 1.0.10 1.0.13"}
STRIP_VERSIONS=${PROBE_STRIP_VERSIONS:-"1.0.10 1.0.13"}
CACHE=${PROBE_CACHE:-}

if [ "$(uname -s)" != Darwin ] && [ -z "${PROBE_ALLOW_LINUX:-}" ]; then
  echo "macOS-only probe, skipping on $(uname -s)"
  exit 0
fi

case "$(uname -s)" in
  Darwin) osname=macos ;;
  Linux) osname=linux ;;
  *) echo "unsupported kernel: $(uname -s)"; exit 0 ;;
esac
case "$(uname -m)" in
  x86_64) arch=x86_64 ;;
  arm64|aarch64) arch=aarch64 ;;
  *) echo "unsupported machine: $(uname -m)"; exit 0 ;;
esac
SUDO=sudo
[ "$(id -u)" = 0 ] && SUDO=
ZSH=/bin/zsh
[ -x "$ZSH" ] || ZSH=$(command -v zsh || true)
if [ -z "$ZSH" ]; then echo "zsh not found"; exit 0; fi
ME=$(id -un)

work=$(mktemp -d "${RUNNER_TEMP:-/tmp}/vfox337.XXXXXX")
harness=$work/harness
mkdir -p "$harness" "$work/plugins" "$work/out"
: > "$work/summary.txt"
made_node=0
H=""
TMUX_BIN=""
VFOX_BIN=/usr/local/bin/vfox

cleanup() {
  $SUDO rm -f /usr/local/bin/vfox
  if [ "$made_node" = 1 ]; then $SUDO rm -f /usr/local/bin/node; fi
}
trap cleanup EXIT

term_env() {
  env -i HOME="$H" USER="$ME" LOGNAME="$ME" SHELL="$ZSH" TERM=xterm-256color LANG=en_US.UTF-8 \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin HARNESS="$harness" TMUXBIN="$TMUX_BIN" "$@"
}

facts() {
  echo "::group::System facts"
  uname -a
  if command -v sw_vers >/dev/null 2>&1; then sw_vers; fi
  "$ZSH" --version
  echo "--- /etc/paths"; cat /etc/paths
  echo "--- /etc/paths.d"
  for f in /etc/paths.d/*; do if [ -f "$f" ]; then echo "[$f]"; cat "$f"; fi; done
  echo "--- /etc/zprofile"; cat /etc/zprofile 2>&1
  echo "--- executables that could shadow the vfox ones"
  for p in /usr/bin/java /usr/local/bin/node /opt/homebrew/bin/node /opt/homebrew/bin/java /usr/local/opt/node/bin/node; do
    if [ -e "$p" ]; then ls -l "$p"; fi
  done
  echo "--- /usr/bin/java -version"; /usr/bin/java -version 2>&1 | head -3
  echo "--- step PATH (before env -i)"; echo "$PATH" | tr ':' '\n' | head -40
  echo "::endgroup::"
}

pathhelper_check() {
  echo "::group::path_helper on a PATH that already holds a vfox directory"
  echo "input : /probe/.vfox/sdks/nodejs/bin:/usr/bin:/bin"
  env -i PATH=/probe/.vfox/sdks/nodejs/bin:/usr/bin:/bin /usr/libexec/path_helper -s \
    | sed -E 's/^PATH="(.*)"; export PATH;$/\1/' | tr ':' '\n' | nl -ba
  echo "::endgroup::"
}

fetch_vfox() {
  v=$1
  asset=vfox_${v}_${osname}_${arch}.tar.gz
  dir=$work/dl-$v
  mkdir -p "$dir"
  if [ -n "$CACHE" ] && [ -f "$CACHE/$v/$asset" ]; then
    cp "$CACHE/$v/$asset" "$CACHE/$v/checksums.txt" "$dir/"
  else
    base=https://github.com/version-fox/vfox/releases/download/v$v
    curl -fsSL --retry 5 --retry-all-errors -o "$dir/$asset" "$base/$asset" || return 1
    curl -fsSL --retry 5 --retry-all-errors -o "$dir/checksums.txt" "$base/checksums.txt" || return 1
  fi
  ( cd "$dir" && grep " $asset\$" checksums.txt > check.txt \
    && if command -v sha256sum >/dev/null 2>&1; then sha256sum -c check.txt; else shasum -a 256 -c check.txt; fi ) || return 1
  mkdir -p "$dir/x" && tar -xzf "$dir/$asset" -C "$dir/x" || return 1
  find "$dir/x" -type f -name vfox | head -1 > "$dir/bin.path"
}

install_vfox() {
  src=$(cat "$work/dl-$1/bin.path")
  $SUDO mkdir -p /usr/local/bin
  $SUDO cp "$src" /usr/local/bin/vfox
  $SUDO chmod 755 /usr/local/bin/vfox
  echo "installed: $(env -i /usr/local/bin/vfox --version 2>&1 | head -1)"
}

mkplugin() { # name version extra-lua-line
  d=$work/plugins/$1
  mkdir -p "$d"
  cat > "$d/main.lua" <<LUA_EOF
PLUGIN = {}
PLUGIN.name = "$1"
PLUGIN.version = "0.0.1"
PLUGIN.homepage = "https://example.invalid/$1"
PLUGIN.license = "Apache-2.0"
PLUGIN.description = "demo plugin for PATH-order probes"
PLUGIN.minRuntimeVersion = "0.2.2"
PLUGIN.notes = {}

function PLUGIN:Available(ctx)
    return {{version = "$2", note = ""}}
end

function PLUGIN:PreInstall(ctx)
    return {version = ctx.version, url = "https://example.invalid/$1.tar.gz"}
end

function PLUGIN:EnvKeys(ctx)
    local keys = {{key = "PATH", value = ctx.path .. "/bin"}}
    $3
    return keys
end
LUA_EOF
  ( cd "$d" && zip -qr "$work/$1.zip" main.lua )
}

mkinstall() { # sdk tool version
  d=$vhome/cache/$1/v-$3/$1-$3/bin
  mkdir -p "$d"
  printf '#!/bin/sh\necho "VFOX %s %s"\n' "$1" "$3" > "$d/$2"
  chmod +x "$d/$2"
}

write_harness() {
  cat > "$harness/report.zsh" <<'ZSH_EOF'
tag=${REPORT_TAG:-RESULT}
for t in node java vfox-demo-tool; do
  printf '%s %-14s %-72s %s\n' "$tag" "$t" "$(command -v $t)" "$($t 2>&1 | head -1)"
done
printf '%sHOOK shell_pid=%s __VFOX_PID=%s hook_registered=%s\n' "${tag%RESULT}" "$$" "${__VFOX_PID:-unset}" "${${precmd_functions[(r)_vfox_hook]:+yes}:-no}"
ZSH_EOF
  cat > "$harness/pathdump.zsh" <<'ZSH_EOF'
print -l ${(s.:.)PATH} | nl -ba
ZSH_EOF
  cat > "$harness/use.zsh" <<'ZSH_EOF'
vfox use -g nodejs@14.18.2 2>&1 | tail -1
echo "vfox current: $(vfox current nodejs 2>&1 | tail -1)"
printf 'RESULT %-14s %-72s %s\n' node "$(command -v node)" "$(node 2>&1 | head -1)"
ZSH_EOF
}

prepare_home() {
  H=$(mktemp -d "$work/home.XXXXXX")
  for p in nodejs java demo; do
    term_env "$VFOX_BIN" add --source "$work/$p.zip" "$p" > "$H/add-$p.log" 2>&1 \
      || { echo "WARN vfox add $p failed:"; sed 's/^/    /' "$H/add-$p.log"; }
  done
  vhome=$H/.vfox
  if [ -d "$H/.version-fox" ]; then vhome=$H/.version-fox; fi
  mkinstall nodejs node 14.18.2
  mkinstall java java 21.0.1
  mkinstall demo vfox-demo-tool 1.0.0
}

write_rc() { # rc-variant zprofile-variant
  case "$1" in
    minimal) printf '%s\n' "PROMPT=''; RPROMPT=''; PROMPT_EOL_MARK=''; unsetopt PROMPT_SP" \
      'eval "$(vfox activate zsh)"' > "$H/.zshrc" ;;
    strip) printf '%s\n' "PROMPT=''; RPROMPT=''; PROMPT_EOL_MARK=''; unsetopt PROMPT_SP" \
      'path=(${${path:#*/.vfox/*}:#*/.version-fox/*})' \
      'eval "$(vfox activate zsh)"' > "$H/.zshrc" ;;
  esac
  case "$2" in
    brew) printf '%s\n' \
      '[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"' \
      '[ -x /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)"' > "$H/.zprofile" ;;
    *) : > "$H/.zprofile" ;;
  esac
}

setup_globals() { # an earlier terminal session: the user picked global versions
  term_env "$ZSH" -l -i > "$H/setup.out" 2>&1 <<'EOT'
vfox use -g nodejs@14.18.2
vfox use -g java@21.0.1
vfox use -g demo@1.0.0
EOT
}

scenario() {
  case "$1" in
  fresh)
    term_env "$ZSH" -l -i 2>&1 <<'EOT'
echo "--- fresh login shell (Terminal.app / iTerm2 tab)"
source $HARNESS/report.zsh
source $HARNESS/pathdump.zsh
EOT
    ;;
  nested)
    term_env "$ZSH" -l -i 2>&1 <<'EOT'
echo "--- parent terminal"
REPORT_TAG=PARENT; source $HARNESS/report.zsh; unset REPORT_TAG
zsh -l -i <<'CHILD'
echo "--- nested login shell (code ., tmux, zsh -l ... started from the activated terminal)"
source $HARNESS/report.zsh
source $HARNESS/pathdump.zsh
CHILD
EOT
    ;;
  nested-use)
    term_env "$ZSH" -l -i 2>&1 <<'EOT'
zsh -l -i <<'CHILD'
echo "--- nested login shell: what the reporter typed"
source $HARNESS/report.zsh
source $HARNESS/use.zsh
source $HARNESS/pathdump.zsh
CHILD
EOT
    ;;
  nested-nonlogin)
    term_env "$ZSH" -l -i 2>&1 <<'EOT'
zsh -i <<'CHILD'
echo "--- nested NON-login shell (no /etc/zprofile, so no path_helper)"
source $HARNESS/report.zsh
CHILD
EOT
    ;;
  vscode)
    term_env VSCODE_RESOLVING_ENVIRONMENT=1 "$ZSH" -i -l -c env > "$H/resolved.env" 2> "$H/resolve.err"
    args=()
    while IFS= read -r line; do
      case "$line" in
        VSCODE_RESOLVING_ENVIRONMENT=*|_=*|SHLVL=*|PWD=*|OLDPWD=*) ;;
        [A-Za-z_]*=*) args+=("$line") ;;
      esac
    done < "$H/resolved.env"
    echo "RESOLVED $(grep '^PATH=' "$H/resolved.env" | tr ':' ' ' | sed "s|$H|<HOME>|g")"
    env -i "${args[@]}" "$ZSH" -l -i 2>&1 <<'EOT'
echo "--- integrated terminal on top of the shell env VS Code resolved at startup"
source $HARNESS/report.zsh
source $HARNESS/pathdump.zsh
EOT
    ;;
  tmux)
    if [ -z "$TMUX_BIN" ]; then echo "(tmux not available)"; return; fi
    term_env "$ZSH" -l -i 2>&1 <<'EOT'
echo "--- parent terminal"
REPORT_TAG=PARENT; source $HARNESS/report.zsh; unset REPORT_TAG
$TMUXBIN -f /dev/null new-session -d -s probe -x 200 -y 50
sleep 2
$TMUXBIN send-keys -t probe 'source $HARNESS/report.zsh > $HOME/tmux.out 2>&1; source $HARNESS/pathdump.zsh >> $HOME/tmux.out 2>&1' Enter
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  if [ -s $HOME/tmux.out ] && grep -q '^HOOK' $HOME/tmux.out && [ "$(wc -l < $HOME/tmux.out)" -gt 6 ]; then break; fi
  sleep 1
done
sleep 1
echo "--- tmux pane (login shell started by tmux)"
cat $HOME/tmux.out
$TMUXBIN kill-server
EOT
    ;;
  esac
}

classify() { # tool file
  line=$(grep "^RESULT $1 " "$2" | tail -1)
  path=$(echo "$line" | awk '{print $3}')
  case "$path" in
    */.vfox/*|*/.version-fox/*) echo VFOX ;;
    /*) echo "SYSTEM:$path" ;;
    *) echo none ;;
  esac
}

run_case() { # version rc-variant zprofile-variant scenario
  prepare_home
  write_rc "$2" "$3"
  setup_globals
  label="vfox=$1 zshrc=$2 zprofile=$3 scenario=$4"
  f=$work/out/$1-$2-$3-$4.log
  echo "::group::$label"
  scenario "$4" 2>&1 | grep -v '^heredoc>' | tee "$f"
  echo "::endgroup::"
  n=$(classify node "$f"); j=$(classify java "$f"); d=$(classify vfox-demo-tool "$f")
  h=$(grep '^HOOK' "$f" | tail -1 | sed -E 's/.*hook_registered=//')
  echo "SUMMARY $label node=$n java=$j demo=$d hook=${h:-n/a}" >> "$work/summary.txt"
}

in_list() { for x in $2; do [ "$x" = "$1" ] && return 0; done; return 1; }

# ---------------------------------------------------------------- main
write_harness
facts
pathhelper_check

mkplugin nodejs 14.18.2 ""
mkplugin java 21.0.1 'table.insert(keys, {key = "JAVA_HOME", value = ctx.path})'
mkplugin demo 1.0.0 ""

# a system-wide node, as the reporter had in /usr/local/bin (nodejs.org pkg, Intel Homebrew)
if [ ! -e /usr/local/bin/node ]; then
  $SUDO mkdir -p /usr/local/bin
  printf '#!/bin/sh\necho "SYSTEM node (/usr/local/bin/node)"\n' | $SUDO tee /usr/local/bin/node > /dev/null
  $SUDO chmod 755 /usr/local/bin/node
  made_node=1
fi

if command -v tmux >/dev/null 2>&1; then
  TMUX_BIN=$(command -v tmux)
elif command -v brew >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1 brew install tmux > "$work/brew-tmux.log" 2>&1 || tail -5 "$work/brew-tmux.log"
  TMUX_BIN=$(command -v tmux || true)
fi
echo "tmux: ${TMUX_BIN:-none}"

have_brew=0
if [ -x /opt/homebrew/bin/brew ] || [ -x /usr/local/bin/brew ]; then have_brew=1; fi

for v in $VERSIONS; do
  echo "::group::vfox $v"
  if ! fetch_vfox "$v"; then echo "SKIP $v: download or checksum failed"; echo "::endgroup::"; continue; fi
  install_vfox "$v"
  echo "::endgroup::"
  for s in fresh nested nested-use vscode nested-nonlogin tmux; do run_case "$v" minimal none "$s"; done
  if [ "$have_brew" = 1 ]; then
    for s in fresh nested vscode; do run_case "$v" minimal brew "$s"; done
  fi
  if in_list "$v" "$STRIP_VERSIONS"; then
    for s in nested vscode tmux; do run_case "$v" strip none "$s"; done
    if [ "$have_brew" = 1 ]; then for s in nested vscode; do run_case "$v" strip brew "$s"; done; fi
  fi
done

echo
echo "================ SUMMARY ($(uname -s) $(uname -m)) ================"
cat "$work/summary.txt"
exit 0
