#!/usr/bin/env bash
# benchmark.sh — Compare speed & token overhead: MCP vs CLI+state vs CLI+stateless
#
# Usage:
#   bash tool/benchmark.sh                          # starts fresh app per phase
#   bash tool/benchmark.sh ws://127.0.0.1:XXXX/ws   # uses an already-running app
#
# Environment variables:
#   ITERATIONS=10       Number of times to repeat each operation (default: 10)
#   FLUTTER_DEVICE=...  Device to run on (default: linux on Linux, macos on macOS)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI_SRC="$REPO_ROOT/packages/marionette_cli/bin/marionette.dart"
CLI_BIN="$REPO_ROOT/tool/marionette"
MCP_SRC="$REPO_ROOT/packages/marionette_mcp/bin/marionette_mcp.dart"
EXAMPLE_DIR="$REPO_ROOT/example"
SCREENSHOT_DIR="$(mktemp -d)"
LOG_DIR="$REPO_ROOT/tool/benchmark_logs"

ITERATIONS=${ITERATIONS:-10}
SHARED_URI="${1:-}"

# Default to desktop device for the current OS
if [[ -z "${FLUTTER_DEVICE:-}" ]]; then
  case "$(uname -s)" in
    Linux*)  FLUTTER_DEVICE="linux" ;;
    Darwin*) FLUTTER_DEVICE="macos" ;;
  esac
fi
DEVICE_FLAG=()
if [[ -n "${FLUTTER_DEVICE:-}" ]]; then
  DEVICE_FLAG=(-d "$FLUTTER_DEVICE")
fi

# Create log directories
rm -rf "$LOG_DIR"
mkdir -p "$LOG_DIR/cli_state" "$LOG_DIR/cli_uri" "$LOG_DIR/mcp"

# Cleanup on exit
FLUTTER_PID=""
MCP_PID=""
cleanup() {
  if [[ -n "$MCP_PID" ]]; then
    kill "$MCP_PID" 2>/dev/null || true
    wait "$MCP_PID" 2>/dev/null || true
  fi
  if [[ -n "$FLUTTER_PID" ]]; then
    pkill -P "$FLUTTER_PID" 2>/dev/null || true
    kill "$FLUTTER_PID" 2>/dev/null || true
    wait "$FLUTTER_PID" 2>/dev/null || true
  fi
  rm -rf "$SCREENSHOT_DIR"
  rm -f "$CLI_BIN"
}
trap cleanup EXIT

# ─── Helpers ──────────────────────────────────────────────────────────────────

now_ms() {
  if date +%s%3N &>/dev/null; then
    date +%s%3N
  else
    python3 -c 'import time; print(int(time.time()*1000))'
  fi
}

char_count() { printf '%s' "$1" | wc -c | tr -d ' '; }
tokens_est() { echo $(( ($1 + 3) / 4 )); }

avg() {
  local sum=0 count=0
  for v in $1; do sum=$(( sum + v )); count=$(( count + 1 )); done
  [[ $count -gt 0 ]] && echo $(( sum / count )) || echo 0
}

# Time a command, capture stdout, return time in ms via printf -v
timed_run() {
  local _out_var="$1" _time_var="$2"; shift 2
  local _start _end _output
  _start=$(now_ms)
  _output=$("$@" 2>/dev/null) || true
  _end=$(now_ms)
  printf -v "$_out_var" '%s' "$_output"
  printf -v "$_time_var" '%s' "$(( _end - _start ))"
}

log_pair() {
  local dir="$1" op="$2" req="$3" resp="$4"
  printf '%s\n' "$req"  > "$dir/${op}_req.txt"
  printf '%s\n' "$resp" > "$dir/${op}_resp.txt"
}

# ─── App lifecycle ────────────────────────────────────────────────────────────

start_app() {
  if [[ -n "$SHARED_URI" ]]; then
    WS_URI="$SHARED_URI"
    echo "  Using provided URI: $WS_URI"
    return
  fi
  echo "  Starting Flutter app..."
  cd "$EXAMPLE_DIR"
  local flutter_log
  flutter_log=$(mktemp)
  flutter run --machine "${DEVICE_FLAG[@]}" >"$flutter_log" 2>&1 &
  FLUTTER_PID=$!
  WS_URI=""
  local deadline=$(( $(date +%s) + 120 ))
  while [[ -z "$WS_URI" ]]; do
    if [[ $(date +%s) -gt $deadline ]]; then
      echo "ERROR: Timed out waiting for Flutter app to start." >&2
      cat "$flutter_log" >&2
      exit 1
    fi
    WS_URI=$(grep -o '"wsUri":"[^"]*"' "$flutter_log" 2>/dev/null | head -1 | sed 's/"wsUri":"//;s/"//' || true)
    sleep 1
  done
  rm -f "$flutter_log"
  echo "  VM service URI: $WS_URI"
  cd "$REPO_ROOT"
}

stop_app() {
  [[ -n "$SHARED_URI" ]] && return
  if [[ -n "$FLUTTER_PID" ]]; then
    echo "  Stopping Flutter app..."
    pkill -P "$FLUTTER_PID" 2>/dev/null || true
    kill "$FLUTTER_PID" 2>/dev/null || true
    wait "$FLUTTER_PID" 2>/dev/null || true
    FLUTTER_PID=""
  fi
}

# ─── Batch helpers ────────────────────────────────────────────────────────────
# Run a CLI command $ITERATIONS times, print per-iteration ms, compute avg.
# Sets: ${pfx}_times, ${pfx}_avg, ${pfx}_sample via eval.

bench_cli() {
  local _pfx="$1" _log="$2" _label="$3"; shift 3
  local _times="" _sample="" _out _ms
  echo -n "  $_label:"
  for _i in $(seq 1 "$ITERATIONS"); do
    timed_run _out _ms "$@"
    _times="$_times $_ms"
    echo -n " $_ms"
    [[ $_i -eq 1 ]] && _sample="$_out" && log_pair "$_log" "$_label" "$*" "$_out"
  done
  local _a; _a=$(avg "$_times")
  eval "${_pfx}_times=\$_times; ${_pfx}_avg=\$_a; ${_pfx}_sample=\$_sample"
  echo " → avg=${_a}ms"
}

# ─── Phase 0: Compile CLI ────────────────────────────────────────────────────

echo "=== Phase 0: Compiling CLI to native binary ==="
dart compile exe "$CLI_SRC" -o "$CLI_BIN" 2>&1 | tail -1
chmod +x "$CLI_BIN"
echo "  Binary: $CLI_BIN"
echo

# ─── Phase 1: CLI + State (--instance) ───────────────────────────────────────

echo "=== Phase 1: CLI + State (--instance) — $ITERATIONS iterations ==="
CS_LOG="$LOG_DIR/cli_state"
INSTANCE_NAME="bench"

start_app

timed_run _out reg_ms "$CLI_BIN" register "$INSTANCE_NAME" "$WS_URI"
echo "  register:     ${reg_ms}ms"

bench_cli cli_s_elem   "$CS_LOG" elements   "$CLI_BIN" -i "$INSTANCE_NAME" elements
bench_cli cli_s_tap    "$CS_LOG" tap        "$CLI_BIN" -i "$INSTANCE_NAME" tap --type FloatingActionButton

# enter-text: runs before scroll (TextField visible at top)
cli_s_enter_times="" cli_s_enter_sample=""
echo -n "  enter-text:"
for i in $(seq 1 "$ITERATIONS"); do
  timed_run _out _ms "$CLI_BIN" -i "$INSTANCE_NAME" enter-text --key search_field --input "bench$i"
  cli_s_enter_times="$cli_s_enter_times $_ms"
  echo -n " $_ms"
  [[ $i -eq 1 ]] && cli_s_enter_sample="$_out" && log_pair "$CS_LOG" "enter-text" "$CLI_BIN -i $INSTANCE_NAME enter-text --key search_field --input bench$i" "$_out"
done
cli_s_enter_avg=$(avg "$cli_s_enter_times")
echo " → avg=${cli_s_enter_avg}ms"

# scroll-to: progressive (Item 20, 30, 40, ...) — must run AFTER enter-text
cli_s_scroll_times="" cli_s_scroll_sample=""
SCROLL_IDX=0
echo -n "  scroll-to:"
for i in $(seq 1 "$ITERATIONS"); do
  SCROLL_IDX=$(( SCROLL_IDX + 1 ))
  scroll_item="Item $(( SCROLL_IDX * 10 + 10 ))"
  timed_run _out _ms "$CLI_BIN" -i "$INSTANCE_NAME" scroll-to --text "$scroll_item"
  cli_s_scroll_times="$cli_s_scroll_times $_ms"
  echo -n " $_ms"
  [[ $i -eq 1 ]] && cli_s_scroll_sample="$_out" && log_pair "$CS_LOG" "scroll-to" "$CLI_BIN -i $INSTANCE_NAME scroll-to --text \"$scroll_item\"" "$_out"
done
cli_s_scroll_avg=$(avg "$cli_s_scroll_times")
echo " → avg=${cli_s_scroll_avg}ms"

bench_cli cli_s_ss     "$CS_LOG" screenshot "$CLI_BIN" -i "$INSTANCE_NAME" screenshot --output "$SCREENSHOT_DIR/cs.png"
bench_cli cli_s_logs   "$CS_LOG" logs       "$CLI_BIN" -i "$INSTANCE_NAME" logs
bench_cli cli_s_reload "$CS_LOG" hot-reload "$CLI_BIN" -i "$INSTANCE_NAME" hot-reload

cli_s_total_avg=$(( cli_s_elem_avg + cli_s_tap_avg + cli_s_enter_avg + cli_s_scroll_avg + cli_s_ss_avg + cli_s_logs_avg + cli_s_reload_avg ))

timed_run _out unreg_ms "$CLI_BIN" unregister "$INSTANCE_NAME"
echo "  unregister:   ${unreg_ms}ms"
stop_app
echo

# ─── Phase 2: CLI + Stateless (--uri) ────────────────────────────────────────

echo "=== Phase 2: CLI + Stateless (--uri) — $ITERATIONS iterations ==="
CU_LOG="$LOG_DIR/cli_uri"

start_app

bench_cli cli_u_elem   "$CU_LOG" elements   "$CLI_BIN" --uri "$WS_URI" elements
bench_cli cli_u_tap    "$CU_LOG" tap        "$CLI_BIN" --uri "$WS_URI" tap --type FloatingActionButton

# enter-text: before scroll
cli_u_enter_times="" cli_u_enter_sample=""
echo -n "  enter-text:"
for i in $(seq 1 "$ITERATIONS"); do
  timed_run _out _ms "$CLI_BIN" --uri "$WS_URI" enter-text --key search_field --input "bench$i"
  cli_u_enter_times="$cli_u_enter_times $_ms"
  echo -n " $_ms"
  [[ $i -eq 1 ]] && cli_u_enter_sample="$_out" && log_pair "$CU_LOG" "enter-text" "$CLI_BIN --uri $WS_URI enter-text --key search_field --input bench$i" "$_out"
done
cli_u_enter_avg=$(avg "$cli_u_enter_times")
echo " → avg=${cli_u_enter_avg}ms"

# scroll-to: progressive
cli_u_scroll_times="" cli_u_scroll_sample=""
SCROLL_IDX=0
echo -n "  scroll-to:"
for i in $(seq 1 "$ITERATIONS"); do
  SCROLL_IDX=$(( SCROLL_IDX + 1 ))
  scroll_item="Item $(( SCROLL_IDX * 10 + 10 ))"
  timed_run _out _ms "$CLI_BIN" --uri "$WS_URI" scroll-to --text "$scroll_item"
  cli_u_scroll_times="$cli_u_scroll_times $_ms"
  echo -n " $_ms"
  [[ $i -eq 1 ]] && cli_u_scroll_sample="$_out" && log_pair "$CU_LOG" "scroll-to" "$CLI_BIN --uri $WS_URI scroll-to --text \"$scroll_item\"" "$_out"
done
cli_u_scroll_avg=$(avg "$cli_u_scroll_times")
echo " → avg=${cli_u_scroll_avg}ms"

bench_cli cli_u_ss     "$CU_LOG" screenshot "$CLI_BIN" --uri "$WS_URI" screenshot --output "$SCREENSHOT_DIR/cu.png"
bench_cli cli_u_logs   "$CU_LOG" logs       "$CLI_BIN" --uri "$WS_URI" logs
bench_cli cli_u_reload "$CU_LOG" hot-reload "$CLI_BIN" --uri "$WS_URI" hot-reload

cli_u_total_avg=$(( cli_u_elem_avg + cli_u_tap_avg + cli_u_enter_avg + cli_u_scroll_avg + cli_u_ss_avg + cli_u_logs_avg + cli_u_reload_avg ))

stop_app
echo

# ─── Phase 3: CLI help-ai overhead ───────────────────────────────────────────

echo "=== Phase 3: CLI help-ai overhead ==="
timed_run helpai_out helpai_ms "$CLI_BIN" help-ai
HELPAI_CHARS=$(char_count "$helpai_out")
echo "  help-ai:      ${helpai_ms}ms  ($HELPAI_CHARS chars, ~$(tokens_est "$HELPAI_CHARS") tokens)"
log_pair "$LOG_DIR" "help-ai" "marionette help-ai" "$helpai_out"
echo

# ─── Phase 4: MCP (JSON-RPC over stdio) ──────────────────────────────────────

echo "=== Phase 4: MCP (JSON-RPC over stdio) — $ITERATIONS iterations ==="
MCP_LOG="$LOG_DIR/mcp"

start_app

coproc MCP_PROC { dart run "$MCP_SRC" --log-level SEVERE 2>/dev/null; }
MCP_PID=$MCP_PROC_PID
sleep 1

mcp_send() { echo "$1" >&"${MCP_PROC[1]}"; }
mcp_recv() {
  local line=""
  read -r -t 15 line <&"${MCP_PROC[0]}" || true
  printf '%s' "$line"
}
mcp_call() {
  local _out_var="$1" _time_var="$2" _req="$3"
  local _start _end _resp
  _start=$(now_ms)
  mcp_send "$_req"
  _resp=$(mcp_recv)
  _end=$(now_ms)
  printf -v "$_out_var" '%s' "$_resp"
  printf -v "$_time_var" '%s' "$(( _end - _start ))"
}

# Initialize
INIT_REQ='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"benchmark","version":"1.0"}}}'
mcp_call _out mcp_init_ms "$INIT_REQ"
echo "  initialize:   ${mcp_init_ms}ms"
log_pair "$MCP_LOG" "initialize" "$INIT_REQ" "$_out"

mcp_send '{"jsonrpc":"2.0","method":"notifications/initialized"}'
sleep 0.2

# tools/list
TOOLS_REQ='{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
mcp_call mcp_tools_out mcp_tools_ms "$TOOLS_REQ"
MCP_TOOLS_CHARS=$(char_count "$mcp_tools_out")
echo "  tools/list:   ${mcp_tools_ms}ms  ($MCP_TOOLS_CHARS chars, ~$(tokens_est "$MCP_TOOLS_CHARS") tokens)"
log_pair "$MCP_LOG" "tools_list" "$TOOLS_REQ" "$mcp_tools_out"

# connect
CONNECT_REQ="{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"connect\",\"arguments\":{\"uri\":\"$WS_URI\"}}}"
mcp_call mcp_connect_out mcp_connect_ms "$CONNECT_REQ"
echo "  connect:      ${mcp_connect_ms}ms"
log_pair "$MCP_LOG" "connect" "$CONNECT_REQ" "$mcp_connect_out"

MCP_ID=10

# Helper: run an MCP tool call $ITERATIONS times
# bench_mcp <pfx> <log_dir> <label> <tool_name> <json_arguments>
bench_mcp() {
  local _pfx="$1" _log="$2" _label="$3" _tool="$4" _args="$5"
  local _times="" _sample="" _req_sample="" _out _ms
  echo -n "  $_label:"
  for _i in $(seq 1 "$ITERATIONS"); do
    MCP_ID=$(( MCP_ID + 1 ))
    local _req="{\"jsonrpc\":\"2.0\",\"id\":$MCP_ID,\"method\":\"tools/call\",\"params\":{\"name\":\"$_tool\",\"arguments\":$_args}}"
    mcp_call _out _ms "$_req"
    _times="$_times $_ms"
    echo -n " $_ms"
    [[ $_i -eq 1 ]] && _sample="$_out" && _req_sample="$_req" && log_pair "$_log" "$_label" "$_req" "$_out"
  done
  local _a; _a=$(avg "$_times")
  eval "${_pfx}_times=\$_times; ${_pfx}_avg=\$_a; ${_pfx}_sample=\$_sample; ${_pfx}_req_sample=\$_req_sample"
  echo " → avg=${_a}ms"
}

bench_mcp mcp_elem   "$MCP_LOG" elements    get_interactive_elements '{}'
bench_mcp mcp_tap    "$MCP_LOG" tap         tap                      '{"type":"FloatingActionButton"}'

# enter-text: before scroll (TextField visible at top)
mcp_enter_times="" mcp_enter_sample="" mcp_enter_req_sample=""
echo -n "  enter-text:"
for i in $(seq 1 "$ITERATIONS"); do
  MCP_ID=$(( MCP_ID + 1 ))
  REQ="{\"jsonrpc\":\"2.0\",\"id\":$MCP_ID,\"method\":\"tools/call\",\"params\":{\"name\":\"enter_text\",\"arguments\":{\"key\":\"search_field\",\"input\":\"bench$i\"}}}"
  mcp_call _out _ms "$REQ"
  mcp_enter_times="$mcp_enter_times $_ms"
  echo -n " $_ms"
  [[ $i -eq 1 ]] && mcp_enter_sample="$_out" && mcp_enter_req_sample="$REQ" && log_pair "$MCP_LOG" "enter-text" "$REQ" "$_out"
done
mcp_enter_avg=$(avg "$mcp_enter_times")
echo " → avg=${mcp_enter_avg}ms"

# scroll-to: progressive (Item 20, 30, 40, ...)
mcp_scroll_times="" mcp_scroll_sample="" mcp_scroll_req_sample=""
SCROLL_IDX=0
echo -n "  scroll-to:"
for i in $(seq 1 "$ITERATIONS"); do
  SCROLL_IDX=$(( SCROLL_IDX + 1 ))
  scroll_item="Item $(( SCROLL_IDX * 10 + 10 ))"
  MCP_ID=$(( MCP_ID + 1 ))
  REQ="{\"jsonrpc\":\"2.0\",\"id\":$MCP_ID,\"method\":\"tools/call\",\"params\":{\"name\":\"scroll_to\",\"arguments\":{\"text\":\"$scroll_item\"}}}"
  mcp_call _out _ms "$REQ"
  mcp_scroll_times="$mcp_scroll_times $_ms"
  echo -n " $_ms"
  [[ $i -eq 1 ]] && mcp_scroll_sample="$_out" && mcp_scroll_req_sample="$REQ" && log_pair "$MCP_LOG" "scroll-to" "$REQ" "$_out"
done
mcp_scroll_avg=$(avg "$mcp_scroll_times")
echo " → avg=${mcp_scroll_avg}ms"

bench_mcp mcp_ss     "$MCP_LOG" screenshot  take_screenshots         '{}'
bench_mcp mcp_logs   "$MCP_LOG" logs        get_logs                 '{}'
bench_mcp mcp_reload "$MCP_LOG" hot-reload  hot_reload               '{}'

mcp_total_avg=$(( mcp_elem_avg + mcp_tap_avg + mcp_enter_avg + mcp_scroll_avg + mcp_ss_avg + mcp_logs_avg + mcp_reload_avg ))

# disconnect
MCP_ID=$(( MCP_ID + 1 ))
DISCONNECT_REQ="{\"jsonrpc\":\"2.0\",\"id\":$MCP_ID,\"method\":\"tools/call\",\"params\":{\"name\":\"disconnect\",\"arguments\":{}}}"
mcp_call _out mcp_disconnect_ms "$DISCONNECT_REQ"
echo "  disconnect:   ${mcp_disconnect_ms}ms"

kill "$MCP_PID" 2>/dev/null || true
wait "$MCP_PID" 2>/dev/null || true
MCP_PID=""

# Verify sample response sizes (sanity check)
echo "  ── MCP sample response sizes (chars) ──"
echo "    elements:   $(char_count "$mcp_elem_sample")"
echo "    tap:        $(char_count "$mcp_tap_sample")"
echo "    enter-text: $(char_count "$mcp_enter_sample")"
echo "    scroll-to:  $(char_count "$mcp_scroll_sample")"
echo "    screenshot: $(char_count "$mcp_ss_sample")"
echo "    logs:       $(char_count "$mcp_logs_sample")"
echo "    hot-reload: $(char_count "$mcp_reload_sample")"
echo "  ── CLI+State sample response sizes (chars) ──"
echo "    elements:   $(char_count "$cli_s_elem_sample")"
echo "    tap:        $(char_count "$cli_s_tap_sample")"
echo "    enter-text: $(char_count "$cli_s_enter_sample")"
echo "    scroll-to:  $(char_count "$cli_s_scroll_sample")"
echo "    screenshot: $(char_count "$cli_s_ss_sample")"
echo "    logs:       $(char_count "$cli_s_logs_sample")"
echo "    hot-reload: $(char_count "$cli_s_reload_sample")"

stop_app
echo

# ─── Phase 5: Speed Comparison Table ─────────────────────────────────────────

echo "=== Speed Results (avg of $ITERATIONS iterations) ==="
echo

printf '%-40s  %12s  %12s  %12s\n' "Metric" "MCP" "CLI+State" "CLI+URI"
printf '%-40s  %12s  %12s  %12s\n' "$(printf '%0.s─' {1..40})" "$(printf '%0.s─' {1..12})" "$(printf '%0.s─' {1..12})" "$(printf '%0.s─' {1..12})"

printf '%-40s  %12s  %12s  %12s\n' "elements avg (ms)"   "$mcp_elem_avg"   "$cli_s_elem_avg"   "$cli_u_elem_avg"
printf '%-40s  %12s  %12s  %12s\n' "tap avg (ms)"        "$mcp_tap_avg"    "$cli_s_tap_avg"    "$cli_u_tap_avg"
printf '%-40s  %12s  %12s  %12s\n' "enter-text avg (ms)" "$mcp_enter_avg"  "$cli_s_enter_avg"  "$cli_u_enter_avg"
printf '%-40s  %12s  %12s  %12s\n' "scroll-to avg (ms)"  "$mcp_scroll_avg" "$cli_s_scroll_avg" "$cli_u_scroll_avg"
printf '%-40s  %12s  %12s  %12s\n' "screenshot avg (ms)" "$mcp_ss_avg"     "$cli_s_ss_avg"     "$cli_u_ss_avg"
printf '%-40s  %12s  %12s  %12s\n' "logs avg (ms)"       "$mcp_logs_avg"   "$cli_s_logs_avg"   "$cli_u_logs_avg"
printf '%-40s  %12s  %12s  %12s\n' "hot-reload avg (ms)" "$mcp_reload_avg" "$cli_s_reload_avg" "$cli_u_reload_avg"

printf '%-40s  %12s  %12s  %12s\n' "$(printf '%0.s─' {1..40})" "$(printf '%0.s─' {1..12})" "$(printf '%0.s─' {1..12})" "$(printf '%0.s─' {1..12})"
printf '%-40s  %12s  %12s  %12s\n' "Total avg (ms)" "$mcp_total_avg" "$cli_s_total_avg" "$cli_u_total_avg"
echo

# ─── Phase 6: Token Usage Table ──────────────────────────────────────────────

echo "=== Token Usage per Operation (single call, chars → ~tokens) ==="
echo

# CLI command strings (what the AI would generate per call)
cli_s_elem_cmd="marionette -i $INSTANCE_NAME elements"
cli_s_tap_cmd="marionette -i $INSTANCE_NAME tap --type FloatingActionButton"
cli_s_enter_cmd="marionette -i $INSTANCE_NAME enter-text --key search_field --input \"bench1\""
cli_s_scroll_cmd="marionette -i $INSTANCE_NAME scroll-to --text \"Item 20\""
cli_s_ss_cmd="marionette -i $INSTANCE_NAME screenshot --output screenshot.png"
cli_s_logs_cmd="marionette -i $INSTANCE_NAME logs"
cli_s_reload_cmd="marionette -i $INSTANCE_NAME hot-reload"

cli_u_elem_cmd="marionette --uri \$WS_URI elements"
cli_u_tap_cmd="marionette --uri \$WS_URI tap --type FloatingActionButton"
cli_u_enter_cmd="marionette --uri \$WS_URI enter-text --key search_field --input \"bench1\""
cli_u_scroll_cmd="marionette --uri \$WS_URI scroll-to --text \"Item 20\""
cli_u_ss_cmd="marionette --uri \$WS_URI screenshot --output screenshot.png"
cli_u_logs_cmd="marionette --uri \$WS_URI logs"
cli_u_reload_cmd="marionette --uri \$WS_URI hot-reload"

print_token_row() {
  local label="$1"
  local mcp_req_chars=$(char_count "$2")
  local mcp_resp_chars=$(char_count "$3")
  local cli_s_req_chars=$(char_count "$4")
  local cli_s_resp_chars=$(char_count "$5")
  local cli_u_req_chars=$(char_count "$6")
  local cli_u_resp_chars=$(char_count "$7")

  printf '%-20s  %6s / %-6s  %6s / %-6s  %6s / %-6s\n' \
    "$label" \
    "~$(tokens_est "$mcp_req_chars")" "~$(tokens_est "$mcp_resp_chars")" \
    "~$(tokens_est "$cli_s_req_chars")" "~$(tokens_est "$cli_s_resp_chars")" \
    "~$(tokens_est "$cli_u_req_chars")" "~$(tokens_est "$cli_u_resp_chars")"
}

printf '%-20s  %15s  %15s  %15s\n' "Operation" "MCP" "CLI+State" "CLI+URI"
printf '%-20s  %15s  %15s  %15s\n' "" "req / resp" "req / resp" "req / resp"
printf '%-20s  %15s  %15s  %15s\n' "$(printf '%0.s─' {1..20})" "$(printf '%0.s─' {1..15})" "$(printf '%0.s─' {1..15})" "$(printf '%0.s─' {1..15})"

print_token_row "elements" \
  "$mcp_elem_req_sample" "$mcp_elem_sample" \
  "$cli_s_elem_cmd" "$cli_s_elem_sample" \
  "$cli_u_elem_cmd" "$cli_u_elem_sample"

print_token_row "tap" \
  "$mcp_tap_req_sample" "$mcp_tap_sample" \
  "$cli_s_tap_cmd" "$cli_s_tap_sample" \
  "$cli_u_tap_cmd" "$cli_u_tap_sample"

print_token_row "enter-text" \
  "$mcp_enter_req_sample" "$mcp_enter_sample" \
  "$cli_s_enter_cmd" "$cli_s_enter_sample" \
  "$cli_u_enter_cmd" "$cli_u_enter_sample"

print_token_row "scroll-to" \
  "$mcp_scroll_req_sample" "$mcp_scroll_sample" \
  "$cli_s_scroll_cmd" "$cli_s_scroll_sample" \
  "$cli_u_scroll_cmd" "$cli_u_scroll_sample"

print_token_row "screenshot" \
  "$mcp_ss_req_sample" "$mcp_ss_sample" \
  "$cli_s_ss_cmd" "$cli_s_ss_sample" \
  "$cli_u_ss_cmd" "$cli_u_ss_sample"

print_token_row "logs" \
  "$mcp_logs_req_sample" "$mcp_logs_sample" \
  "$cli_s_logs_cmd" "$cli_s_logs_sample" \
  "$cli_u_logs_cmd" "$cli_u_logs_sample"

print_token_row "hot-reload" \
  "$mcp_reload_req_sample" "$mcp_reload_sample" \
  "$cli_s_reload_cmd" "$cli_s_reload_sample" \
  "$cli_u_reload_cmd" "$cli_u_reload_sample"

# Totals
mcp_req_total_chars=0 mcp_resp_total_chars=0
cli_s_req_total_chars=0 cli_s_resp_total_chars=0
cli_u_req_total_chars=0 cli_u_resp_total_chars=0

for var in mcp_elem_req_sample mcp_tap_req_sample mcp_enter_req_sample mcp_scroll_req_sample mcp_ss_req_sample mcp_logs_req_sample mcp_reload_req_sample; do
  mcp_req_total_chars=$(( mcp_req_total_chars + $(char_count "${!var}") ))
done
for var in mcp_elem_sample mcp_tap_sample mcp_enter_sample mcp_scroll_sample mcp_ss_sample mcp_logs_sample mcp_reload_sample; do
  mcp_resp_total_chars=$(( mcp_resp_total_chars + $(char_count "${!var}") ))
done
for var in cli_s_elem_cmd cli_s_tap_cmd cli_s_enter_cmd cli_s_scroll_cmd cli_s_ss_cmd cli_s_logs_cmd cli_s_reload_cmd; do
  cli_s_req_total_chars=$(( cli_s_req_total_chars + $(char_count "${!var}") ))
done
for var in cli_s_elem_sample cli_s_tap_sample cli_s_enter_sample cli_s_scroll_sample cli_s_ss_sample cli_s_logs_sample cli_s_reload_sample; do
  cli_s_resp_total_chars=$(( cli_s_resp_total_chars + $(char_count "${!var}") ))
done
for var in cli_u_elem_cmd cli_u_tap_cmd cli_u_enter_cmd cli_u_scroll_cmd cli_u_ss_cmd cli_u_logs_cmd cli_u_reload_cmd; do
  cli_u_req_total_chars=$(( cli_u_req_total_chars + $(char_count "${!var}") ))
done
for var in cli_u_elem_sample cli_u_tap_sample cli_u_enter_sample cli_u_scroll_sample cli_u_ss_sample cli_u_logs_sample cli_u_reload_sample; do
  cli_u_resp_total_chars=$(( cli_u_resp_total_chars + $(char_count "${!var}") ))
done

printf '%-20s  %15s  %15s  %15s\n' "$(printf '%0.s─' {1..20})" "$(printf '%0.s─' {1..15})" "$(printf '%0.s─' {1..15})" "$(printf '%0.s─' {1..15})"
printf '%-20s  %6s / %-6s  %6s / %-6s  %6s / %-6s\n' \
  "Total (7 ops)" \
  "~$(tokens_est "$mcp_req_total_chars")" "~$(tokens_est "$mcp_resp_total_chars")" \
  "~$(tokens_est "$cli_s_req_total_chars")" "~$(tokens_est "$cli_s_resp_total_chars")" \
  "~$(tokens_est "$cli_u_req_total_chars")" "~$(tokens_est "$cli_u_resp_total_chars")"

printf '%-20s  %6s / %-6s  %6s / %-6s  %6s / %-6s\n' \
  "One-time setup" \
  "~$(tokens_est "$MCP_TOOLS_CHARS")" "—" \
  "~$(tokens_est "$HELPAI_CHARS")" "—" \
  "~$(tokens_est "$HELPAI_CHARS")" "—"

echo
echo "Notes:"
echo "  - Each operation ran $ITERATIONS times; speed values are averages"
echo "  - A fresh Flutter app is started for each test phase"
echo "  - Operations run in batches: enter-text before scroll (TextField must be visible)"
echo "  - Scroll targets progress: Item 20, 30, 40, ... (10 items further each iteration)"
echo "  - Token estimates use ~4 chars/token approximation"
echo "  - req = what the AI sends (CLI command string vs MCP JSON-RPC request)"
echo "  - resp = what comes back (CLI plain text stdout vs MCP JSON-RPC response)"
echo "  - One-time setup: MCP tool definitions vs CLI help-ai text (loaded once per session)"
echo "  - CLI compiled to native binary (dart compile exe) for fair speed comparison"
echo "  - Set ITERATIONS=N to change iteration count (default: 10)"

echo
echo "Request/response logs saved to:"
echo "  $LOG_DIR/cli_state/  — CLI+State (7 ops × req + resp)"
echo "  $LOG_DIR/cli_uri/    — CLI+URI   (7 ops × req + resp)"
echo "  $LOG_DIR/mcp/        — MCP       (7 ops × req + resp + setup)"
echo "  Files: {op}_req.txt, {op}_resp.txt"
echo
