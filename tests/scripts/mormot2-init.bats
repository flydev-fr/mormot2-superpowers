#!/usr/bin/env bats

setup() {
    PLUGIN_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${PLUGIN_ROOT}/scripts/mormot2-init.sh"
    WORK="$(mktemp -d)"
    cd "$WORK"
}

teardown() {
    rm -rf "$WORK"
}

@test "exits 1 when --scaffold is passed (not yet implemented in Plan 3)" {
    run "$SCRIPT" --scaffold
    [ "$status" -eq 1 ]
    [[ "$output" == *"not yet implemented"* ]]
}

@test "creates .claude/mormot2.config.json with --mormot2-path" {
    MORMOT2="$(mktemp -d)"
    run "$SCRIPT" --mormot2-path "$MORMOT2"
    [ "$status" -eq 0 ]
    [ -f .claude/mormot2.config.json ]
    grep -q "$MORMOT2" .claude/mormot2.config.json
    rm -rf "$MORMOT2"
}

@test "exits 2 when --mormot2-path points nowhere" {
    run "$SCRIPT" --mormot2-path /no/such/path
    [ "$status" -eq 2 ]
    [[ "$output" == *"not found"* ]]
}

@test "refuses to overwrite existing config without --force" {
    mkdir -p .claude
    echo '{"mormot2_path":"/old"}' > .claude/mormot2.config.json
    MORMOT2="$(mktemp -d)"
    run "$SCRIPT" --mormot2-path "$MORMOT2"
    [ "$status" -eq 3 ]
    [[ "$output" == *"already exists"* ]]
    rm -rf "$MORMOT2"
}

@test "overwrites with --force" {
    mkdir -p .claude
    echo '{"mormot2_path":"/old"}' > .claude/mormot2.config.json
    MORMOT2="$(mktemp -d)"
    run "$SCRIPT" --force --mormot2-path "$MORMOT2"
    [ "$status" -eq 0 ]
    grep -q "$MORMOT2" .claude/mormot2.config.json
    ! grep -q "/old" .claude/mormot2.config.json
    rm -rf "$MORMOT2"
}

@test "infers mormot2_doc_path from mormot2_path/docs" {
    MORMOT2="$(mktemp -d)"
    mkdir -p "$MORMOT2/docs"
    run "$SCRIPT" --mormot2-path "$MORMOT2"
    [ "$status" -eq 0 ]
    grep -q "$MORMOT2/docs" .claude/mormot2.config.json
    rm -rf "$MORMOT2"
}
