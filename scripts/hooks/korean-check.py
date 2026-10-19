#!/usr/bin/env python3
"""Stop 훅: 마지막 답변이 영어 위주면 막고 한국어로 다시 쓰게 한다.
코드 블록, 인라인 코드, 링크 주소는 세지 않는다."""
import json, re, sys

def is_user_prompt(e):
    """도구 결과가 아니라 사용자가 직접 보낸 메시지인지"""
    if e.get("type") != "user":
        return False
    c = (e.get("message") or {}).get("content")
    if isinstance(c, str):
        return bool(c.strip())
    if isinstance(c, list):
        return any(isinstance(x, dict) and x.get("type") == "text" for x in c)
    return False

def last_assistant_text(path):
    """사용자의 마지막 메시지 뒤에 쓴 답변만 본다.
    훅이 도는 시점엔 방금 끝낸 답변이 아직 파일에 없을 수 있어서, 그 전 답변으로 잘못 판단하지 않게."""
    text = ""
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                e = json.loads(line)
            except Exception:
                continue
            if is_user_prompt(e):
                text = ""
                continue
            if e.get("type") != "assistant":
                continue
            content = (e.get("message") or {}).get("content") or []
            parts = [c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text"]
            if parts:
                text = "\n".join(parts)
    return text

def main():
    data = json.load(sys.stdin)
    path = data.get("transcript_path")
    if not path:
        return
    text = last_assistant_text(path)
    text = re.sub(r"```.*?```", " ", text, flags=re.S)
    text = re.sub(r"`[^`]*`", " ", text)
    text = re.sub(r"https?://\S+", " ", text)
    hangul = len(re.findall(r"[가-힣]", text))
    latin = len(re.findall(r"[A-Za-z]", text))
    if latin < 60:
        return
    if hangul / (hangul + latin) >= 0.35:
        return
    if data.get("stop_hook_active"):
        return  # 다시 써도 안 되면 무한 반복하지 않는다
    print(json.dumps({
        "decision": "block",
        "reason": "마지막 답변이 영어로 쓰였어요. 프로젝트 규칙(CLAUDE.md: 모든 답변은 무조건 한국어)에 따라 같은 내용을 한국어로 다시 써서 답하세요."
    }, ensure_ascii=False))

main()
