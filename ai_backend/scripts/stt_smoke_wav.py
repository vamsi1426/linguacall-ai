#!/usr/bin/env python3
"""
Batch STT smoke test: same RecognitionConfig shape as translate_stream (LINEAR16 16kHz mono).

Usage (from repo root or ai_backend):
  python scripts/stt_smoke_wav.py path/to/sample.wav --lang en-US

Requires GOOGLE_APPLICATION_CREDENTIALS or GOOGLE_CREDENTIALS_JSON (see google_env.py).
WAV must be 16-bit PCM mono 16 kHz (export from Audacity or ffmpeg).
"""

from __future__ import annotations

import argparse
import sys
import wave
from pathlib import Path

# Allow importing ai_backend modules when run as `python scripts/stt_smoke_wav.py`
_ROOT = Path(__file__).resolve().parent.parent
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from google.cloud import speech  # noqa: E402

from google_env import configure_google_application_credentials  # noqa: E402


def main() -> None:
    p = argparse.ArgumentParser(description="Run Google STT on a WAV file (offline credential check).")
    p.add_argument("wav", type=Path, help="16 kHz mono PCM16 WAV")
    p.add_argument("--lang", default="en-US", help="Language code (e.g. en-US, te-IN)")
    args = p.parse_args()

    if not args.wav.is_file():
        print(f"File not found: {args.wav}", file=sys.stderr)
        sys.exit(1)

    configure_google_application_credentials()

    with wave.open(str(args.wav), "rb") as wf:
        ch = wf.getnchannels()
        sw = wf.getsampwidth()
        rate = wf.getframerate()
        if ch != 1 or sw != 2 or rate != 16000:
            print(
                f"Expected 16-bit mono 16 kHz; got channels={ch} width={sw} rate={rate}",
                file=sys.stderr,
            )
            sys.exit(1)
        content = wf.readframes(wf.getnframes())

    client = speech.SpeechClient()
    audio = speech.RecognitionAudio(content=content)
    config = speech.RecognitionConfig(
        encoding=speech.RecognitionConfig.AudioEncoding.LINEAR16,
        sample_rate_hertz=16000,
        language_code=args.lang,
        audio_channel_count=1,
        enable_automatic_punctuation=True,
    )

    print("Recognizing…")
    resp = client.recognize(config=config, audio=audio)
    if not resp.results:
        print("No results — silence, wrong format, or STT could not decode.")
        sys.exit(2)

    for r in resp.results:
        for a in r.alternatives:
            conf = getattr(a, "confidence", None)
            print(f"transcript={a.transcript!r} confidence={conf}")


if __name__ == "__main__":
    main()
