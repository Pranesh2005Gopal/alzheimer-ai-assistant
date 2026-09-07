"""Duckling HTTP client for dates, times, and durations."""

from __future__ import annotations

import logging

import httpx

from models.nlu import TemporalEntity
from utils.config import Settings

logger = logging.getLogger(__name__)


class DucklingTemporalParser:
    def __init__(self, settings: Settings) -> None:
        self._url = settings.duckling_url.rstrip("/")

    def parse(self, text: str) -> list[TemporalEntity]:
        parse_url = f"{self._url}/parse"
        try:
            response = httpx.post(
                parse_url,
                data={"locale": "en_US", "text": text, "dims": '["time","duration","interval"]'},
                timeout=3.0,
            )
            response.raise_for_status()
            payload = response.json()
        except Exception as exc:
            logger.warning("Duckling is unreachable at %s: %s", parse_url, exc)
            return []

        entities: list[TemporalEntity] = []
        for row in payload:
            value = row.get("value") or {}
            entities.append(
                TemporalEntity(
                    dim=row.get("dim", "time"),
                    body=row.get("body", ""),
                    value=value.get("value") or value,
                    grain=value.get("grain"),
                )
            )
        return entities
