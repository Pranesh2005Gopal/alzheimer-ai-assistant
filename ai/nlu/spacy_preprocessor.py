"""spaCy preprocessing and entity extraction. Does not classify intent."""

from __future__ import annotations

import re

import spacy

from models.nlu import SpacyDocumentView
from utils.config import Settings


class SpacyPreprocessor:
    def __init__(self, settings: Settings) -> None:
        self._model_name = settings.spacy_model
        self._nlp = None

    def load(self) -> None:
        if self._nlp is not None:
            return
        self._nlp = spacy.load(self._model_name)

    def analyze(self, text: str) -> SpacyDocumentView:
        self.load()
        assert self._nlp is not None
        doc = self._nlp(text)
        return SpacyDocumentView(
            tokens=[t.text for t in doc],
            lemmas=[t.lemma_ for t in doc],
            entities=[{"text": ent.text, "label": ent.label_} for ent in doc.ents],
        )

    def person_mentions(self, view: SpacyDocumentView, text: str) -> list[str]:
        names = [e["text"] for e in view.entities if e["label"] in {"PERSON", "ORG"}]
        # Also surface capitalized tokens that spaCy may miss in short questions.
        for token in view.tokens:
            if token[:1].isupper() and token.lower() not in {"i", "who", "what", "when", "where"}:
                if token not in names:
                    names.append(token)
        match = re.search(r"\bwho is\s+(?:my\s+)?([A-Za-z][A-Za-z.'\-]*)", text, flags=re.IGNORECASE)
        if match:
            token = match.group(1).strip()
            if token.lower() not in {"my", "the", "this", "that", "a", "an"} and token not in names:
                names.append(token)
        return names
