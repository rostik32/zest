#!/bin/zsh -f
# Measures what zest costs you: shell startup, the work the shell does on every key
# press, how long the shell waits for an answer to Tab/↑/↓, and the app's memory and
# CPU. Zest.app must be running.
#
# Usage: zsh scripts/bench.zsh
zmodload zsh/datetime zsh/net/socket

root=${0:A:h:h}
script=$root/shell/zest.zsh
socket=${ZEST_SOCKET:-"$HOME/Library/Application Support/zest/zest.sock"}

# Prints the median and the 95th percentile of the numbers on stdin.
stats() { sort -n | awk '{ a[NR] = $1 } END { printf "median %.2f, p95 %.2f", a[int((NR + 1) / 2)], a[int(NR * 0.95 + 0.5)] }' }

# --- Runs inside an interactive zsh with zest loaded (see below) -------------------
if [[ $1 == --keys ]]; then
  source "$script"
  _zest_connect || { print "cannot connect to $socket"; exit 1 }
  # Typing these one after another changes the line on every step, like real typing.
  lines=(g gi git "git " "git c" "git ch" "git che" "git chec" d do doc dock docke docker "docker "
         "docker r" "docker ru" n np npm "npm " "npm r" "npm ru" "npm run" "npm run " l ls "ls " "ls -"
         "ls -l" c cd "cd " "cd S" "cd So" k ku kub kubectl "kubectl " "kubectl g" "kubectl get ")
  redraw=() ask=()
  for round in {1..10}; do
    for BUFFER in $lines; do
      CURSOR=${#BUFFER}
      t=$EPOCHREALTIME; _zest_redraw; redraw+=$(( (EPOCHREALTIME - t) * 1e6 ))
    done
  done
  for round in {1..5}; do
    for BUFFER in $lines; do
      CURSOR=${#BUFFER}
      t=$EPOCHREALTIME; _zest_ask down; ask+=$(( (EPOCHREALTIME - t) * 1e3 ))
    done
  done
  print -r -- "key-redraw $(print -l $redraw | stats)"
  print -r -- "key-ask $(print -l $ask | stats)"
  exit 0
fi

[[ -S $socket ]] || { print "Zest.app is not running (no socket at $socket)"; exit 1 }
pid=$(pgrep -f "Zest.app/Contents/MacOS/Zest" | head -1)

print "zest $(sed -n 's/.*current = "\(.*\)".*/\1/p' "$root/Sources/ZestCore/Version.swift"), $(sw_vers -productName) $(sw_vers -productVersion), $(sysctl -n machdep.cpu.brand_string)"
print

# 1. Shell startup: an interactive zsh with and without the zest script.
without=() with=()
for i in {1..40}; do
  t=$EPOCHREALTIME; zsh -f -i -c exit </dev/null >/dev/null 2>&1; without+=$(( (EPOCHREALTIME - t) * 1e3 ))
  t=$EPOCHREALTIME; zsh -f -i -c "source '$script'; exit" </dev/null >/dev/null 2>&1; with+=$(( (EPOCHREALTIME - t) * 1e3 ))
done
base=$(print -l $without | sort -n | awk '{ a[NR] = $1 } END { print a[int((NR + 1) / 2)] }')
loaded=$(print -l $with | sort -n | awk '{ a[NR] = $1 } END { print a[int((NR + 1) / 2)] }')
printf "Shell startup:   +%.1f ms (zsh -f: %.1f ms, with zest: %.1f ms; medians of 40)\n" $(( loaded - base )) $base $loaded

# 2 and 3. Per key: the shell's own work, and the wait for an answer to a key.
# The shell runs with a terminal name no app has, so no popup appears while it runs.
out=$(__CFBundleIdentifier=zest-bench TERM_PROGRAM=zest-bench HISTFILE=/dev/null ZEST_GHOST_TEXT=1 \
  ZEST_SOCKET=$socket zsh -f -i "$0" --keys </dev/null 2>/dev/null)
print -r -- "Each key press:  $(print -r -- $out | sed -n 's/^key-redraw //p') µs in the shell (sends the line, no waiting)"
print -r -- "Tab, ↑, ↓:       $(print -r -- $out | sed -n 's/^key-ask //p') ms until the shell has the app's answer"

# 4. The app: memory and CPU while idle.
if [[ -n $pid ]]; then
  cputime() { ps -o time= -p $pid | awk -F'[:.]' '{ print ($1 * 60 + $2) + $3 / 100 }' }
  a=$(cputime); sleep 10; b=$(cputime)
  printf "App, idle:       %.1f%% of one core over 10 s\n" $(( (b - a) * 10 ))
  print -r -- "App memory:      $(footprint -p $pid 2>/dev/null | awk '/phys_footprint:/ { print $2, $3; exit }') (physical footprint)"
fi
