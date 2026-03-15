#!/bin/bash

# Telegram notification helper
# Source this file AFTER loading server/.env so TELEGRAM_BOT_TOKEN and
# TELEGRAM_CHAT_ID are already in the environment.
#
# Registers an EXIT trap that fires on every exit:
#   exit code 0  → sends  "✅ Backup OK: <script-name>"
#   exit code != 0 → sends "❌ Backup FAILED: <script-name> (exit <code>)"
#
# If either variable is missing the trap is a no-op; scripts still work.

_tg_send() {
    local text="$1"
    [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] || return 0
    curl -sS --max-time 10 \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${text}" \
        > /dev/null 2>&1 || true
}

_tg_on_exit() {
    local code=$?
    local name
    name="$(basename "$0")"
    if [ "$code" -ne 0 ]; then
        _tg_send "❌ Backup FAILED: ${name} (exit ${code})"
    else
        _tg_send "✅ Backup OK: ${name}"
    fi
}

trap '_tg_on_exit' EXIT
