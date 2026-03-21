"""
Google Cloud credential loading for local dev and cloud (Render, etc.).

- Prefer GOOGLE_APPLICATION_CREDENTIALS pointing to a service-account JSON file path.
- On platforms without a file mount, set GOOGLE_CREDENTIALS_JSON to the raw JSON
  (e.g. Render secret); a temp file is created and the env var is updated.
"""

from __future__ import annotations

import logging
import os
import tempfile

logger = logging.getLogger("linguacall.google_env")


def configure_google_application_credentials() -> None:
    path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
    if path and os.path.isfile(path):
        return

    raw = os.environ.get("GOOGLE_CREDENTIALS_JSON", "").strip()
    if raw:
        fd, tmp_path = tempfile.mkstemp(suffix=".json", text=True)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(raw)
        except Exception:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
            raise
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = tmp_path
        logger.info("Configured credentials from GOOGLE_CREDENTIALS_JSON (temp file).")
        return

    logger.warning(
        "Google credentials not configured. Set GOOGLE_APPLICATION_CREDENTIALS to a JSON "
        "file path, or GOOGLE_CREDENTIALS_JSON to the raw service account JSON."
    )
