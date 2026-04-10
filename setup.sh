#!/bin/bash
# ─────────────────────────────────────────────
# Claude Auto Permit — Setup Script
# ─────────────────────────────────────────────

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║    Claude Auto Permit — Setup             ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Step 1: tmux 설치 확인 ──
echo "▶ Step 1/3: tmux 확인"
if command -v tmux &>/dev/null; then
    echo "  ✅ tmux 이미 설치됨 ($(tmux -V))"
else
    echo "  ⚠️  tmux가 설치되어 있지 않습니다."
    if command -v brew &>/dev/null; then
        read -p "  Homebrew로 tmux를 설치할까요? (y/n) " yn
        if [ "$yn" = "y" ] || [ "$yn" = "Y" ]; then
            brew install tmux
            echo "  ✅ tmux 설치 완료"
        else
            echo "  ❌ tmux 없이는 동작하지 않습니다. 수동으로 설치 후 다시 실행해주세요."
            echo "     brew install tmux"
            exit 1
        fi
    else
        echo "  ❌ Homebrew가 없습니다. 먼저 tmux를 설치해주세요:"
        echo "     https://github.com/tmux/tmux/wiki/Installing"
        exit 1
    fi
fi
echo ""

# ── Step 2: Python 확인 ──
echo "▶ Step 2/3: Python 확인"
if command -v python3 &>/dev/null; then
    PY_VER=$(python3 --version 2>&1)
    echo "  ✅ $PY_VER"
else
    echo "  ❌ Python 3이 필요합니다."
    echo "     https://www.python.org/downloads/"
    exit 1
fi
echo ""

# ── Step 3: 텔레그램 봇 설정 ──
echo "▶ Step 3/3: 텔레그램 봇 설정"

if [ -f "$CONFIG" ]; then
    echo "  ℹ️  config.json이 이미 존재합니다."
    read -p "  기존 설정을 덮어쓸까요? (y/n) " overwrite
    if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
        echo "  ✅ 기존 설정 유지"
        echo ""
        echo "══════════════════════════════════════"
        echo "  설치 완료! 실행하려면:"
        echo "    ./start.sh"
        echo "══════════════════════════════════════"
        exit 0
    fi
fi

echo ""
echo "  ┌──────────────────────────────────────────────────┐"
echo "  │  텔레그램 봇이 없다면 아래 순서대로 만드세요:      │"
echo "  │                                                    │"
echo "  │  1. 텔레그램에서 @BotFather 검색                   │"
echo "  │  2. /newbot 입력                                   │"
echo "  │  3. 봇 이름 입력 (예: My Claude Guard)             │"
echo "  │  4. 봇 유저네임 입력 (예: my_claude_guard_bot)     │"
echo "  │  5. BotFather가 알려주는 토큰을 복사               │"
echo "  │     (예: 123456789:ABCdef...)                      │"
echo "  │                                                    │"
echo "  │  그 다음 Chat ID를 알아내야 합니다:                 │"
echo "  │  1. 만든 봇에게 아무 메시지 하나 보내기            │"
echo "  │  2. 브라우저에서 아래 URL 열기:                     │"
echo "  │     https://api.telegram.org/bot{토큰}/getUpdates  │"
echo "  │  3. 결과에서 \"chat\":{\"id\": 숫자} 부분의 숫자 복사  │"
echo "  └──────────────────────────────────────────────────┘"
echo ""

# Bot Token 입력
while true; do
    read -p "  Bot Token: " BOT_TOKEN
    if [ -z "$BOT_TOKEN" ]; then
        echo "  ⚠️  토큰을 입력해주세요."
        continue
    fi
    # 토큰 유효성 검증
    echo "  🔄 토큰 확인 중..."
    RESULT=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe" 2>/dev/null)
    if echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['ok']" 2>/dev/null; then
        BOT_NAME=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['username'])" 2>/dev/null)
        echo "  ✅ 봇 확인됨: @$BOT_NAME"
        break
    else
        echo "  ❌ 유효하지 않은 토큰입니다. 다시 입력해주세요."
    fi
done

# Chat ID 입력
echo ""
echo "  💡 Chat ID를 모르면 봇에게 아무 메시지를 보낸 후"
echo "     여기서 Enter를 누르면 자동으로 찾아봅니다."
echo ""
read -p "  Chat ID (모르면 Enter): " CHAT_ID

if [ -z "$CHAT_ID" ]; then
    echo "  🔄 최근 메시지에서 Chat ID 찾는 중..."
    UPDATES=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates" 2>/dev/null)
    CHAT_ID=$(echo "$UPDATES" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data.get('result'):
    for update in reversed(data['result']):
        msg = update.get('message', {})
        chat = msg.get('chat', {})
        if chat.get('id'):
            print(chat['id'])
            break
" 2>/dev/null)
    if [ -n "$CHAT_ID" ]; then
        echo "  ✅ Chat ID 발견: $CHAT_ID"
    else
        echo "  ❌ Chat ID를 찾을 수 없습니다."
        echo "     봇에게 메시지를 보낸 후 다시 시도하거나, 직접 입력해주세요."
        read -p "  Chat ID: " CHAT_ID
        if [ -z "$CHAT_ID" ]; then
            echo "  ❌ Chat ID 없이는 알림을 보낼 수 없습니다."
            exit 1
        fi
    fi
fi

# 테스트 메시지 전송
echo ""
echo "  🔄 테스트 메시지 전송 중..."
TEST_RESULT=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "{\"chat_id\": \"${CHAT_ID}\", \"text\": \"✅ Telegram Guard 설정 완료! 이제 Claude Code 권한 요청이 여기로 옵니다.\"}" 2>/dev/null)

if echo "$TEST_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['ok']" 2>/dev/null; then
    echo "  ✅ 텔레그램 테스트 메시지 전송 성공! 확인해보세요."
else
    echo "  ⚠️  메시지 전송 실패. Chat ID를 확인해주세요."
fi

# config.json 생성
cat > "$CONFIG" <<EOF
{
  "bot_token": "$BOT_TOKEN",
  "chat_id": "$CHAT_ID",
  "tmux_session": "claude",
  "poll_interval": 2,
  "timeout_seconds": 900,
  "timeout_action": "deny",
  "auto_approve_patterns": [
    "Read",
    "Glob",
    "Grep",
    "WebSearch",
    "WebFetch"
  ]
}
EOF

echo ""
echo "  ✅ config.json 생성 완료"

# 실행 권한
chmod +x "$SCRIPT_DIR/start.sh" "$SCRIPT_DIR/stop.sh" "$SCRIPT_DIR/telegram_guard.py"

echo ""
echo "══════════════════════════════════════════"
echo "  🎉 설치 완료!"
echo ""
echo "  실행:  ./start.sh"
echo "  종료:  ./stop.sh"
echo "  설정:  config.json 수정"
echo "══════════════════════════════════════════"
