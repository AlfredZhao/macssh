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

printf 'All tests passed.\n'
