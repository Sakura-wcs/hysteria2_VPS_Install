#!/usr/bin/env bash

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/test-helper.sh"
source "$ROOT/scripts/node-info.sh"

link="$(generate_node_link 'example.com' 443 'a b@/' 'o&b' 'sni.example' false)"
assert_contains "$link" 'a%20b%40%2F@example.com:443'
assert_contains "$link" 'insecure=0'
assert_contains "$link" 'obfs-password=o%26b'

client_config="$(generate_client_config 'example.com' 443 'a: b' 'x"y' 'sni.example' false)"
assert_contains "$client_config" 'auth: "a: b"'
assert_contains "$client_config" 'password: "x\"y"'
assert_contains "$client_config" 'insecure: false'

singbox_config="$(generate_singbox_config 'example.com' 443 'a"b' 'x\\y' 'sni.example' false)"
assert_contains "$singbox_config" '"password": "a\"b"'
assert_contains "$singbox_config" '"password": "x\\\\y"'
assert_contains "$singbox_config" '"insecure": false'

finish_tests
