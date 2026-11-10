#!/bin/bash
set -eu

project_dir=$(cd "$(dirname "$0")" && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/macssh-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

export MACSSH_HOME="$test_root/.ssh"
export MACSSH_CONFIG="$MACSSH_HOME/config.d/macssh.conf"
export MACSSH_MAIN_CONFIG="$MACSSH_HOME/config"
export MACSSH_LOG_DIR="$test_root/ssh-logs"
export MACSSH_TUNNEL_DIR="$test_root/tunnels"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_contains() { grep -Fq "$2" "$1" || fail "$1 does not contain: $2"; }

"$project_dir/macssh" add prod --host 10.0.0.8 --user ubuntu --port 2222 --key ~/.ssh/prod.pem --tags production --yes >/dev/null
assert_contains "$MACSSH_CONFIG" 'Host prod'
assert_contains "$MACSSH_CONFIG" 'IgnoreUnknown UseKeychain'
assert_contains "$MACSSH_CONFIG" 'HostName "10.0.0.8"'
assert_contains "$MACSSH_CONFIG" 'Port 2222'
assert_contains "$MACSSH_CONFIG" 'IdentityFile "/home/'

list_output=$("$project_dir/macssh" list)
printf '%s' "$list_output" | grep -Fq prod || fail 'list omitted prod'
printf '%s' "$list_output" | grep -Fq production || fail 'list omitted tags'

"$project_dir/macssh" add prod --host example.com --user deploy --yes >/dev/null
[ "$(grep -c '^Host prod$' "$MACSSH_CONFIG")" -eq 1 ] || fail 'update duplicated host'
assert_contains "$MACSSH_CONFIG" 'HostName "example.com"'

printf 'new.example.com\nadmin\n2200\n\n\nupdated\n' | "$project_dir/macssh" edit prod >/dev/null
assert_contains "$MACSSH_CONFIG" 'HostName "new.example.com"'
assert_contains "$MACSSH_CONFIG" 'User "admin"'
assert_contains "$MACSSH_CONFIG" 'Port 2200'
assert_contains "$MACSSH_CONFIG" '# Tags: updated'

printf 'y\n' | "$project_dir/macssh" remove prod >/dev/null
if grep -Fq 'Host prod' "$MACSSH_CONFIG"; then fail 'remove left host behind'; fi

if "$project_dir/macssh" add 'bad name' --host example.com >/dev/null 2>&1; then fail 'invalid name accepted'; fi
if "$project_dir/macssh" add bad-port --host example.com --port 70000 >/dev/null 2>&1; then fail 'invalid port accepted'; fi

help_output=$("$project_dir/macssh" help)
printf '%s' "$help_output" | grep -Fq 'macssh put' || fail 'help omitted put'
printf '%s' "$help_output" | grep -Fq 'macssh get' || fail 'help omitted get'
printf '%s' "$help_output" | grep -Fq -- '--log' || fail 'help omitted --log'
printf '%s' "$help_output" | grep -Fq 'macssh tunnel' || fail 'help omitted tunnel'

"$project_dir/macssh" add transfer --host example.com --user ubuntu --yes >/dev/null

if "$project_dir/macssh" put >/dev/null 2>&1; then fail 'put without args succeeded'; fi
if "$project_dir/macssh" put transfer >/dev/null 2>&1; then fail 'put without local path succeeded'; fi
if "$project_dir/macssh" put missing-host /tmp >/dev/null 2>&1; then fail 'put unknown host succeeded'; fi
if "$project_dir/macssh" put transfer "$test_root/no-such-file" >/dev/null 2>&1; then fail 'put missing local path succeeded'; fi
if "$project_dir/macssh" get >/dev/null 2>&1; then fail 'get without args succeeded'; fi
if "$project_dir/macssh" get transfer >/dev/null 2>&1; then fail 'get without remote path succeeded'; fi
if "$project_dir/macssh" get missing-host /tmp >/dev/null 2>&1; then fail 'get unknown host succeeded'; fi

fake_bin="$test_root/bin"
mkdir -p "$fake_bin"
printf '%s\n' '#!/bin/bash' 'printf "%s\n" "$*" > "$SCP_LOG"' > "$fake_bin/scp"
chmod +x "$fake_bin/scp"
export PATH="$fake_bin:$PATH"
export SCP_LOG="$test_root/scp.log"

src="$test_root/hello.txt"
printf 'hi\n' > "$src"
"$project_dir/macssh" put transfer "$src" /tmp/hello.txt >/dev/null
grep -Fq "$src transfer:/tmp/hello.txt" "$SCP_LOG" || fail 'put did not pass scp args'

mkdir -p "$test_root/folder"
"$project_dir/macssh" put transfer "$test_root/folder" /opt/app >/dev/null
grep -Fq -- "-r $test_root/folder transfer:/opt/app" "$SCP_LOG" || fail 'put did not recurse directory'

"$project_dir/macssh" get transfer /var/log/app.log ./out.log >/dev/null
grep -Fq -- "-r transfer:/var/log/app.log ./out.log" "$SCP_LOG" || fail 'get did not pass scp args'

if "$project_dir/macssh" test >/dev/null 2>&1; then fail 'test without args succeeded'; fi
if "$project_dir/macssh" test missing-host >/dev/null 2>&1; then fail 'test unknown host succeeded'; fi

export SSH_LOG="$test_root/ssh.log"
export SSH_EXIT=0
cat > "$fake_bin/ssh" << 'SSH'
#!/bin/bash
printf '%s\n' "$*" > "$SSH_LOG"
socket=""
operation=""
forward=""
while [ $# -gt 0 ]; do
  case "$1" in
    -S) socket="$2"; shift 2 ;;
    -O) operation="$2"; shift 2 ;;
    -L) forward="$2"; shift 2 ;;
    *) shift ;;
  esac
done
case "$operation" in
  check) [ -n "$socket" ] && [ -e "$socket" ]; exit ;;
  exit) [ -n "$socket" ] && rm -f "$socket"; exit "${SSH_EXIT:-0}" ;;
esac
if [ -n "$forward" ] && [ -n "$socket" ] && [ "${SSH_EXIT:-0}" -eq 0 ]; then
  mkdir -p "$(dirname "$socket")"
  : > "$socket"
fi
exit "${SSH_EXIT:-0}"
SSH
chmod +x "$fake_bin/ssh"

test_ok=$("$project_dir/macssh" test transfer)
printf '%s' "$test_ok" | grep -Fq "Testing 'transfer'..." || fail 'test omitted progress'
printf '%s' "$test_ok" | grep -Fq "Authentication succeeded for 'transfer'." || fail 'test omitted success'
grep -Fq -- "-o BatchMode=yes -o ConnectTimeout=5 transfer true" "$SSH_LOG" || fail 'test did not pass ssh args'

SSH_EXIT=1
if test_err=$("$project_dir/macssh" test transfer 2>&1); then fail 'test succeeded when ssh failed'; fi
printf '%s' "$test_err" | grep -Fq "authentication failed for 'transfer'" || fail 'test omitted failure'

SSH_EXIT=0
"$project_dir/macssh" connect transfer
grep -Fq 'transfer' "$SSH_LOG" || fail 'connect did not pass ssh host'
if ls "$MACSSH_LOG_DIR"/*.log >/dev/null 2>&1; then fail 'connect without --log wrote a log'; fi

if "$project_dir/macssh" connect transfer --verbose >/dev/null 2>&1; then fail 'connect unknown option succeeded'; fi
if "$project_dir/macssh" connect transfer extra >/dev/null 2>&1; then fail 'connect extra arg succeeded'; fi

tunnel_output=$("$project_dir/macssh" tunnel transfer 5902)
printf '%s' "$tunnel_output" | grep -Fq "127.0.0.1:5902 -> 127.0.0.1:5902" || fail 'tunnel omitted default mapping'
grep -Fq -- '-M -S ' "$SSH_LOG" || fail 'tunnel did not create a control master'
grep -Fq -- '-f -N -T' "$SSH_LOG" || fail 'tunnel did not run in background mode'
grep -Fq -- '-o ExitOnForwardFailure=yes' "$SSH_LOG" || fail 'tunnel omitted forward failure checking'
grep -Fq -- '-L 127.0.0.1:5902:127.0.0.1:5902 transfer' "$SSH_LOG" || fail 'tunnel passed the wrong default mapping'

tunnel_list=$("$project_dir/macssh" tunnel list)
printf '%s' "$tunnel_list" | grep -Fq transfer || fail 'tunnel list omitted host'
printf '%s' "$tunnel_list" | grep -Fq '127.0.0.1:5902' || fail 'tunnel list omitted port'

custom_output=$("$project_dir/macssh" port transfer 5903 --local 15903 --compress)
printf '%s' "$custom_output" | grep -Fq '127.0.0.1:15903 -> 127.0.0.1:5903' || fail 'tunnel omitted custom mapping'
grep -Fq -- '-f -N -T -C' "$SSH_LOG" || fail 'tunnel --compress omitted -C'
grep -Fq -- '-L 127.0.0.1:15903:127.0.0.1:5903 transfer' "$SSH_LOG" || fail 'tunnel passed the wrong custom mapping'

if "$project_dir/macssh" tunnel transfer 6000 --local 15903 >/dev/null 2>&1; then fail 'tunnel reused a managed local port'; fi
if "$project_dir/macssh" tunnel missing-host 5904 >/dev/null 2>&1; then fail 'tunnel accepted an unknown host'; fi
if "$project_dir/macssh" tunnel transfer 70000 >/dev/null 2>&1; then fail 'tunnel accepted an invalid remote port'; fi
if "$project_dir/macssh" tunnel transfer 5904 --local 0 >/dev/null 2>&1; then fail 'tunnel accepted an invalid local port'; fi

stop_output=$("$project_dir/macssh" tunnel kill transfer 15903)
printf '%s' "$stop_output" | grep -Fq "Stopped tunnel 'transfer'" || fail 'tunnel stop omitted confirmation'
if "$project_dir/macssh" tunnel stop transfer 15903 >/dev/null 2>&1; then fail 'tunnel stopped a missing mapping'; fi

# An SSH process that disappears outside macssh should be removed from list.
rm -f "$MACSSH_TUNNEL_DIR/transfer-5902.sock"
stale_list=$("$project_dir/macssh" tunnel list)
printf '%s' "$stale_list" | grep -Fq 'No active tunnels.' || fail 'tunnel list kept stale mapping'
[ ! -e "$MACSSH_TUNNEL_DIR/transfer-5902.state" ] || fail 'tunnel list kept stale state file'

SSH_EXIT=1
if "$project_dir/macssh" tunnel transfer 5907 >/dev/null 2>&1; then fail 'tunnel succeeded when ssh failed'; fi
[ ! -e "$MACSSH_TUNNEL_DIR/transfer-5907.state" ] || fail 'failed tunnel left a state file'
[ ! -e "$MACSSH_TUNNEL_DIR/transfer-5907.sock" ] || fail 'failed tunnel left a control file'
SSH_EXIT=0

"$project_dir/macssh" tunnel start transfer 5905 >/dev/null
"$project_dir/macssh" tunnel transfer 5906 >/dev/null
stop_all_output=$("$project_dir/macssh" tunnel stop --all)
printf '%s' "$stop_all_output" | grep -Fq '5905' || fail 'tunnel stop --all omitted first mapping'
printf '%s' "$stop_all_output" | grep -Fq '5906' || fail 'tunnel stop --all omitted second mapping'
empty_list=$("$project_dir/macssh" tunnel list)
printf '%s' "$empty_list" | grep -Fq 'No active tunnels.' || fail 'tunnel stop --all left mappings'

cat > "$fake_bin/script" << 'SCRIPT'
#!/bin/bash
file=""
extra=""
cmd=()
while [ $# -gt 0 ]; do
  case "$1" in
    -q|-a|-k|-e|--quiet|--append|--return|--flush) shift ;;
    -c|--command) extra="$2"; shift 2 ;;
    *)
      if [ -z "$file" ]; then
        file="$1"
      else
        cmd+=("$1")
      fi
      shift
      ;;
  esac
done
[ -n "$file" ] || exit 1
if [ -n "${SCRIPT_PAYLOAD:-}" ]; then
  printf '%s' "$SCRIPT_PAYLOAD" > "$file"
else
  printf 'hello\r\n\033[32mgreen\033[0m\nbell\a\nq ⠹0\rq ⠸0\rq ⠼0\n\033[0 qABC\rXYZ\n' > "$file"
fi
if [ -n "$extra" ]; then
  case "$extra" in
    stty\ *) extra=${extra#*; } ;;
  esac
  eval "$extra"
elif [ "${#cmd[@]}" -gt 0 ]; then
  "${cmd[@]}"
fi
SCRIPT
chmod +x "$fake_bin/script"

log_output=$("$project_dir/macssh" connect transfer --log)
printf '%s' "$log_output" | grep -Fq "Logging to '" || fail 'connect --log omitted logging message'
printf '%s' "$log_output" | grep -Fq "Saved session log to '" || fail 'connect --log omitted saved message'
log_file=$(printf '%s\n' "$log_output" | sed -n "s/.*Saved session log to '\\(.*\\)'/\\1/p")
[ -n "$log_file" ] || fail 'connect --log did not print log path'
[ -f "$log_file" ] || fail 'connect --log did not create log file'
grep -Fq 'hello' "$log_file" || fail 'log omitted hello'
grep -Fq 'green' "$log_file" || fail 'log omitted stripped color text'
grep -Fq 'q ⠼0' "$log_file" || fail 'log omitted final spinner frame'
grep -Fq 'XYZ' "$log_file" || fail 'log omitted overwritten status text'
if grep -Fq '⠹' "$log_file"; then fail 'log kept intermediate spinner frame'; fi
if grep -Fq '⠸' "$log_file"; then fail 'log kept intermediate spinner frame'; fi
if grep -Fq 'ABC' "$log_file"; then fail 'log kept overwritten status text'; fi
if grep -q $'\r' "$log_file"; then fail 'log still contains CR'; fi
if grep -q $'\033' "$log_file"; then fail 'log still contains escape'; fi
if grep -q $'\a' "$log_file"; then fail 'log still contains bell'; fi
grep -Fq 'transfer' "$SSH_LOG" || fail 'connect --log did not pass ssh host'

"$project_dir/macssh" connect --log transfer >/dev/null
log_count=$(find "$MACSSH_LOG_DIR" -name 'transfer-*.log' | wc -l)
[ "$log_count" -eq 2 ] || fail "expected 2 session logs, got $log_count"

SCRIPT_PAYLOAD=$(printf '\033[2J\033[Hloading-banner\n\033[2J\033[Hfinal-banner\n\n› hi\n\n• Hi — what would you like to work on?\n')
export SCRIPT_PAYLOAD
tui_output=$("$project_dir/macssh" connect transfer --log)
tui_log=$(printf '%s\n' "$tui_output" | sed -n "s/.*Saved session log to '\\(.*\\)'/\\1/p")
[ -n "$tui_log" ] || fail 'TUI --log did not print log path'
grep -Fq 'final-banner' "$tui_log" || fail 'TUI log omitted redrawn frame'
grep -Fq '› hi' "$tui_log" || fail 'TUI log omitted prompt after redraw'
grep -Fq 'Hi — what would you like to work on?' "$tui_log" || fail 'TUI log omitted assistant text'
if grep -Fq 'loading-banner' "$tui_log"; then fail 'TUI log kept replaced frame'; fi
unset SCRIPT_PAYLOAD

# xterm/Codex private CSI prefixes such as >4 and <1 must not abort Perl
# numeric conversion, and post-TUI shell output must still be logged.
SCRIPT_PAYLOAD=$(printf '\033[?1049h\033[2J\033[Hcodex-tui\n\033[>4;1m\033[<1;2m\033[?1049lclosed.\nnew-os-command\n')
export SCRIPT_PAYLOAD
csi_output=$("$project_dir/macssh" connect transfer --log 2>"$test_root/csi.err")
csi_log=$(printf '%s\n' "$csi_output" | sed -n "s/.*Saved session log to '\\(.*\\)'/\\1/p")
[ -n "$csi_log" ] || fail 'CSI --log did not print log path'
if grep -Fq "isn't numeric" "$test_root/csi.err"; then fail 'CSI prefixes caused Perl numeric warnings'; fi
if grep -Fq 'Argument' "$test_root/csi.err"; then fail 'CSI prefixes caused Perl argument warnings'; fi
grep -Fq 'closed.' "$csi_log" || fail 'CSI log omitted post-TUI closed text'
grep -Fq 'new-os-command' "$csi_log" || fail 'CSI log omitted post-TUI shell output'
unset SCRIPT_PAYLOAD

printf 'All tests passed.\n'
