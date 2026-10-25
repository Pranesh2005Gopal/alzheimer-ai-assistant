"""Patient-scoped retrieval for personal assistant questions.

This service deliberately works with repositories already scoped by the
authenticated patient id.  It is used before the language model so saved
personal facts are answered deterministically rather than guessed from chat
history.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
from typing import Any

from backend.auth.store import get_user_by_id
from models.domain import ReminderKind


@dataclass(frozen=True)
class ContextAnswer:
    text: str
    category: str
    status: str = "ok"


class PatientContextService:
    """Retrieve only the records relevant to one personal question."""

    def __init__(self, patient_id: str, repos: Any) -> None:
        self.patient_id = patient_id
        self.repos = repos

    def answer(self, question: str) -> ContextAnswer | None:
        """Return a grounded answer for a recognized personal-data question.

        ``None`` means this is not a personal retrieval question and normal
        dialogue routing should continue.  Repository failures are distinct
        from an absent saved value so callers never claim a fact is missing
        when it merely could not be read.
        """
        lowered = " ".join(question.lower().split())
        category = self._category(lowered)
        if category is None:
            return None
        try:
            profile = self._profile()
            if category == "name":
                return self._name(profile)
            if category == "birthday":
                return self._birthday(profile)
            if category == "hobbies":
                return self._hobbies(profile)
            if category == "routine":
                return self._routine(profile)
            if category == "family":
                return self._family()
            if category == "memories":
                return self._memories(profile)
            if category in {"residence", "profession", "pet"}:
                return self._biographical(category, profile)
        except Exception:
            # Do not log the question or patient records: both can be private.
            return ContextAnswer(
                "Your saved information is temporarily unavailable. Please try again shortly.",
                category,
                "unavailable",
            )
        return None

    @staticmethod
    def _category(text: str) -> str | None:
        if any(item in text for item in ("what is my name", "what's my name", "who am i", "what should you call me", "call me")):
            return "name"
        if any(item in text for item in ("how old am i", "when is my birthday", "when's my birthday", "date of birth", "born")):
            return "birthday"
        if any(item in text for item in ("hobbies", "interests", "like doing", "music do i enjoy", "what music do i like")):
            return "hobbies"
        if any(item in text for item in ("daily routine", "morning", "what do i do", "supposed to do today", "my schedule")):
            return "routine"
        if any(item in text for item in ("family", "relatives")):
            return "family"
        if any(item in text for item in ("where did i live", "where have i lived", "previous residence")):
            return "residence"
        if any(item in text for item in ("profession", "my job", "my work", "what was my job", "what did i do for work")):
            return "profession"
        if any(item in text for item in ("dog's name", "dogs name", "pet's name", "pets name", "my dog", "my pet")):
            return "pet"
        if any(item in text for item in ("remember about me", "my memories", "my life")):
            return "memories"
        return None

    def _profile(self) -> dict:
        # The id originates in PatientAccess, never from a request body.
        user = get_user_by_id(self.patient_id)
        if not user:
            return {}
        profile = dict(user.get("profile") or {})
        # A newly created profile has empty defaults, which may still use
        # legitimate legacy facts. A field cleared through profile editing is
        # different: it must not be filled from stale seed preferences.
        profile["_explicitly_cleared_fields"] = set(user.get("cleared_profile_fields") or [])
        return profile

    def _name(self, profile: dict) -> ContextAnswer:
        full = str(profile.get("full_name") or "").strip()
        preferred = str(profile.get("preferred_name") or "").strip()
        if not preferred and not self._is_explicitly_cleared(profile, "preferred_name"):
            preferred = self._preference_value("preferred_name") or ""
        if full and preferred and preferred.lower() != full.lower():
            return ContextAnswer(f"Your name is {full}, and you prefer to be called {preferred}.", "name")
        if full:
            return ContextAnswer(f"Your name is {full}.", "name")
        if preferred:
            return ContextAnswer(f"You prefer to be called {preferred}.", "name")
        return self._missing("name")

    def _birthday(self, profile: dict) -> ContextAnswer:
        dob = str(profile.get("date_of_birth") or "").strip()
        if not dob and not self._is_explicitly_cleared(profile, "date_of_birth"):
            dob = self._preference_value("date_of_birth") or ""
        if not dob:
            return self._missing("birthday")
        try:
            born = datetime.strptime(dob, "%Y-%m-%d").date()
            if "how old" in "":  # kept as a single formatter below
                pass
            age = date.today().year - born.year - ((date.today().month, date.today().day) < (born.month, born.day))
            return ContextAnswer(f"Your birthday is {born.strftime('%B')} {born.day}, {born.year}. You are {age} years old.", "birthday")
        except ValueError:
            return ContextAnswer(f"Your saved date of birth is {dob}.", "birthday")

    def _hobbies(self, profile: dict) -> ContextAnswer:
        if self._is_explicitly_cleared(profile, "hobbies"):
            return self._missing("hobbies or interests")
        hobbies = self._strings(profile.get("hobbies"))
        if not hobbies:
            hobbies = self._preference_values("hobby", "hobbies", "interest", "interests", "activity")
        # Profile hobbies are the patient-facing source of truth.  Legacy
        # preference records fill the gap only when that profile field is empty.
        values = self._unique(hobbies or self._preference_values("hobby", "hobbies", "interest", "interests", "activity", "music"))
        if not values:
            return self._missing("hobbies or interests")
        return ContextAnswer(f"You enjoy {self._join(values)}.", "hobbies")

    def _routine(self, profile: dict) -> ContextAnswer:
        if self._is_explicitly_cleared(profile, "daily_routine"):
            return self._missing("daily routine")
        routine = self._strings(profile.get("daily_routine"))
        if routine:
            return ContextAnswer(f"Your saved daily routine is {self._join(routine)}.", "routine")
        items = [r for r in self.repos.reminders.list_all() if r.kind in {ReminderKind.DAILY_ROUTINE, ReminderKind.MEDICATION}]
        items.sort(key=lambda item: item.time_iso)
        if not items:
            return self._missing("daily routine")
        entries = []
        for item in items:
            title = item.medication_name or item.title
            entries.append(f"{self._spoken_time(item.time_iso)} for {title}")
        return ContextAnswer(f"Your saved daily routine is {self._join(entries)}.", "routine")

    def _family(self) -> ContextAnswer:
        people = [p for p in self.repos.memory.list_people() if "doctor" not in p.relationship.lower()]
        if not people:
            return self._missing("family details")
        entries = [f"{person.name}, your {person.relationship}" for person in people]
        return ContextAnswer(f"Your saved family information includes {self._join(entries)}.", "family")

    def _memories(self, profile: dict) -> ContextAnswer:
        if self._is_explicitly_cleared(profile, "personal_memories"):
            return self._missing("personal memories")
        memories = self._strings(profile.get("personal_memories"))
        memories += [p.value for p in self.repos.memory.list_preferences() if p.key.lower() in {"note", "memory", "biography"}]
        if not memories:
            return self._missing("personal memories")
        return ContextAnswer(f"Here is what I have saved: {self._join(self._unique(memories))}.", "memories")

    def _biographical(self, category: str, profile: dict) -> ContextAnswer:
        terms = {
            "residence": ("residence", "lived", "home", "location", "address"),
            "profession": ("profession", "occupation", "job", "career", "work"),
            "pet": ("pet", "dog", "cat", "animal", "retriever", "puppy"),
        }[category]
        values = []
        for memory in self._strings(profile.get("personal_memories")):
            if any(term in memory.lower() for term in terms):
                values.append(memory)
        for pref in self.repos.memory.list_preferences():
            if pref.key.lower() in terms or any(term in pref.value.lower() for term in terms):
                values.append(pref.value)
        for person in self.repos.memory.list_people():
            if any(term in f"{person.name} {person.relationship} {person.notes}".lower() for term in terms):
                values.append(person.notes or f"{person.name} is your {person.relationship}")
        if not values:
            return self._missing({"residence": "where you lived", "profession": "your profession", "pet": "your pet"}[category])
        return ContextAnswer(self._join(self._unique(values)) + ".", category)

    def _preference_value(self, key: str) -> str | None:
        values = self._preference_values(key)
        return values[0] if values else None

    def _preference_values(self, *keys: str) -> list[str]:
        wanted = {key.lower() for key in keys}
        return [p.value.strip() for p in self.repos.memory.list_preferences() if p.subject.lower() == "patient" and p.key.lower() in wanted and p.value.strip()]

    @staticmethod
    def _strings(value: object) -> list[str]:
        return [str(item).strip() for item in value] if isinstance(value, list) else []

    @staticmethod
    def _is_explicitly_cleared(profile: dict, field: str) -> bool:
        return field in profile.get("_explicitly_cleared_fields", set())

    @staticmethod
    def _unique(values: list[str]) -> list[str]:
        return list(dict.fromkeys(value.strip() for value in values if value and value.strip()))

    @staticmethod
    def _join(values: list[str]) -> str:
        if len(values) == 1:
            return values[0]
        if len(values) == 2:
            return f"{values[0]} and {values[1]}"
        return ", ".join(values[:-1]) + f", and {values[-1]}"

    @staticmethod
    def _spoken_time(value: str) -> str:
        try:
            return datetime.strptime(value[-5:], "%H:%M").strftime("%-I:%M %p")
        except ValueError:
            return value

    @staticmethod
    def _missing(detail: str) -> ContextAnswer:
        return ContextAnswer(f"I do not have {detail} saved yet.", "missing")
