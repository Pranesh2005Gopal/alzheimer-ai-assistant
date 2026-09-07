"""Outputs of spaCy, DistilBERT, and Duckling before the dialogue manager."""

from typing import Any, Optional

from pydantic import BaseModel, Field

from models.intents import Intent


class SpacyDocumentView(BaseModel):
    tokens: list[str] = Field(default_factory=list)
    lemmas: list[str] = Field(default_factory=list)
    entities: list[dict[str, str]] = Field(default_factory=list)


class TemporalEntity(BaseModel):
    dim: str
    body: str
    value: Any = None
    grain: Optional[str] = None


class NLUResult(BaseModel):
    raw_text: str
    normalized_text: str
    intent: Intent
    intent_confidence: float
    spacy: SpacyDocumentView
    temporal: list[TemporalEntity] = Field(default_factory=list)
    person_mentions: list[str] = Field(default_factory=list)
