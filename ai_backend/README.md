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
   - **Local file path (recommended for dev):**
     - Windows: `set GOOGLE_APPLICATION_CREDENTIALS=C:\path\to\service-account.json`
     - Linux/macOS: `export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json`
   - Or copy `ai_backend/.env.example` to `ai_backend/.env` and set variables there.
   - **Cloud (Render, etc.):** set secret `GOOGLE_CREDENTIALS_JSON` to the **full JSON string** of the service account (no repo file needed).

## Run

From the `ai_backend/` directory:

- `uvicorn main:app --host 0.0.0.0 --port 8000` (listens on all interfaces; use `--reload` only when `UVICORN_RELOAD=1`)
- Or: `set PORT=8000` / `export PORT=8000` then `uvicorn main:app --host 0.0.0.0 --port %PORT%` (Render sets `PORT` automatically).

## Deploy (Render)

1. In the repo root, use `render.yaml` (Blueprint) or create two **Web** services manually.
2. **Python service:** root directory `ai_backend`, build `pip install -r requirements.txt`, start `uvicorn main:app --host 0.0.0.0 --port $PORT`, set `UVICORN_RELOAD=0`, add `GOOGLE_CREDENTIALS_JSON` (secret) or mount credentials.
3. Public URL will be `https://<name>.onrender.com`; WebSocket for clients: `wss://<name>.onrender.com/ws/translate-stream`.
4. Flutter production build: pass `--dart-define=LINGUA_PROFILE=prod` and `--dart-define=LINGUA_TRANSLATE_WS=wss://...` (see `lingua_call/lib/config/app_config.dart`).

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

