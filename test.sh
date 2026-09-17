#!/bin/bash
set -eu

project_dir=$(cd "$(dirname "$0")" && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/macssh-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

export MACSSH_HOME="$test_root/.ssh"
export MACSSH_CONFIG="$MACSSH_HOME/config.d/macssh.conf"
export MACSSH_MAIN_CONFIG="$MACSSH_HOME/config"

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
printf '%s\n' '#!/bin/bash' 'printf "%s\n" "$*" > "$SSH_LOG"' 'exit "${SSH_EXIT:-0}"' > "$fake_bin/ssh"
chmod +x "$fake_bin/ssh"

test_ok=$("$project_dir/macssh" test transfer)
printf '%s' "$test_ok" | grep -Fq "Testing 'transfer'..." || fail 'test omitted progress'
printf '%s' "$test_ok" | grep -Fq "Authentication succeeded for 'transfer'." || fail 'test omitted success'
grep -Fq -- "-o BatchMode=yes -o ConnectTimeout=5 transfer true" "$SSH_LOG" || fail 'test did not pass ssh args'

SSH_EXIT=1
if test_err=$("$project_dir/macssh" test transfer 2>&1); then fail 'test succeeded when ssh failed'; fi
printf '%s' "$test_err" | grep -Fq "authentication failed for 'transfer'" || fail 'test omitted failure'

printf 'All tests passed.\n'
