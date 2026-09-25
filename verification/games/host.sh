#!/usr/bin/env bash
# Host unit tests: the shared springcabal crates and every game's host-built
# crates (`shared`, Hunted's `ai`).  The game modules themselves build only
# for wasm32, so logic worth testing on the host lives in those crates.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

HOST_TARGET=$(rustc -vV | sed -n 's/^host: //p')
HOST_CRATES=(shared ai)
FAILURES=0
PASSED=0

# host_cargo_test DIR TARGET_NAME [cargo test args...]
host_cargo_test() {
    local dir=$1 name=$2 output passed
    shift 2
    output=$(cd "$dir" && flock /tmp/springcabal-build.lock cargo test --locked "$@" \
        --target "$HOST_TARGET" --target-dir "$BUILD_CACHE/host-$name" 2>&1) || {
        printf '%s\n' "$output" | tail -30
        printf '  FAIL     %s\n' "$name"
        FAILURES=$((FAILURES + 1))
        return 0
    }
    passed=$(grep -oE 'test result: ok\. [0-9]+ passed' <<<"$output" | awk '{ sum += $4 } END { print sum + 0 }')
    PASSED=$((PASSED + passed))
    printf '  PASS     %s (%s tests)\n' "$name" "$passed"
}

host_tests() {
    local game dir member package
    vf_note 'springcabal-rs'
    host_cargo_test "$PROJECT_ROOT/springcabal-rs" springcabal-rs --workspace
    for dir in "$GAMES_DIR"/*-wasm.sdd/wasm-src; do
        game=$(basename "$(dirname "$dir")")
        vf_note "$game"
        for member in "${HOST_CRATES[@]}"; do
            [[ -f $dir/$member/Cargo.toml ]] || continue
            package=$(sed -n 's/^name *= *"\(.*\)"/\1/p' "$dir/$member/Cargo.toml" | head -1)
            host_cargo_test "$dir" "$package" -p "$package"
        done
    done
    echo
    printf 'host tests passed: %s\n' "$PASSED"
    [[ $FAILURES -eq 0 ]] || vf_die "$FAILURES host test crate(s) failed"
    echo '>>> Host tests passed <<<'
}

case "${1:-}" in
    tests) host_tests ;;
    *) vf_die 'usage: host.sh tests' ;;
esac
