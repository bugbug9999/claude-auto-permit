#!/bin/bash
# Telegram Guard + Claude Code 종료

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION="claude"
GUARD_PID_FILE="$SCRIPT_DIR/.guard.pid"

# guard 종료
if [ -f "$GUARD_PID_FILE" ]; then
    PID=$(cat "$GUARD_PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        kill "$PID"
        echo "✅ Telegram Guard 종료 (PID: $PID)"
    else
        echo "⚠️  Guard 프로세스 이미 종료됨"
    fi
    rm -f "$GUARD_PID_FILE"
else
    echo "⚠️  Guard PID 파일 없음"
fi

# tmux 세션 종료
if tmux has-session -t "$SESSION" 2>/dev/null; then
    tmux kill-session -t "$SESSION"
    echo "✅ tmux 세션 '$SESSION' 종료"
else
    echo "⚠️  tmux 세션 '$SESSION' 없음"
fi

echo "🔴 전체 종료 완료"
