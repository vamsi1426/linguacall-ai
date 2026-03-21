import struct


def pcm16le_to_wav_bytes(pcm16le_bytes: bytes, *, sample_rate_hz: int, channels: int = 1) -> bytes:
    """
    Wrap raw 16-bit PCM (little-endian) into a valid WAV container.

    This is required because the Flutter client expects WAV bytes and decodes RIFF/WAVE chunks.
    """
    if channels < 1:
        raise ValueError("channels must be >= 1")
    if sample_rate_hz <= 0:
        raise ValueError("sample_rate_hz must be > 0")

    bits_per_sample = 16
    byte_rate = sample_rate_hz * channels * bits_per_sample // 8
    block_align = channels * bits_per_sample // 8
    data_size = len(pcm16le_bytes)

    # RIFF chunk size excludes the first 8 bytes ("RIFF" + size field)
    riff_chunk_size = 36 + data_size

    header = struct.pack(
        "<4sI4s"  # ChunkID, ChunkSize, Format
        "4sI"     # Subchunk1ID ("fmt "), Subchunk1Size
        "HHIIHH"  # AudioFormat, NumChannels, SampleRate, ByteRate, BlockAlign, BitsPerSample
        "4sI",     # Subchunk2ID ("data"), Subchunk2Size
        b"RIFF",
        riff_chunk_size,
        b"WAVE",
        b"fmt ",
        16,
        1,  # PCM
        channels,
        sample_rate_hz,
        byte_rate,
        block_align,
        bits_per_sample,
        b"data",
        data_size,
    )

    return header + pcm16le_bytes

