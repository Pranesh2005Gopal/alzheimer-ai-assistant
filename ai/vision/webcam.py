"""Grab one webcam still with ffmpeg (already required for voice). No extra packages."""

from __future__ import annotations

import glob
import logging
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

logger = logging.getLogger(__name__)


def capture_jpeg_bytes() -> bytes:
    if shutil.which("ffmpeg") is None:
        raise RuntimeError("ffmpeg is required to capture the webcam.")
    devices = sorted(glob.glob("/dev/video*"))
    if not devices:
        raise RuntimeError("No webcam was found.")
    errors: list[str] = []
    for device in devices:
        try:
            data = _grab(device)
            if data:
                return data
        except Exception as exc:
            errors.append(f"{device}: {exc}")
    raise RuntimeError("Could not capture a webcam photo. " + "; ".join(errors[:3]))


def _grab(device: str) -> bytes:
    fd, name = tempfile.mkstemp(suffix=".jpg")
    os.close(fd)
    dest = Path(name)
    try:
        command = [
            "ffmpeg",
            "-y",
            "-hide_banner",
            "-loglevel",
            "error",
            "-f",
            "v4l2",
            "-video_size",
            "640x480",
            "-i",
            device,
            "-frames:v",
            "1",
            str(dest),
        ]
        subprocess.run(command, check=True, capture_output=True, timeout=8)
        data = dest.read_bytes()
        if len(data) < 100:
            raise RuntimeError("empty frame")
        return data
    finally:
        dest.unlink(missing_ok=True)
