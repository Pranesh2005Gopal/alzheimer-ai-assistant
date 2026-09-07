"""NLU pipeline: spaCy → DistilBERT → Duckling."""

from __future__ import annotations

from models.nlu import NLUResult
from utils.config import Settings

from ai.nlu.distilbert_intent import DistilBertIntentClassifier
from ai.nlu.duckling_temporal import DucklingTemporalParser
from ai.nlu.spacy_preprocessor import SpacyPreprocessor


class NLUPipeline:
    def __init__(self, settings: Settings) -> None:
        self.spacy = SpacyPreprocessor(settings)
        self.intent = DistilBertIntentClassifier(settings)
        self.duckling = DucklingTemporalParser(settings)

    def interpret(self, text: str) -> NLUResult:
        cleaned = " ".join(text.strip().split())
        spacy_view = self.spacy.analyze(cleaned)
        intent, confidence = self.intent.predict(cleaned)
        temporal = self.duckling.parse(cleaned)
        people = self.spacy.person_mentions(spacy_view, cleaned)
        return NLUResult(
            raw_text=text,
            normalized_text=cleaned,
            intent=intent,
            intent_confidence=confidence,
            spacy=spacy_view,
            temporal=temporal,
            person_mentions=people,
        )
