#!/usr/bin/env bats

setup() {
    PLUGIN_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${PLUGIN_ROOT}/scripts/sad-lookup.sh"
    FAKE_DOCS="$(mktemp -d)"
    # Build a fake SAD doc tree
    for n in 01 05 10 25; do
        printf '# Chapter %s\nbody body body\n' "$n" > "${FAKE_DOCS}/mORMot2-SAD-Chapter-${n}.md"
    done
}

teardown() {
    rm -rf "$FAKE_DOCS"
}

@test "exits 2 when MORMOT2_DOC_PATH is unset" {
    unset MORMOT2_DOC_PATH
    run "$SCRIPT" torm
    [ "$status" -eq 2 ]
    [[ "$output" == *"MORMOT2_DOC_PATH"* ]]
}

@test "exits 2 when MORMOT2_DOC_PATH does not exist" {
    MORMOT2_DOC_PATH="/no/such/path" run "$SCRIPT" torm
    [ "$status" -eq 2 ]
    [[ "$output" == *"not found"* ]]
}

@test "resolves topic to chapter number" {
    MORMOT2_DOC_PATH="$FAKE_DOCS" run "$SCRIPT" torm
    [ "$status" -eq 0 ]
    [[ "$output" == *"Chapter 05"* ]]
}

@test "accepts a chapter number directly" {
    MORMOT2_DOC_PATH="$FAKE_DOCS" run "$SCRIPT" 10
    [ "$status" -eq 0 ]
    [[ "$output" == *"Chapter 10"* ]]
}

@test "exits 3 when chapter file is missing" {
    MORMOT2_DOC_PATH="$FAKE_DOCS" run "$SCRIPT" 99
    [ "$status" -eq 3 ]
    [[ "$output" == *"not found"* ]]
}

@test "exits 4 when topic is unknown" {
    MORMOT2_DOC_PATH="$FAKE_DOCS" run "$SCRIPT" not-a-topic
    [ "$status" -eq 4 ]
    [[ "$output" == *"unknown topic"* ]]
}

@test "default excerpt limit is 200 lines" {
    # Pad chapter 5 with 500 lines
    yes line | head -n 500 >> "${FAKE_DOCS}/mORMot2-SAD-Chapter-05.md"
    MORMOT2_DOC_PATH="$FAKE_DOCS" run "$SCRIPT" torm
    [ "$status" -eq 0 ]
    line_count=$(printf '%s\n' "$output" | wc -l)
    # 1 header line + up to 200 body lines = 201
    [ "$line_count" -le 201 ]
}

@test "respects custom line limit" {
    yes line | head -n 500 >> "${FAKE_DOCS}/mORMot2-SAD-Chapter-05.md"
    MORMOT2_DOC_PATH="$FAKE_DOCS" run "$SCRIPT" torm 5
    [ "$status" -eq 0 ]
    line_count=$(printf '%s\n' "$output" | wc -l)
    # 1 header + 5 body = 6
    [ "$line_count" -le 6 ]
}

@test "exits 1 on non-numeric limit" {
    MORMOT2_DOC_PATH="$FAKE_DOCS" run "$SCRIPT" torm abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"line-limit must be a positive integer"* ]]
}

@test "exits 1 on zero limit" {
    MORMOT2_DOC_PATH="$FAKE_DOCS" run "$SCRIPT" torm 0
    [ "$status" -eq 1 ]
}

@test "exits 2 with clear message when chapter-index file missing" {
    INDEX="${PLUGIN_ROOT}/references/chapter-index.json"
    BACKUP="${INDEX}.bak"
    mv "$INDEX" "$BACKUP"
    MORMOT2_DOC_PATH="$FAKE_DOCS" run "$SCRIPT" torm
    mv "$BACKUP" "$INDEX"
    [ "$status" -eq 2 ]
    [[ "$output" == *"chapter-index lookup failed"* ]]
}
