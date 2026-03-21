# LinguaCall AI Backend (Real-time Translation)

This backend implements a WebSocket endpoint for real-time voice translation:

- `GET /` health check
- `WebSocket /ws/translate-stream` (client contract used by the Flutter app)

## Features

- Per-connection session
- Streaming Speech-to-Text -> Google Translate -> Text-to-Speech
- Sends **ONLY binary WAV audio bytes** after the initial JSON `start` message
- Non-blocking WebSocket receiver loop (audio enqueued; STT/Translate/TTS runs in a background worker)

## Setup

1. Create and activate a Python virtual environment

   - Windows (PowerShell):
     - `py -m venv .venv`
     - `.\.venv\Scripts\Activate.ps1`

2. Install dependencies

   - `pip install -r requirements.txt`

3. Configure Google Cloud credentials

   - Create a Service Account JSON key in Google Cloud
   - Enable APIs:
     - Speech-to-Text
     - Cloud Translation
     - Text-to-Speech
   - Set environment variable:
     - `set GOOGLE_APPLICATION_CREDENTIALS=C:\path\to\service-account.json`

   On Linux/macOS:
   - `export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json`

## Run

From the `ai_backend/` directory:

- `uvicorn main:app --host 0.0.0.0 --port 8000 --reload`

Health check:
- `http://localhost:8000/`

WebSocket:
- `ws://<host>:8000/ws/translate-stream`

## WebSocket Contract

1. First message (TEXT/JSON):

```json
{
  "type": "start",
  "source": "te-IN",
  "target": "en-US",
  "translate": true
}
```

This endpoint also accepts:
- `"enabled"` (primary) OR `"translate"` (fallback)

Language mapping supported:
- `te` -> `te-IN`
- `en` -> `en-US`

2. Second message onward (BINARY):
- PCM16 audio stream
- 16kHz, mono, little-endian

3. Server responses:
- ONLY BINARY WAV bytes (no JSON after start)
- Each response is a valid WAV chunk playable by the Flutter client

## Test (WebSocket client)

Run:

- `python test_ws_translate_stream.py`

This script sends:
- a start JSON message
- a short PCM16 silence stream in 500ms chunks

Because Speech recognition may not return meaningful transcripts for silence,
your server should still stay alive and correctly respond (or respond with no audio chunks).

