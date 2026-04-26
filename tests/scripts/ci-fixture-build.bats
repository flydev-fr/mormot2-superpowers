#!/usr/bin/env bats

setup() {
    PLUGIN_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${PLUGIN_ROOT}/scripts/ci-fixture-build.sh"
    WORK="$(mktemp -d)"
    cd "$WORK"
    mkdir -p .claude
    cat > .claude/mormot2.config.json <<EOF
{
  "mormot2_path": "REPLACE_WITH_MORMOT2_PATH",
  "mormot2_doc_path": "REPLACE_WITH_MORMOT2_PATH/docs",
  "compiler": "auto"
}
EOF
}

teardown() {
    rm -rf "$WORK"
}

@test "exits 1 when MORMOT2_PATH is unset" {
    unset MORMOT2_PATH
    run "$SCRIPT" --fixture "$WORK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"MORMOT2_PATH"* ]]
}

@test "exits 1 when fixture dir does not exist" {
    MORMOT2_PATH="/some/path" run "$SCRIPT" --fixture /no/such/fixture
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "rewrites .claude/mormot2.config.json with real MORMOT2_PATH" {
    FAKE_MM="$(mktemp -d)"
    MORMOT2_PATH="$FAKE_MM" run "$SCRIPT" --fixture "$WORK" --dry-run
    [ "$status" -eq 0 ]
    grep -q "$FAKE_MM" "$WORK/.claude/mormot2.config.json"
    ! grep -q "REPLACE_WITH_MORMOT2_PATH" "$WORK/.claude/mormot2.config.json"
    rm -rf "$FAKE_MM"
}

@test "exits 1 with --dry-run if fixture has no .claude/mormot2.config.json" {
    rm -rf "$WORK/.claude"
    FAKE_MM="$(mktemp -d)"
    MORMOT2_PATH="$FAKE_MM" run "$SCRIPT" --fixture "$WORK" --dry-run
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]]
    rm -rf "$FAKE_MM"
}
