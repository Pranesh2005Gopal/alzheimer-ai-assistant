"""
Isolation Forest for unusual activity patterns (Phase 7).

This module must never be used to diagnose Alzheimer's disease
or make any medical claim. It only flags unusual activity counts/times.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np


@dataclass
class AnomalyVerdict:
    unusual: bool
    score: float
    message: str


class ActivityIsolationForest:
    def __init__(self, contamination: float = 0.1) -> None:
        self._contamination = contamination
        self._model = None

    def fit(self, feature_rows: list[list[float]]) -> None:
        from sklearn.ensemble import IsolationForest

        self._model = IsolationForest(contamination=self._contamination, random_state=42)
        self._model.fit(np.asarray(feature_rows, dtype=float))

    def score_one(self, features: list[float]) -> AnomalyVerdict:
        if self._model is None:
            return AnomalyVerdict(False, 0.0, "Anomaly model is not trained yet.")
        value = np.asarray([features], dtype=float)
        pred = int(self._model.predict(value)[0])
        score = float(self._model.decision_function(value)[0])
        unusual = pred == -1
        message = "Unusual activity detected." if unusual else "Activity looks within the usual range."
        return AnomalyVerdict(unusual=unusual, score=score, message=message)
