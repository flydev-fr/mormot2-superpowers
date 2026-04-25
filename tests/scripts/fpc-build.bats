#!/usr/bin/env bats

setup() {
    PLUGIN_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${PLUGIN_ROOT}/scripts/fpc-build.sh"
    FAKE_MM="$(mktemp -d)"
    mkdir -p "${FAKE_MM}/src/core" "${FAKE_MM}/src/orm"
    FAKE_PROJ="$(mktemp -d)"
    printf 'program fake;\nbegin\nend.\n' > "${FAKE_PROJ}/fake.dpr"
}

teardown() {
    rm -rf "$FAKE_MM" "$FAKE_PROJ"
}

@test "exits 2 when MORMOT2_PATH is unset" {
    unset MORMOT2_PATH
    run "$SCRIPT" --project "${FAKE_PROJ}/fake.dpr"
    [ "$status" -eq 2 ]
    [[ "$output" == *"MORMOT2_PATH"* ]]
}

@test "exits 5 when project file is missing" {
    MORMOT2_PATH="$FAKE_MM" run "$SCRIPT" --project /no/such/file.dpr
    [ "$status" -eq 5 ]
}

@test "exits 6 when fpc is not on PATH" {
    PATH="/usr/bin:/bin" command -v fpc >/dev/null 2>&1 && skip "fpc is on PATH on this system"
    MORMOT2_PATH="$FAKE_MM" PATH="" run "$SCRIPT" --project "${FAKE_PROJ}/fake.dpr"
    [ "$status" -eq 6 ]
}

@test "emits BUILD_RESULT on every code path" {
    MORMOT2_PATH="$FAKE_MM" run "$SCRIPT" --project /no/such/file.dpr
    [[ "$output" == *"BUILD_RESULT exit="* ]]
}
