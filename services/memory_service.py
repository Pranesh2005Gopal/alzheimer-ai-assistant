from __future__ import annotations

import re
from uuid import uuid4

from models.domain import Person, Preference
from models.nlu import NLUResult
from repositories.in_memory import InMemoryMemoryRepository
from ai.memory.chroma_store import SemanticMemoryStore

_ROLE_WORDS = ("daughter", "son", "caregiver", "doctor", "wife", "husband", "spouse", "brother", "sister")
_NAME_STOP = {
    "who",
    "what",
    "this",
    "that",
    "he",
    "she",
    "they",
    "my",
    "the",
    "a",
    "an",
    "person",
    "someone",
    "family",
    "doctor",
    "son",
    "daughter",
    "brother",
    "sister",
}


class MemoryService:
    """
    Long-term structured memory (people, dates, preferences) plus optional Chroma RAG.

    Conversation history is NOT stored here. Only explicit/relevant facts become long-term memory.
    """

    def __init__(self, repo: InMemoryMemoryRepository, semantic: SemanticMemoryStore) -> None:
        self.repo = repo
        self.semantic = semantic

    def identify(self, nlu: NLUResult) -> str:
        lowered = nlu.normalized_text.lower()
        if self._is_family_list_question(lowered):
            return self.spoken_family()
        if self._is_self_question(lowered):
            return self.spoken_self()
        for role in _ROLE_WORDS:
            if f"my {role}" in lowered or f"the {role}" in lowered:
                matches = self._people_for_role(role)
                if len(matches) == 1:
                    return self.spoken_relationship(matches[0])
                if len(matches) > 1:
                    names = " and ".join(person.name for person in matches)
                    return f"Your {role} is {names}."
                return "I don't have that information right now."
        person = self.person_from_query(nlu)
        if person:
            return self.spoken_relationship(person)
        queried = self._queried_name(nlu)
        if queried:
            return f"I don't have information about who {queried} is."
        people = ", ".join(f"{p.name} ({p.relationship})" for p in self.repo.list_people())
        return f"I am not sure who you mean. Known people: {people}." if people else "I don't have that information right now."

    def spoken_relationship(self, person: Person) -> str:
        stored = self.repo.get_person_by_name(person.name) or person
        relationship = (stored.relationship or "").strip()
        if relationship:
            return f"{stored.name} is your {relationship}."
        return f"I know {stored.name}, but I don't have information about their relationship to you."

    def spoken_face_identity(self, person: Person | None, unknown: bool) -> str:
        if unknown or person is None:
            return "I don't recognize this person."
        stored = self.repo.get_person_by_name(person.name) or person
        relationship = (stored.relationship or "").strip()
        if relationship:
            return f"This is {stored.name}, your {relationship}."
        return f"This is {stored.name}, but I don't have information about their relationship to you."

    def person_from_query(self, nlu: NLUResult) -> Person | None:
        lowered = nlu.normalized_text.lower()
        ranked: list[Person] = []
        for person in self.repo.list_people():
            name = person.name.lower().replace("dr.", "").strip()
            if name and name in lowered:
                ranked.append(person)
        if ranked:
            ranked.sort(key=lambda item: len(item.name), reverse=True)
            return ranked[0]
        for mention in nlu.person_mentions:
            found = self.repo.get_person_by_name(mention)
            if found:
                return found
        queried = self._queried_name(nlu)
        if queried:
            return self.repo.get_person_by_name(queried)
        return None

    def _queried_name(self, nlu: NLUResult) -> str | None:
        for mention in nlu.person_mentions:
            cleaned = mention.strip(" ?.")
            if cleaned.lower() not in _NAME_STOP and len(cleaned) > 1:
                return cleaned
        match = re.search(
            r"\b(?:who is|tell me who)\s+(?:my\s+)?([A-Za-z][A-Za-z.'\-]*)",
            nlu.normalized_text,
            flags=re.IGNORECASE,
        )
        if not match:
            return None
        name = match.group(1).strip()
        if name.lower() in _NAME_STOP:
            return None
        return name

    def spoken_family(self) -> str:
        people = self.repo.list_people()
        if not people:
            return "I don't have that information right now."
        family = [p for p in people if "doctor" not in p.relationship.lower()]
        doctors = [p for p in people if "doctor" in p.relationship.lower()]
        parts: list[str] = []
        if family:
            names = " and ".join(person.name for person in family)
            if len(family) == 1:
                parts.append(f"{family[0].name} is your {family[0].relationship}.")
            else:
                parts.append(f"Your family members are {names}.")
        for doctor in doctors:
            parts.append(f"{doctor.name} is your {doctor.relationship}.")
        return " ".join(parts) if parts else "I don't have that information right now."

    def _people_for_role(self, role: str) -> list:
        needle = role.lower()
        found = []
        for person in self.repo.list_people():
            blob = f"{person.relationship} {person.notes}".lower()
            if needle in blob:
                found.append(person)
        return found

    def spoken_self(self) -> str:
        name = self.patient_display_name()
        if name:
            return f"Your name is {name}. I am your helper, and I am here with you."
        return "You are at home. I am your helper, and I am here with you."

    @staticmethod
    def _is_self_question(lowered: str) -> bool:
        return any(
            phrase in lowered
            for phrase in ("who am i", "who am i?", "what is my name", "what's my name", "who i am")
        )

    @staticmethod
    def _is_family_list_question(lowered: str) -> bool:
        return any(
            phrase in lowered
            for phrase in (
                "who are my family",
                "who is in my family",
                "who are my family members",
                "tell me about my family",
                "who is my family",
            )
        )

    def patient_display_name(self) -> str | None:
        for pref in self.repo.list_preferences("patient"):
            if pref.key == "preferred_name" and pref.value.strip():
                return pref.value.strip()
        return None

    def set_preferred_name(self, name: str) -> str:
        cleaned = name.strip()
        if not cleaned:
            return ""
        if cleaned[:1].islower():
            cleaned = cleaned.capitalize()
        for pref in self.repo.list_preferences("patient"):
            if pref.key == "preferred_name":
                pref.value = cleaned
                return f"The patient's name is {cleaned}."
        self.repo.add_preference(
            Preference(id=uuid4().hex[:12], subject="patient", key="preferred_name", value=cleaned)
        )
        return f"The patient's name is {cleaned}."

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
