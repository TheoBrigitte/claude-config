#!/usr/bin/env -S uv run --script
# /// script
# requires-python = "==3.12.*"
# dependencies = ["faster-whisper", "numpy", "piper-tts"]
# ///
"""Hands-free voice loop between a Meet tab and Claude.

Records meet_out.monitor, splits utterances on silence, transcribes them with
Whisper, sends them to a long-lived `claude -p` session and plays the reply
with piper into claude_out. Speaking over Claude stops its reply.
Run bin/meet-audio.sh up first.

Env: MEET_MODEL, MEET_WHISPER, MEET_VOICE, MEET_THRESHOLD.
"""
import itertools
import json
import os
import queue
import subprocess
import sys
import threading
import time
from collections import deque

import numpy as np
from faster_whisper import WhisperModel
from piper import PiperVoice

RATE = 16000
FRAME = RATE * 30 // 1000  # 30 ms
SILENCE_FRAMES = 17  # 500 ms of silence ends an utterance
MIN_FRAMES = 10  # 300 ms of speech starts an utterance and interrupts Claude
LEAD = 0.15  # seconds of audio queued ahead of playback
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
    "Input comes from speech recognition and may contain errors. "
    "Theo can interrupt you while you speak."
)


def log(msg):
    print(f"{time.strftime('%H:%M:%S')} {msg}", file=sys.stderr, flush=True)


class Speaker:
    """Synthesizes queued sentences and plays them into claude_out. stop() drops the rest."""

    def __init__(self, voice):
        self.voice = voice
        self.rate = voice.config.sample_rate
        self.sentences = queue.Queue()
        self.generation = 0
        self.end = 0.0  # when the audio written so far finishes playing
        self.play = subprocess.Popen(
            ["pw-play", "--target", "claude_out", "--raw", "--rate", str(self.rate), "--channels", "1",
             "--format", "s16", "-"],
            stdin=subprocess.PIPE,
        )
        threading.Thread(target=self.run, daemon=True).start()

    def say(self, text):
        self.sentences.put((self.generation, text))

    def stop(self):
        self.generation += 1

    def busy(self):
        return time.monotonic() < self.end or not self.sentences.empty()

    def run(self):
        step = int(self.rate * 0.05) * 2  # 50 ms of s16 audio
        while True:
            gen, text = self.sentences.get()
            for chunk in self.voice.synthesize(text):
                data = chunk.audio_int16_bytes
                for i in range(0, len(data), step):
                    if gen != self.generation:
                        break
                    time.sleep(max(0, self.end - time.monotonic() - LEAD))
                    self.play.stdin.write(data[i : i + step])
                    self.play.stdin.flush()
                    self.end = max(self.end, time.monotonic()) + len(data[i : i + step]) / 2 / self.rate


class Claude:
    """Long-lived `claude -p` session. Streams each reply to the speaker one sentence at a time."""

    def __init__(self, speaker):
        self.speaker = speaker
        self.active = False
        self.cut = False
        self.ids = itertools.count()
        self.proc = subprocess.Popen(
            ["claude", "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
             "--include-partial-messages", "--model", MODEL, "--tools", "", "--strict-mcp-config",
             "--no-session-persistence", "--system-prompt", SYSTEM],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
        )
        threading.Thread(target=self.read, daemon=True).start()

    def write(self, message):
        self.proc.stdin.write(json.dumps(message) + "\n")
        self.proc.stdin.flush()

    def send(self, text):
        self.active = True
        self.write({"type": "user", "message": {"role": "user", "content": text}})

    def interrupt(self):
        self.cut = True
        self.write({"type": "control_request", "request_id": f"interrupt-{next(self.ids)}",
                    "request": {"subtype": "interrupt"}})

    def read(self):
        text, sent = "", 0
        for line in self.proc.stdout:
            event = json.loads(line)
            if event["type"] == "result":
                if text[sent:].strip() and not self.cut:
                    self.speaker.say(text[sent:].replace("\n", " ").strip())
                log(f"claude{' (cut off)' if self.cut else ''}: {text.strip()}")
                text, sent, self.active, self.cut = "", 0, False, False
                continue
            delta = event.get("event", {}).get("delta", {})
            if delta.get("type") != "text_delta" or self.cut:
                continue
            if not text:
                log("claude: first token")
            text += delta["text"]
            end = max(text.rfind(c, sent) for c in ".!?")
            if end >= sent:
                self.speaker.say(text[sent : end + 1].replace("\n", " ").strip())
                sent = end + 1


def listen(rec):
    """Yield ("start", None) after 300 ms of speech and ("end", audio) after the following silence."""
    voiced, silent, loud = [], 0, 0
    preroll = deque(maxlen=MIN_FRAMES)  # keeps quiet word onsets
    while chunk := rec.stdout.read(FRAME * 2):
        frame = np.frombuffer(chunk, dtype=np.int16)
        if np.sqrt(np.mean(frame.astype(np.float32) ** 2)) > THRESHOLD:
            if not voiced:
                voiced.extend(preroll)
            voiced.append(frame)
            silent = 0
            loud += 1
            if loud == MIN_FRAMES:
                yield "start", None
        elif voiced:
            voiced.append(frame)
            silent += 1
            if silent >= SILENCE_FRAMES:
                if loud >= MIN_FRAMES:
                    yield "end", np.concatenate(voiced).astype(np.float32) / 32768
                voiced, silent, loud = [], 0, 0
                preroll.clear()
        else:
            preroll.append(frame)


def main():
    name = os.environ.get("MEET_WHISPER", "base.en")
    try:
        whisper = WhisperModel(name, device="cpu", compute_type="int8", local_files_only=True)
    except Exception:
        log(f"downloading Whisper {name} from Hugging Face")
        whisper = WhisperModel(name, device="cpu", compute_type="int8")
    speaker = Speaker(PiperVoice.load(VOICE))
    claude = Claude(speaker)
    rec = subprocess.Popen(
        ["parecord", "--device=meet_out.monitor", "--raw", f"--rate={RATE}", "--channels=1", "--format=s16le"],
        stdout=subprocess.PIPE,
    )
    note = ""
    log("listening on meet_out.monitor")
    for kind, audio in listen(rec):
        if kind == "start":
            if claude.active or speaker.busy():
                log("interrupted")
                speaker.stop()
                if claude.active:
                    claude.interrupt()
                note = "(You were interrupted mid-reply.) "
            continue
        segments, _ = whisper.transcribe(audio, language="en", beam_size=1)
        text = " ".join(s.text.strip() for s in segments).strip()
        if not text:
            continue
        log(f"you: {text}")
        claude.send(note + text)
        note = ""


if __name__ == "__main__":
    main()
