import asyncio
import json
import logging
import queue
import threading
import time
from dataclasses import dataclass
from typing import Optional

from fastapi import WebSocket, WebSocketDisconnect

from google.cloud import speech
from google.cloud import translate_v2 as translate
from google.cloud import texttospeech
from google.api_core.exceptions import OutOfRange
from google.cloud.speech_v1.services.speech.client import SpeechClient as GapicSpeechClient

from audio_utils import pcm16le_to_wav_bytes
from google_env import configure_google_application_credentials

logger = logging.getLogger("linguacall.translate_stream")


def _is_stt_max_stream_duration_error(exc: BaseException) -> bool:
    """Google STT ends each streaming RPC after ~305s; we must open a new session."""
    msg = str(exc).lower()
    return (
        "exceeded maximum allowed stream duration" in msg
        or "maximum allowed stream duration" in msg
    )


def _normalize_lang_code(code: Optional[str]) -> str:
    """
    Map short and full client language codes.

    Required:
    - te -> te-IN
    - en -> en-US
    - Handle both short and full codes.
    """
    if not code:
        # Safe default.
        return "en-US"

    c = code.strip()
    lc = c.lower()

    if lc.startswith("te"):
        return "te-IN"
    if lc.startswith("en"):
        return "en-US"

    # If it's already full (e.g. "te-IN"), keep it.
    # Otherwise fall back to what was provided.
    return c


def _short_lang_for_translate(speech_locale: str) -> str:
    """
    Cloud Translation API v2 expects ISO 639-1 codes (e.g. te, en), not BCP-47 locales.
    """
    lc = speech_locale.strip().lower()
    if lc.startswith("te"):
        return "te"
    if lc.startswith("en"):
        return "en"
    if "-" in speech_locale:
        return speech_locale.split("-", 1)[0].lower()
    return lc or "en"


def _tts_voice_language_code(speech_locale: str) -> str:
    """TTS voice selection uses BCP-47 style codes (e.g. en-US, te-IN)."""
    return _normalize_lang_code(speech_locale)


@dataclass(frozen=True)
class TranslationSessionConfig:
    source_lang: str
    target_lang: str
    enabled: bool
    interim_throttle_seconds: float


def _run_translation_worker(
    *,
    pcm_queue: "queue.Queue[Optional[bytes]]",
    stop_event: threading.Event,
    config: TranslationSessionConfig,
    loop: asyncio.AbstractEventLoop,
    websocket: WebSocket,
) -> None:
    """
    Runs Google Speech->Translate->TTS in a background thread.

    It reads PCM16 audio from pcm_queue and sends binary WAV bytes back to the client
    using the websocket bound to the main event loop (via run_coroutine_threadsafe).
    """
    if not config.enabled:
        logger.info("Translation disabled; worker will drain audio only.")

    configure_google_application_credentials()

    speech_client = speech.SpeechClient()
    translate_client = translate.Client()
    tts_client = texttospeech.TextToSpeechClient()

    logger.info(
        "Worker started: STT pipeline ready (source=%s target=%s enabled=%s)",
        config.source_lang,
        config.target_lang,
        config.enabled,
    )

    # Google Speech streaming config.
    recognition_config = speech.RecognitionConfig(
        encoding=speech.RecognitionConfig.AudioEncoding.LINEAR16,
        sample_rate_hertz=16000,
        language_code=config.source_lang,
        audio_channel_count=1,
        enable_automatic_punctuation=True,
        # model can be tuned for latency; default is generally safe.
    )
    streaming_config = speech.StreamingRecognitionConfig(
        config=recognition_config,
        interim_results=True,
        single_utterance=False,
    )

    last_sent_at = 0.0
    last_sent_text = None  # type: Optional[str]

    # Google streaming STT requires audio near real time; long idle gaps raise:
    # OUT_OF_RANGE "Audio Timeout Error: Long duration elapsed without audio."
    # When the client has not yet sent the next mic chunk, feed PCM16 silence.
    _sr_hz = 16000
    _bytes_per_sample = 2
    _silence_ms = 100
    _silence_chunk = b"\x00" * (
        _sr_hz * _bytes_per_sample * _silence_ms // 1000
    )

    wav_out_count = 0
    stt_trace = {"first_transcript": False, "response_count": 0}

    def safe_send(wav_bytes: bytes) -> None:
        nonlocal wav_out_count
        wav_out_count += 1
        if wav_out_count <= 10 or wav_out_count % 25 == 0:
            logger.info(
                "Sending translated audio chunk #%s (%s bytes WAV)",
                wav_out_count,
                len(wav_bytes),
            )
        fut = asyncio.run_coroutine_threadsafe(websocket.send_bytes(wav_bytes), loop)

        def _log_done(f: "asyncio.Future[object]") -> None:
            try:
                f.result()
            except Exception as e:
                logger.warning("Failed sending translated WAV chunk: %s", e)

        fut.add_done_callback(_log_done)

    def process_response(response: speech.StreamingRecognizeResponse) -> None:
        nonlocal last_sent_at, last_sent_text

        if not response.results:
            return

        result = response.results[0]
        if not result.alternatives:
            return

        transcript = result.alternatives[0].transcript.strip()
        if not transcript:
            return

        now = time.time()
        is_final = bool(result.is_final)

        # Throttle interim results to ~750ms to keep playback near real-time.
        if not is_final:
            if (now - last_sent_at) < config.interim_throttle_seconds:
                return
            # Avoid re-sending identical partial text.
            if last_sent_text is not None and transcript == last_sent_text:
                return

        if not config.enabled:
            return

        last_sent_at = now
        last_sent_text = transcript

        try:
            src_tr = _short_lang_for_translate(config.source_lang)
            tgt_tr = _short_lang_for_translate(config.target_lang)
            translation = translate_client.translate(
                transcript,
                target_language=tgt_tr,
                source_language=src_tr,
            )
            translated_text = translation.get("translatedText", "").strip()
            if not translated_text:
                logger.warning(
                    "Translate returned empty text (src=%r len=%s)",
                    transcript[:120],
                    len(transcript),
                )
                return

            synthesis_input = texttospeech.SynthesisInput(text=translated_text)
            voice = texttospeech.VoiceSelectionParams(
                language_code=_tts_voice_language_code(config.target_lang),
                ssml_gender=texttospeech.SsmlVoiceGender.NEUTRAL,
            )
            audio_config = texttospeech.AudioConfig(
                audio_encoding=texttospeech.AudioEncoding.LINEAR16,
                sample_rate_hertz=16000,
                speaking_rate=1.0,
            )

            tts_response = tts_client.synthesize_speech(
                input=synthesis_input,
                voice=voice,
                audio_config=audio_config,
            )

            pcm16 = tts_response.audio_content  # raw PCM16 bytes (little-endian)
            wav_bytes = pcm16le_to_wav_bytes(pcm16, sample_rate_hz=16000, channels=1)

            safe_send(wav_bytes)
        except Exception as e:
            logger.exception("Pipeline error (translate+tts): %s", e)

    try:
        # Google limits each StreamingRecognize RPC to ~305s; open a new session when needed.
        session_index = 0
        while not stop_event.is_set():
            session_index += 1

            def streaming_requests():
                yield speech.StreamingRecognizeRequest(streaming_config=streaming_config)
                while not stop_event.is_set():
                    try:
                        chunk = pcm_queue.get(timeout=0.2)
                    except queue.Empty:
                        yield speech.StreamingRecognizeRequest(audio_content=_silence_chunk)
                        continue
                    if chunk is None:
                        return
                    yield speech.StreamingRecognizeRequest(audio_content=chunk)

            try:
                logger.info("Starting STT streaming session #%s", session_index)
                responses = GapicSpeechClient.streaming_recognize(
                    speech_client,
                    requests=streaming_requests(),
                )
                for response in responses:
                    if stop_event.is_set():
                        break
                    process_response(response)
            except OutOfRange as e:
                if _is_stt_max_stream_duration_error(e):
                    logger.info(
                        "STT session #%s hit max duration; starting new stream: %s",
                        session_index,
                        e,
                    )
                    continue
                logger.warning("Streaming STT stopped (OutOfRange): %s", e)
                break
            except Exception as e:
                logger.exception("STT streaming session #%s error: %s", session_index, e)
                break
    except Exception as e:
        logger.exception("Worker crashed: %s", e)
    finally:
        # Stop the websocket safely from the receiver side. We don't close it here.
        logger.info("Translation worker exiting.")


async def translate_stream_websocket(websocket: WebSocket) -> None:
    """
    WebSocket contract for `/ws/translate-stream`:
      1) Receive a JSON text message:
         { "type": "start", "source": "te-IN", "target": "en-US", "translate": true }
         (also accepts "enabled": true)
      2) Then receive binary PCM16 16kHz mono chunks indefinitely.
      3) Send ONLY binary WAV bytes back after each STT->Translate->TTS pipeline step.
    """
    await websocket.accept()
    # Always visible on hosts that don't propagate app loggers to stdout.
    print("linguacall: translate-stream WebSocket accepted", flush=True)
    logger.info("WebSocket accepted: /ws/translate-stream")

    stop_event = threading.Event()
    pcm_queue: "queue.Queue[Optional[bytes]]" = queue.Queue(maxsize=100)

    worker_task = None
    loop = asyncio.get_running_loop()
    no_pcm_warn_task: Optional[asyncio.Task] = None

    try:
        try:
            start_text = await asyncio.wait_for(websocket.receive_text(), timeout=15.0)
        except asyncio.TimeoutError:
            logger.warning("No start JSON received within 15s after accept; closing")
            await websocket.close(code=1008)
            return

        logger.info(
            "Received start JSON: %s",
            start_text[:800] + ("…" if len(start_text) > 800 else ""),
        )

        try:
            start = json.loads(start_text)
        except json.JSONDecodeError as e:
            logger.warning("Invalid start JSON: %s", e)
            await websocket.close(code=1003)
            return

        if start.get("type") != "start":
            await websocket.close(code=1003)
            return

        source_raw = start.get("source")
        target_raw = start.get("target")

        enabled = start.get("enabled", None)
        if enabled is None:
            # Fallback support.
            enabled = start.get("translate", True)

        config = TranslationSessionConfig(
            source_lang=_normalize_lang_code(source_raw),
            target_lang=_normalize_lang_code(target_raw),
            enabled=bool(enabled),
            interim_throttle_seconds=0.75,
        )

        # Start background worker in a thread (STT+Translate+TTS are synchronous).
        worker_task = asyncio.create_task(
            asyncio.to_thread(
                _run_translation_worker,
                pcm_queue=pcm_queue,
                stop_event=stop_event,
                config=config,
                loop=loop,
                websocket=websocket,
            )
        )

        pcm_stats = {"received": 0}

        async def _warn_no_pcm_soon() -> None:
            await asyncio.sleep(5.0)
            if pcm_stats["received"] == 0 and not stop_event.is_set():
                logger.warning(
                    "No PCM bytes received from client after 5s (session still open; check client mic)",
                )

        no_pcm_warn_task = asyncio.create_task(_warn_no_pcm_soon())

        # Drain loop: non-blocking (enqueue only).
        while True:
            pcm_chunk = await websocket.receive_bytes()
            if stop_event.is_set():
                break
            pcm_stats["received"] += 1
            n = pcm_stats["received"]
            if n <= 3 or n % 100 == 0:
                logger.info("Received PCM chunk #%s size=%s", n, len(pcm_chunk))
            try:
                pcm_queue.put_nowait(pcm_chunk)
            except queue.Full:
                # If the worker lags, drop old audio to keep latency low.
                _ = pcm_queue.get_nowait()
                pcm_queue.put_nowait(pcm_chunk)

    except WebSocketDisconnect:
        logger.info("Client disconnected.")
    except Exception as e:
        logger.exception("WebSocket session error: %s", e)
    finally:
        if no_pcm_warn_task is not None and not no_pcm_warn_task.done():
            no_pcm_warn_task.cancel()
        stop_event.set()
        try:
            pcm_queue.put_nowait(None)
        except Exception:
            pass
        if worker_task is not None:
            try:
                await worker_task
            except Exception:
                pass

