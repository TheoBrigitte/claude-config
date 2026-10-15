#!/usr/bin/env -S uv run --script
# /// script
# requires-python = "==3.12.*"
# dependencies = ["faster-whisper", "numpy"]
# ///
"""Hands-free voice loop between a Meet tab and Claude.

Records meet_out.monitor, splits utterances on silence, transcribes them with
Whisper, sends them to a long-lived `claude -p` session and plays the reply
with piper into claude_out. Run bin/meet-audio.sh up first.

Env: MEET_MODEL, MEET_WHISPER, MEET_VOICE, MEET_THRESHOLD.
"""
import json
import os
import subprocess
import sys
import time

import numpy as np
from faster_whisper import WhisperModel

RATE = 16000
FRAME = RATE * 30 // 1000  # 30 ms
SILENCE_FRAMES = 17  # 500 ms of silence ends an utterance
MIN_FRAMES = 10  # drop blips under 300 ms
THRESHOLD = int(os.environ.get("MEET_THRESHOLD", "400"))  # int16 RMS
MODEL = os.environ.get("MEET_MODEL", "haiku")
VOICE = os.environ.get(
    "MEET_VOICE", "/usr/share/piper-voices/en/en_US/hfc_female/medium/en_US-hfc_female-medium.onnx"
)
SYSTEM = (
    "You are Claude, talking with Theo in a Google Meet call. "
    "Your words are spoken aloud by a text-to-speech voice. "
    "Answer in one to three short spoken sentences. "
    "No markdown, no lists, no code, no URLs. "
    "Input comes from speech recognition and may contain errors."
)


def log(msg):
    print(f"{time.strftime('%H:%M:%S')} {msg}", file=sys.stderr, flush=True)


def speaker():
    """Start piper and pw-play. Write one sentence per line to its stdin."""
    rate = "16000" if VOICE.endswith("-low.onnx") else "22050"
    piper = subprocess.Popen(
        ["piper-tts", "--model", VOICE, "--output-raw"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    play = subprocess.Popen(
        ["pw-play", "--target", "claude_out", "--raw", "--rate", rate, "--channels", "1", "--format", "s16", "-"],
        stdin=piper.stdout,
    )
    return piper, play


def reply(claude, piper):
    """Stream Claude's reply into piper, one sentence per line. Return the full text."""
    text, sent = "", 0
    while (event := json.loads(claude.stdout.readline()))["type"] != "result":
        delta = event.get("event", {}).get("delta", {})
        if delta.get("type") != "text_delta":
            continue
        if not text:
            log("claude: first token")
        text += delta["text"]
        end = max(text.rfind(c, sent) for c in ".!?")
        if end >= sent:
            piper.stdin.write(text[sent : end + 1].replace("\n", " ").strip().encode() + b"\n")
            piper.stdin.flush()
            sent = end + 1
    if text[sent:].strip():
        piper.stdin.write(text[sent:].replace("\n", " ").strip().encode() + b"\n")
        piper.stdin.flush()
    return text.strip()


def utterances(rec):
    voiced, silent = [], 0
    while chunk := rec.stdout.read(FRAME * 2):
        frame = np.frombuffer(chunk, dtype=np.int16)
        loud = np.sqrt(np.mean(frame.astype(np.float32) ** 2)) > THRESHOLD
        if loud:
            voiced.append(frame)
            silent = 0
        elif voiced:
            voiced.append(frame)
            silent += 1
            if silent >= SILENCE_FRAMES:
                if len(voiced) - silent >= MIN_FRAMES:
                    yield np.concatenate(voiced).astype(np.float32) / 32768
                voiced, silent = [], 0


def main():
    claude = subprocess.Popen(
        ["claude", "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
         "--include-partial-messages",
         "--model", MODEL, "--tools", "", "--strict-mcp-config", "--no-session-persistence",
         "--system-prompt", SYSTEM],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
    )
    name = os.environ.get("MEET_WHISPER", "base.en")
    try:
        whisper = WhisperModel(name, device="cpu", compute_type="int8", local_files_only=True)
    except Exception:
        log(f"downloading Whisper {name} from Hugging Face")
        whisper = WhisperModel(name, device="cpu", compute_type="int8")
    piper, _ = speaker()
    rec = subprocess.Popen(
        ["parecord", "--device=meet_out.monitor", "--raw", f"--rate={RATE}", "--channels=1", "--format=s16le"],
        stdout=subprocess.PIPE,
    )
    log("listening on meet_out.monitor")
    for audio in utterances(rec):
        log("heard utterance")
        segments, _ = whisper.transcribe(audio, language="en", beam_size=1)
        text = " ".join(s.text.strip() for s in segments).strip()
        if not text:
            continue
        log(f"you: {text}")
        claude.stdin.write(json.dumps({"type": "user", "message": {"role": "user", "content": text}}) + "\n")
        claude.stdin.flush()
        log(f"claude: {reply(claude, piper)}")


if __name__ == "__main__":
    main()
