#!/bin/bash
# Telegram Guard + Claude Code 런처
# 사용법: ./start.sh [claude 명령 인자들...]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION="claude"
GUARD_PID_FILE="$SCRIPT_DIR/.guard.pid"

# PATH 설정
export PATH="/tmp/node-v22.14.0-darwin-arm64/bin:/opt/homebrew/bin:$PATH"

# 이미 실행 중인지 확인
if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "⚠️  tmux 세션 '$SESSION' 이미 실행 중"
    echo "   접속: tmux attach -t $SESSION"
    echo "   종료: ./stop.sh"
    exit 1
fi

# guard 이미 실행 중이면 종료
if [ -f "$GUARD_PID_FILE" ]; then
    OLD_PID=$(cat "$GUARD_PID_FILE")
    kill "$OLD_PID" 2>/dev/null
    rm -f "$GUARD_PID_FILE"
fi

# tmux 세션 생성 + Claude Code 실행
CLAUDE_CMD="claude $*"
tmux new-session -d -s "$SESSION" "$CLAUDE_CMD"
echo "✅ tmux 세션 '$SESSION' 생성 — Claude Code 실행 중"

# guard 데몬 시작
python3 "$SCRIPT_DIR/telegram_guard.py" &
GUARD_PID=$!
echo "$GUARD_PID" > "$GUARD_PID_FILE"
echo "✅ Telegram Guard 시작 (PID: $GUARD_PID)"

echo ""
echo "📱 텔레그램에서 권한 요청 알림을 받을 수 있어"
echo "   tmux 접속: tmux attach -t $SESSION"
echo "   종료:      ./stop.sh"
