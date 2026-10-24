"""NLU pipeline: spaCy → DistilBERT → Duckling."""

from __future__ import annotations

from models.intents import Intent
from models.nlu import NLUResult
from utils.config import Settings

from ai.nlu.clauses import spoken_clauses
from ai.nlu.distilbert_intent import DistilBertIntentClassifier
from ai.nlu.duckling_temporal import DucklingTemporalParser


class NLUPipeline:
    def __init__(self, settings: Settings) -> None:
        # Load spaCy only when the conversational pipeline is constructed, not
        # when lightweight API routes import the application.
        from ai.nlu.spacy_preprocessor import SpacyPreprocessor

        self.spacy = SpacyPreprocessor(settings)
        self.intent = DistilBertIntentClassifier(settings)
        self.duckling = DucklingTemporalParser(settings)

    def interpret(self, text: str) -> NLUResult:
        cleaned = " ".join(text.strip().split())
        primary = self._interpret_one(cleaned, raw_text=text)
        followups = [
            self._interpret_one(clause, raw_text=clause)
            for clause in spoken_clauses(cleaned)
            if clause.lower() != cleaned.lower()
        ]
        if primary.intent == Intent.UNKNOWN and followups:
            ranked = sorted(
                followups,
                key=lambda item: (item.intent != Intent.UNKNOWN, item.intent_confidence),
                reverse=True,
            )
            if ranked and ranked[0].intent != Intent.UNKNOWN:
                winner = ranked[0]
                return winner.model_copy(
                    update={
                        "raw_text": text,
                        "normalized_text": cleaned,
                        "followups": followups,
                    }
                )
        return primary.model_copy(update={"followups": followups})

    def _interpret_one(self, text: str, raw_text: str) -> NLUResult:
        spacy_view = self.spacy.analyze(text)
        intent, confidence = self.intent.predict(text)
        temporal = self.duckling.parse(text)
        people = self.spacy.person_mentions(spacy_view, text)
        return NLUResult(
            raw_text=raw_text,
            normalized_text=text,
            intent=intent,
            intent_confidence=confidence,
            spacy=spacy_view,
            temporal=temporal,
            person_mentions=people,
        )
