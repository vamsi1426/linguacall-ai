import argparse
import asyncio
import json
import os
import wave
from typing import Optional

import websockets


def wav_to_pcm16_bytes(wav_path: str) -> bytes:
    """
    Extract raw PCM16 little-endian mono audio bytes from a WAV file.
    """
    with wave.open(wav_path, "rb") as wf:
        if wf.getnchannels() != 1:
            raise ValueError("Test WAV must be mono (1 channel).")
        if wf.getsampwidth() != 2:
            raise ValueError("Test WAV must be 16-bit PCM (2 bytes per sample).")
        return wf.readframes(wf.getnframes())


async def run_test(
    ws_url: str,
    *,
    source: str,
    target: str,
    translate_enabled: bool,
    wav_pcm_path: Optional[str],
    out_dir: str,
    wait_seconds: int,
    max_chunks: int,
) -> None:
    os.makedirs(out_dir, exist_ok=True)

    start_payload = {
        "type": "start",
        "source": source,
        "target": target,
        "translate": translate_enabled,
    }

    async with websockets.connect(ws_url, max_size=None) as ws:
        await ws.send(json.dumps(start_payload))

        if wav_pcm_path:
            pcm_bytes = wav_to_pcm16_bytes(wav_pcm_path)
        else:
            # 2 seconds of silence at 16kHz PCM16 mono.
            # 2.0s * 16000 samples/sec * 2 bytes/sample = 64000 bytes
            pcm_bytes = bytes(2 * 16000 * 2)

        # Send 500ms chunks (matches Flutter client chunking).
        chunk_size = 16000 * 1 // 2  # placeholder; corrected below
        # 500ms => 8000 samples at 16kHz => 16000 bytes
        chunk_size = 16000

        for i in range(0, len(pcm_bytes), chunk_size):
            await ws.send(pcm_bytes[i : i + chunk_size])

        # Try to read translated WAV chunks.
        received = 0
        deadline = asyncio.get_running_loop().time() + wait_seconds
        idx = 0
        while received < max_chunks and asyncio.get_running_loop().time() < deadline:
            # Use a short per-recv timeout so we can re-check the deadline.
            try:
                data = await asyncio.wait_for(ws.recv(), timeout=10)
            except asyncio.TimeoutError:
                print("Still waiting for translated audio (no chunks yet)...")
                idx += 1
                continue

            if isinstance(data, (bytes, bytearray)):
                out_path = os.path.join(out_dir, f"chunk_{received:03d}.wav")
                with open(out_path, "wb") as f:
                    f.write(data)
                print("Saved:", out_path, "len=", len(data))
                received += 1
            else:
                # This test expects ONLY binary audio after start.
                print("Received non-binary data (unexpected):", data)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ws-url", default="ws://127.0.0.1:8000/ws/translate-stream")
    parser.add_argument("--source", default="te")
    parser.add_argument("--target", default="en")
    parser.add_argument("--out-dir", default="./ws_out")
    parser.add_argument("--wav-pcm16-mono", default=None, help="Optional mono PCM16 WAV file path.")
    parser.add_argument("--wait-seconds", type=int, default=60)
    parser.add_argument("--max-chunks", type=int, default=5)
    args = parser.parse_args()

    asyncio.run(
        run_test(
            args.ws_url,
            source=args.source,
            target=args.target,
            translate_enabled=True,
            wav_pcm_path=args.wav_pcm16_mono,
            out_dir=args.out_dir,
            wait_seconds=args.wait_seconds,
            max_chunks=args.max_chunks,
        )
    )


if __name__ == "__main__":
    main()

