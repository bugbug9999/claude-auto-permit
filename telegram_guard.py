#!/usr/bin/env python3
"""
Claude Auto Permit
- tmux 세션 출력을 감시해서 권한 프롬프트 감지
- 텔레그램으로 알림 + 인라인 키보드 (승인/거부)
- 응답에 따라 tmux에 키 입력
"""

import json
import hashlib
import time
import subprocess
import re
import signal
import sys
import os
import logging
from typing import Optional, List
from urllib.request import Request, urlopen
from urllib.parse import urlencode
from urllib.error import URLError

# ── 로깅 ──
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("guard")

# ── 설정 로드 ──
CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.json")

with open(CONFIG_PATH) as f:
    CFG = json.load(f)

BOT_TOKEN = CFG["bot_token"]
CHAT_ID = CFG["chat_id"]
TMUX_SESSION = CFG.get("tmux_session", "claude")
POLL_INTERVAL = CFG.get("poll_interval", 2)
TIMEOUT_SEC = CFG.get("timeout_seconds", 300)
TIMEOUT_ACTION = CFG.get("timeout_action", "deny")
AUTO_APPROVE = CFG.get("auto_approve_patterns", [])

API = f"https://api.telegram.org/bot{BOT_TOKEN}"

# ── 프롬프트 감지 패턴 ──
PROMPT_PATTERNS = [
    # Claude Code 권한 프롬프트
    re.compile(r"(?:Allow|허용)\s+.+\s*\?", re.IGNORECASE),
    re.compile(r"\(y\s*/\s*n\)", re.IGNORECASE),
    re.compile(r"Allow once|Allow always|Deny", re.IGNORECASE),
    re.compile(r"Do you want to\s+", re.IGNORECASE),
    re.compile(r"Permission required", re.IGNORECASE),
    re.compile(r"Press Enter to allow|Yes,? allow", re.IGNORECASE),
    # AskUserQuestion 패턴
    re.compile(r"Select an option|Choose.*:", re.IGNORECASE),
]

# ── 상태 ──
sent_hashes = set()  # type: set
pending_msg_id = None  # type: Optional[int]
pending_prompt_text = ""  # type: str
update_offset = 0  # type: int
running = True


def tg_request(method, data=None):
    """텔레그램 API 호출 (requests 없이 urllib 사용)"""
    url = f"{API}/{method}"
    if data:
        body = json.dumps(data).encode()
        req = Request(url, data=body, headers={"Content-Type": "application/json"})
    else:
        req = Request(url)
    try:
        with urlopen(req, timeout=35) as resp:
            return json.loads(resp.read())
    except URLError as e:
        log.error(f"Telegram API error: {e}")
        return {"ok": False}


def send_alert(text):
    """텔레그램 알림 + 인라인 키보드 전송. message_id 반환."""
    keyboard = {
        "inline_keyboard": [
            [
                {"text": "✅ 승인", "callback_data": "approve"},
                {"text": "❌ 거부", "callback_data": "deny"},
            ]
        ]
    }
    resp = tg_request("sendMessage", {
        "chat_id": CHAT_ID,
        "text": text,
        "parse_mode": "HTML",
        "reply_markup": keyboard,
    })
    if resp.get("ok"):
        return resp["result"]["message_id"]
    return None


def send_simple(text: str):
    """단순 텍스트 메시지 전송"""
    tg_request("sendMessage", {
        "chat_id": CHAT_ID,
        "text": text,
        "parse_mode": "HTML",
    })


def answer_callback(callback_id: str, text: str):
    """callback_query 응답"""
    tg_request("answerCallbackQuery", {
        "callback_query_id": callback_id,
        "text": text,
    })


def get_tmux_output() -> str:
    """tmux 세션의 최근 50줄 캡처"""
    try:
        result = subprocess.run(
            ["tmux", "capture-pane", "-t", TMUX_SESSION, "-p", "-S", "-50"],
            capture_output=True, text=True, timeout=5,
        )
        return result.stdout
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return ""


def send_keys(keys: str):
    """tmux 세션에 키 입력"""
    try:
        subprocess.run(
            ["tmux", "send-keys", "-t", TMUX_SESSION, keys],
            timeout=5,
        )
        log.info(f"Sent keys: {repr(keys)}")
    except Exception as e:
        log.error(f"send_keys failed: {e}")


def hash_text(text: str) -> str:
    return hashlib.md5(text.strip().encode()).hexdigest()[:12]


def extract_prompt_context(output: str) -> Optional[str]:
    """출력에서 프롬프트 부분 추출"""
    lines = output.strip().split("\n")
    # 뒤에서부터 스캔해서 프롬프트 블록 찾기
    prompt_lines = []
    found = False
    for line in reversed(lines):
        stripped = line.strip()
        if not stripped:
            if found:
                break
            continue
        for pat in PROMPT_PATTERNS:
            if pat.search(stripped):
                found = True
                break
        if found:
            prompt_lines.insert(0, stripped)
        elif prompt_lines:
            # 프롬프트 위의 컨텍스트 줄도 포함
            prompt_lines.insert(0, stripped)
            if len(prompt_lines) > 10:
                break

    if not found:
        return None
    return "\n".join(prompt_lines[-10:])  # 최대 10줄


def check_auto_approve(prompt_text: str) -> bool:
    """자동 승인 패턴 체크"""
    for pattern in AUTO_APPROVE:
        if pattern.lower() in prompt_text.lower():
            return True
    return False


def poll_updates() -> list:
    """텔레그램 업데이트 polling"""
    global update_offset
    resp = tg_request("getUpdates", {
        "offset": update_offset,
        "timeout": 1,  # 짧은 polling (메인 루프 블로킹 최소화)
    })
    if not resp.get("ok"):
        return []
    updates = resp.get("result", [])
    if updates:
        update_offset = updates[-1]["update_id"] + 1
    return updates


def process_callback(updates: list) -> Optional[str]:
    """callback_query에서 approve/deny 추출"""
    for update in updates:
        cb = update.get("callback_query")
        if not cb:
            continue
        data = cb.get("data", "")
        if data in ("approve", "deny"):
            answer_callback(cb["id"], "승인됨 ✅" if data == "approve" else "거부됨 ❌")
            return data
    return None


def handle_signal(sig, frame):
    global running
    log.info("Shutting down...")
    running = False


signal.signal(signal.SIGINT, handle_signal)
signal.signal(signal.SIGTERM, handle_signal)


def main():
    global pending_msg_id, pending_prompt_text, sent_hashes

    log.info(f"Telegram Guard 시작 — tmux 세션: {TMUX_SESSION}")
    send_simple(f"🟢 <b>Telegram Guard 시작</b>\ntmux 세션: <code>{TMUX_SESSION}</code>")

    # 시작 시 기존 업데이트 소비 (무시)
    poll_updates()

    pending_since = 0.0

    while running:
        try:
            # ── 대기 중인 프롬프트 응답 확인 ──
            if pending_msg_id:
                updates = poll_updates()
                action = process_callback(updates)

                if action:
                    if action == "approve":
                        send_keys("y")
                        log.info("승인 처리 완료")
                    else:
                        send_keys("n")
                        log.info("거부 처리 완료")
                    pending_msg_id = None
                    pending_prompt_text = ""
                    sent_hashes.clear()  # 다음 프롬프트 감지를 위해 리셋
                    time.sleep(3)  # 프롬프트 처리 후 잠시 대기
                    continue

                # 타임아웃 체크
                if time.time() - pending_since > TIMEOUT_SEC:
                    if TIMEOUT_ACTION == "approve":
                        send_keys("y")
                        send_simple("⏰ 타임아웃 — 자동 승인")
                    else:
                        send_keys("n")
                        send_simple("⏰ 타임아웃 — 자동 거부")
                    pending_msg_id = None
                    pending_prompt_text = ""
                    log.info(f"타임아웃 → {TIMEOUT_ACTION}")

                time.sleep(1)
                continue

            # ── tmux 출력 감시 ──
            output = get_tmux_output()
            if not output:
                time.sleep(POLL_INTERVAL)
                continue

            prompt = extract_prompt_context(output)
            if not prompt:
                time.sleep(POLL_INTERVAL)
                continue

            h = hash_text(prompt)
            if h in sent_hashes:
                time.sleep(POLL_INTERVAL)
                continue

            sent_hashes.add(h)

            # 자동 승인 체크
            if check_auto_approve(prompt):
                send_keys("y")
                log.info(f"자동 승인: {prompt[:50]}...")
                time.sleep(2)
                continue

            # 텔레그램 알림
            alert_text = (
                f"🔔 <b>Claude Code 권한 요청</b>\n\n"
                f"<code>{prompt[:500]}</code>\n\n"
                f"5분 내 응답 없으면 자동 {TIMEOUT_ACTION}"
            )
            msg_id = send_alert(alert_text)
            if msg_id:
                pending_msg_id = msg_id
                pending_prompt_text = prompt
                pending_since = time.time()
                log.info(f"텔레그램 알림 전송: {prompt[:50]}...")
            else:
                log.error("텔레그램 전송 실패")

        except Exception as e:
            log.error(f"메인 루프 에러: {e}")
            time.sleep(5)

    send_simple("🔴 <b>Telegram Guard 종료</b>")
    log.info("종료 완료")


if __name__ == "__main__":
    main()
