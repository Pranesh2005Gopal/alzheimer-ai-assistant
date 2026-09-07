from __future__ import annotations

from uuid import uuid4

from models.domain import Preference
from models.nlu import NLUResult
from repositories.in_memory import InMemoryMemoryRepository
from ai.memory.chroma_store import SemanticMemoryStore


class MemoryService:
    """
    Long-term structured memory (people, dates, preferences) plus optional Chroma RAG.

    Conversation history is NOT stored here. Only explicit/relevant facts become long-term memory.
    """

    def __init__(self, repo: InMemoryMemoryRepository, semantic: SemanticMemoryStore) -> None:
        self.repo = repo
        self.semantic = semantic

    def identify(self, nlu: NLUResult) -> str:
        for name in nlu.person_mentions:
            person = self.repo.get_person_by_name(name)
            if person:
                extra = f" {person.notes}" if person.notes else ""
                return f"{person.name} is your {person.relationship}.{extra}"
        lowered = nlu.normalized_text.lower()
        if "son" in lowered:
            person = self.repo.get_person_by_name("Arun")
            if person:
                return f"{person.name} is your {person.relationship}."
        if "daughter" in lowered:
            person = self.repo.get_person_by_name("Priya")
            if person:
                return f"{person.name} is your {person.relationship}."
        people = ", ".join(f"{p.name} ({p.relationship})" for p in self.repo.list_people())
        return f"I am not sure who you mean. Known people: {people}." if people else "I do not know this person yet."

    def recall(self, query: str) -> str:
        semantic_hits = self.semantic.search(query)
        structured = self.repo.search_facts(query)
        combined = semantic_hits + structured
        if not combined:
            prefs = [f"{p.subject} {p.key}: {p.value}" for p in self.repo.list_preferences()]
            dates = [f"{d.title} on {d.date_iso}" for d in self.repo.list_important_dates()]
            people = [f"{p.name} is your {p.relationship}" for p in self.repo.list_people()]
            combined = people + dates + prefs
        return "Memory facts:\n" + "\n".join(combined[:10])

    def store_from_utterance(self, text: str) -> str:
        pref = Preference(
            id=uuid4().hex[:12],
            subject="patient",
            key="note",
            value=text,
        )
        self.repo.add_preference(pref)
        self.semantic.upsert(pref.id, text, {"kind": "long_term_note"})
        return f"Stored long-term memory: {text}"
