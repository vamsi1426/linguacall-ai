import os
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

from google_env import configure_google_application_credentials

# Import the strict production websocket pipeline
from translate_stream import translate_stream_websocket

# Load .env from ai_backend/ when present (local dev)
load_dotenv(Path(__file__).resolve().parent / ".env")

configure_google_application_credentials()

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
    port = int(os.environ.get("PORT", "8000"))
    reload = os.environ.get("UVICORN_RELOAD", "1") == "1"
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=reload)
