"""Split a spoken turn so DistilBERT can classify each question separately."""

from __future__ import annotations

import re

_SPLIT = re.compile(r"[?]+|\s+(?:and|also|plus)\s+", re.IGNORECASE)


def spoken_clauses(text: str) -> list[str]:
    parts = [re.sub(r"\s+", " ", piece).strip(" .,!") for piece in _SPLIT.split(text)]
    return [piece for piece in parts if len(piece) >= 4]
