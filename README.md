# Telegram Guard for Claude Code

Claude Code를 원격으로 쓸 때 권한 프롬프트가 떠서 작업이 멈추는 문제를 해결합니다.

터미널 출력을 감시하다가 권한 요청이 뜨면 텔레그램으로 알림을 보내고, 버튼 하나로 승인/거부할 수 있습니다.

## 동작 원리

```
Claude Code (tmux 세션 안에서 실행)
     │
     ├─ 권한 프롬프트 발생 ("Allow Bash tool?")
     │
telegram_guard.py (백그라운드 데몬)
     ├─ tmux 출력 2초마다 감시 (로컬 명령어, 토큰 소모 없음)
     ├─ 프롬프트 패턴 감지
     ├─ 텔레그램으로 알림 전송 (승인/거부 버튼)
     └─ 응답에 따라 tmux에 'y' 또는 'n' 키 입력
```

**AI API 호출 없음. 토큰 소모 0.**

## 설치

```bash
git clone https://github.com/bugbug9999/telegram-guard.git
cd telegram-guard
./setup.sh
```

`setup.sh`가 알아서 해줍니다:
- tmux 설치 확인 (없으면 Homebrew로 설치)
- Python 3 확인
- 텔레그램 봇 설정 (토큰 입력 + 자동 검증 + 테스트 메시지)

## 텔레그램 봇 만들기 (처음인 경우)

1. 텔레그램에서 **@BotFather** 검색
2. `/newbot` 입력
3. 봇 이름 입력 (예: `My Claude Guard`)
4. 봇 유저네임 입력 (예: `my_claude_guard_bot`)
5. BotFather가 알려주는 **토큰**을 복사 (예: `123456789:ABCdef...`)
6. 만든 봇에게 아무 메시지 하나 보내기
7. `./setup.sh` 실행하면 Chat ID 자동 감지

## 사용법

```bash
# 시작 (tmux + Claude Code + Guard 한번에)
./start.sh

# Claude Code에 인자 전달
./start.sh --model opus

# 종료
./stop.sh

# tmux 세션 직접 접속 (디버깅용)
tmux attach -t claude
```

## 설정 (config.json)

| 항목 | 기본값 | 설명 |
|------|--------|------|
| `poll_interval` | `2` | 터미널 감시 주기 (초) |
| `timeout_seconds` | `900` | 무응답 타임아웃 (15분) |
| `timeout_action` | `"deny"` | 타임아웃 시 동작 (`"deny"` 또는 `"approve"`) |
| `auto_approve_patterns` | `["Read", "Glob", ...]` | 알림 없이 자동 승인할 도구 |
| `tmux_session` | `"claude"` | tmux 세션 이름 |

### 자동 승인 예시

읽기 전용 도구는 자동 승인하고 싶으면:
```json
{
  "auto_approve_patterns": ["Read", "Glob", "Grep", "WebSearch", "WebFetch"]
}
```

전부 수동 승인하려면:
```json
{
  "auto_approve_patterns": []
}
```

## 요구사항

- macOS (Linux도 가능)
- Python 3.6+
- tmux
- 텔레그램 계정 + 봇

## 라이센스

MIT
