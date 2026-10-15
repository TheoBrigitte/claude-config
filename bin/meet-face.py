#!/usr/bin/env -S uv run --script
# /// script
# requires-python = "==3.12.*"
# dependencies = ["numpy", "pillow"]
# ///
"""Talking face for Claude's Meet tab.

Renders the Claude logo on a dark background. The logo pulses and spins with
the audio level on claude_out.monitor. Frames stream through ffmpeg to a
v4l2loopback device, which the Meet tab uses as its camera.

Env: MEET_CAMERA (default /dev/video10), MEET_LOGO.
"""
import io
import os
import subprocess
import threading
import time
from pathlib import Path

import numpy as np
from PIL import Image

WIDTH, HEIGHT, FPS = 640, 360, 15
SIZE = 180  # logo size in pixels at rest
BACKGROUND = (38, 38, 36)
CAMERA = os.environ.get("MEET_CAMERA", "/dev/video10")
LOGO = os.environ.get("MEET_LOGO", str(Path(__file__).resolve().parent.parent / ".claude/claude-color.svg"))
RATE = 16000

level = 0.0


def listen():
    """Track the smoothed audio level of claude_out.monitor in [0, 1]."""
    global level
    rec = subprocess.Popen(
        ["parecord", "--device=claude_out.monitor", "--raw", f"--rate={RATE}", "--channels=1", "--format=s16le"],
        stdout=subprocess.PIPE,
    )
    while chunk := rec.stdout.read(RATE // FPS * 2):
        frame = np.frombuffer(chunk, dtype=np.int16).astype(np.float32)
        target = min(1.0, np.sqrt(np.mean(frame**2)) / 4000)
        # Fast attack, slow release.
        level += (target - level) * (0.7 if target > level else 0.25)


def main():
    png = subprocess.run(
        ["rsvg-convert", "-w", str(SIZE * 2), "-h", str(SIZE * 2), LOGO], capture_output=True, check=True
    ).stdout
    logo = Image.open(io.BytesIO(png)).convert("RGBA")
    threading.Thread(target=listen, daemon=True).start()
    ffmpeg = subprocess.Popen(
        ["ffmpeg", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{WIDTH}x{HEIGHT}",
         "-r", str(FPS), "-i", "-", "-f", "v4l2", "-pix_fmt", "yuv420p", CAMERA],
        stdin=subprocess.PIPE,
    )
    angle, tick = 0.0, 0
    while True:
        start = time.monotonic()
        tick += 1
        angle -= level * 12
        breath = 0.03 * np.sin(tick / FPS * 2)  # slow idle breathing
        size = int(SIZE * (1 + breath + 0.4 * level))
        sprite = logo.resize((size, size), Image.LANCZOS).rotate(angle, resample=Image.BICUBIC, expand=True)
        frame = Image.new("RGB", (WIDTH, HEIGHT), BACKGROUND)
        frame.paste(sprite, ((WIDTH - sprite.width) // 2, (HEIGHT - sprite.height) // 2), sprite)
        ffmpeg.stdin.write(frame.tobytes())
        time.sleep(max(0, 1 / FPS - (time.monotonic() - start)))


if __name__ == "__main__":
    main()
