#!/bin/bash
# Daily Robinhood trading bot runner.
#
# Task (arg 1):  entry (default) | exit
#   entry = once at the open; Opus picks & buys per policy.md
#   exit  = intraday monitor; Haiku checks the open position and sells on
#           take-profit/stop per exit-policy.md (never buys). Market-hours only.
#
# Live/paper gate (both tasks):
#   - bot/STOP present -> HALT (nothing runs, entry or exit)
#   - bot/LIVE present -> LIVE (real orders)
#   - neither          -> PAPER (reads + logs intended action, places nothing) [default]
#
# Controls:
#   touch bot/LIVE / rm bot/LIVE   # arm / disarm real trading
#   touch bot/STOP                 # kill switch (halts entry AND exit)
set -uo pipefail

PROJ_DIR="/Users/jackbrown/robinhood-trading"
BOT_DIR="$PROJ_DIR/bot"
LOG_DIR="$BOT_DIR/logs"
STOP_FILE="$BOT_DIR/STOP"
LIVE_FILE="$BOT_DIR/LIVE"
MCP_CONFIG="$PROJ_DIR/.mcp.json"

mkdir -p "$LOG_DIR"
TASK="${1:-entry}"
# Backward-compat: the loaded entry plist passes a legacy mode word ('live'/'dry'/
# 'auto') as arg1. Treat any of those as the entry task; mode now comes from the
# LIVE flag file, not the argument.
case "$TASK" in live|dry|auto) TASK="entry" ;; esac

STAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"
DAYLOG="$LOG_DIR/$(date '+%Y-%m-%d').log"

# --- Kill switch (highest priority) ---
if [ -f "$STOP_FILE" ]; then
  echo "[$STAMP] HALTED ($TASK): STOP file present. No action." >> "$DAYLOG"
  exit 0
fi

# --- The entry run keeps the Mac awake through the session (~6.5h) so the
#     intraday exit monitor can fire. Best-effort: closed-lid/battery may override.
if [ "$TASK" = "entry" ]; then
  /usr/bin/caffeinate -dimsu -t 23400 >/dev/null 2>&1 &
fi

# --- Exit task runs only during ~market hours (machine is on Pacific time) ---
if [ "$TASK" = "exit" ]; then
  dow=$(date +%u)              # 1=Mon .. 7=Sun
  hm=$((10#$(date +%H%M)))     # base-10 HHMM, e.g. 0930 -> 930
  if [ "$dow" -gt 5 ] || [ "$hm" -lt 630 ] || [ "$hm" -gt 1300 ]; then
    exit 0                     # outside 6:30am-1:00pm PT Mon-Fri: skip silently
  fi
fi

# --- Live/paper from the LIVE flag (hard gate) ---
if [ -f "$LIVE_FILE" ]; then MODE="live"; else MODE="dry"; fi

# --- Per-task config ---
case "$TASK" in
  entry) POLICY="$BOT_DIR/policy.md";      MODEL="claude-opus-4-8" ;;
  exit)  POLICY="$BOT_DIR/exit-policy.md"; MODEL="claude-haiku-4-5-20251001" ;;
  *) echo "[$STAMP] unknown task '$TASK'" >> "$DAYLOG"; exit 1 ;;
esac

READ_TOOLS="mcp__robinhood-trading__get_accounts,mcp__robinhood-trading__get_portfolio,mcp__robinhood-trading__get_equity_positions,mcp__robinhood-trading__get_equity_quotes,mcp__robinhood-trading__get_equity_historicals,mcp__robinhood-trading__get_equity_orders,mcp__robinhood-trading__get_equity_tradability,mcp__robinhood-trading__search,mcp__robinhood-trading__review_equity_order"
WRITE_TOOLS="mcp__robinhood-trading__place_equity_order,mcp__robinhood-trading__cancel_equity_order"

PROMPT="$(cat "$POLICY")"
if [ "$MODE" = "dry" ]; then
  TOOLS="$READ_TOOLS"
  PROMPT="$PROMPT

# PAPER MODE
Order tools are unavailable. Do NOT attempt to place or cancel anything. In the SUMMARY line, state exactly what order you WOULD place."
else
  TOOLS="$READ_TOOLS,$WRITE_TOOLS"
fi

echo "[$STAMP] === RUN START (task=$TASK, mode=$MODE, model=$MODEL) ===" >> "$DAYLOG"

# Resolve binaries to absolute paths. launchd's PATH is minimal and omits
# Homebrew (/opt/homebrew/bin on Apple Silicon), where coreutils' `timeout` lives.
CLAUDE_BIN="$(command -v claude || echo /Users/jackbrown/.local/bin/claude)"
TIMEOUT_BIN=""
for c in /opt/homebrew/bin/timeout /opt/homebrew/bin/gtimeout /usr/local/bin/timeout /usr/local/bin/gtimeout timeout gtimeout; do
  if command -v "$c" >/dev/null 2>&1; then TIMEOUT_BIN="$(command -v "$c")"; break; fi
done

if [ -n "$TIMEOUT_BIN" ]; then
  "$TIMEOUT_BIN" 300 "$CLAUDE_BIN" -p "$PROMPT" \
    --allowedTools "$TOOLS" \
    --mcp-config "$MCP_CONFIG" \
    --model "$MODEL" \
    --output-format text >> "$DAYLOG" 2>&1 < /dev/null
  RC=$?
else
  echo "[$STAMP] WARN: no timeout binary found; running without a hard timeout" >> "$DAYLOG"
  "$CLAUDE_BIN" -p "$PROMPT" \
    --allowedTools "$TOOLS" \
    --mcp-config "$MCP_CONFIG" \
    --model "$MODEL" \
    --output-format text >> "$DAYLOG" 2>&1 < /dev/null
  RC=$?
fi

grep -h '^SUMMARY:' "$DAYLOG" | tail -1 >> "$LOG_DIR/summary.log" 2>/dev/null

echo "" >> "$DAYLOG"
echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] === RUN END (task=$TASK, mode=$MODE, exit $RC) ===" >> "$DAYLOG"
exit $RC
