# What counts as a runtime failure in an engine log (ERE), for every suite
# (vf_forbid_runtime_failures) and the release smoke test.  Sourced; defines
# only this variable.
#   - a Wasm trap, fault or error: "core Wasm export trapped: ...",
#     "Core Wasm module X was deregistered due to fault: ...", "wasm trap"
#   - a callin the engine skipped, or a module over its engine-call budget
#   - a Rust panic ("guest panic: ...", "panicked at") or a borrow conflict
#     ("... already borrowed", logged before the panic)
#   - a Lua error in a callin, a crash, or a sanitizer report
# shellcheck disable=SC2034
RUNTIME_FAILURE_PATTERN='[Ww]asm.*(trap|error|Error|fault)|Core Wasm callin .* skipped|Core Wasm module .* made more than|panic|already borrowed|CallIn.*(error|Error)|RunCallInTraceback|Error: \[Lua|\[Lua(Rules|UI|Gaia)\] Error|Segmentation fault|\[Fatal\]|Fatal:|AddressSanitizer'
