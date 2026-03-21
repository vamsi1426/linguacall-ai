import os
import json
import asyncio
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

# Import the strict production websocket pipeline
from translate_stream import translate_stream_websocket

def _ensure_google_credentials() -> None:
    """
    Make local runs robust: if GOOGLE_APPLICATION_CREDENTIALS is missing or points
    to a bad path, fall back to ai_backend/google_key.json.
    """
    configured = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
    if configured and os.path.exists(configured):
        return

    fallback = os.path.join(os.path.dirname(__file__), "google_key.json")
    if os.path.exists(fallback):
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = fallback
        print(f"[startup] Using GOOGLE_APPLICATION_CREDENTIALS={fallback}")
    else:
        print(
            "[startup] WARNING: google_key.json not found and GOOGLE_APPLICATION_CREDENTIALS is invalid."
        )


_ensure_google_credentials()

app = FastAPI(title="LinguaCall AI Backend", description="Real-time translation stream")

# CORS middleware for flutter frontend (if using web)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def read_root():
    return {"status": "AI Translation Backend running"}

@app.websocket("/ws/translate")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("WebSocket connected for translation pipeline")
    
    # In a full GCP environment, we would initialize streaming recognize requests here
    # client_stt = speech.SpeechClient()
    # client_translate = translate.Client()
    # client_tts = texttospeech.TextToSpeechClient()
    
    try:
        while True:
            # Wait for data from the client (audio bytes in 1s chunks ideally)
            data = await websocket.receive_bytes()
            
            # --- START AI PIPELINE LOGIC (Pseudocode/Placeholder) ---
            # 1. Provide chunk to STT streaming pipeline
            # text_original = stream_stt(data)
            text_original = "mock transcribed text"  # Replace with actual STT
            
            # 2. Translate text (e.g. client sends target config at start of connection)
            # text_translated = client_translate.translate(text_original, target_language="es")
            text_translated = "texto traducido de prueba"
            
            # 3. Text to Speech
            # audio_response = stream_tts(text_translated)
            audio_response = b"mock audio byte stream"
            
            # Send the translated audio chunk back immediately
            # Use JSON to send metadata along with base64 audio, or just binary
            # Here sending simulated binary audio back
            await websocket.send_bytes(audio_response)
            
            # Small artificial delay simulating pipeline latency for dummy code processing
            # asyncio.sleep(0.01)

    except WebSocketDisconnect:
        print("WebSocket disconnected")
    except Exception as e:
        print(f"Error in translation pipeline: {e}")


@app.websocket("/ws/translate-stream")
async def websocket_translate_stream(websocket: WebSocket):
    """
    Production websocket contract endpoint used by the Flutter client.
    """
    await translate_stream_websocket(websocket)

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
