"""
Dialogue manager: deterministic routing.

Llama 3 never creates, deletes, or completes reminders/appointments/memories.
Those mutations go through application services only.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime

from models.intents import Intent
from models.nlu import NLUResult
from services.appointment_service import AppointmentService
from services.emergency_service import EmergencyService
from services.memory_service import MemoryService
from services.patient_context import PatientContextService
from services.reminder_manager import ReminderManager

_READ_INTENTS = {
    Intent.CHECK_REMINDER,
    Intent.CHECK_MEDICATION,
    Intent.CHECK_APPOINTMENT,
    Intent.ASK_PERSON_IDENTITY,
    Intent.ASK_MEMORY,
    Intent.ASK_DAILY_ROUTINE,
    Intent.CHECK_TIME,
    Intent.CHECK_DATE,
}


_ACK_PHRASES = {"done", "yes", "ok", "okay", "i did", "i took it", "got it"}


@dataclass
class DialogueState:
    awaiting_emergency_confirm: bool = False
    awaiting_medication_done: bool = False
    awaiting_reminder_ack: bool = False
    active_reminder_id: str | None = None
    last_intent: Intent | None = None


@dataclass
class DialogueDecision:
    user_prompt_for_llm: str
    facts: str
    mutated: bool = False
    status: str = "ok"
    extras: dict = field(default_factory=dict)


class DialogueManager:
    def __init__(
        self,
        reminders: ReminderManager,
        appointments: AppointmentService,
        memory: MemoryService,
        emergency: EmergencyService,
        patient_context: PatientContextService | None = None,
    ) -> None:
        self.reminders = reminders
        self.appointments = appointments
        self.memory = memory
        self.emergency = emergency
        self.patient_context = patient_context
        self.state = DialogueState()

    def handle(self, nlu: NLUResult) -> DialogueDecision:
        text = nlu.normalized_text
        lowered = re.sub(r"[.!?]+$", "", text.lower().strip()).strip()

        self._remember_from_speech(text)

        # Personal questions are answered from the authenticated patient's
        # saved application records before intent classification or the LLM.
        if self.patient_context is not None:
            answer = self.patient_context.answer(text)
            if answer is not None:
                return DialogueDecision(
                    user_prompt_for_llm="Say the saved patient information below in the same words.",
                    facts=answer.text,
                    status=answer.status,
                    extras={"verbatim": True, "patient_context_category": answer.category},
                )

        if self.state.awaiting_emergency_confirm:
            return self._finish_emergency_confirm(lowered)

        if self.state.awaiting_reminder_ack:
            snooze = self._snooze_decision(nlu, lowered)
            if snooze is not None:
                return snooze
            if lowered in _ACK_PHRASES:
                reminder = self.reminders.complete_active()
                self.state.awaiting_reminder_ack = False
                self.state.active_reminder_id = None
                self.state.awaiting_medication_done = False
                fact = (
                    "Okay. I've marked your reminder as completed."
                    if reminder
                    else "I could not find that reminder."
                )
                return DialogueDecision(
                    user_prompt_for_llm="Say the facts below in the same words.",
                    facts=fact,
                    mutated=bool(reminder),
                    extras={"verbatim": True},
                )

        if self.state.awaiting_medication_done and lowered in _ACK_PHRASES:
            reminder = self.reminders.mark_next_medication_done()
            self.state.awaiting_medication_done = False
            fact = "Okay. I've marked your reminder as completed." if reminder else "I could not find a pending medication."
            return DialogueDecision(
                user_prompt_for_llm="Say the facts below in the same words.",
                facts=fact,
                mutated=True,
                extras={"verbatim": True},
            )

        intent = nlu.intent
        if intent == Intent.UNKNOWN:
            intent = self._recover_intent(nlu)
            nlu = nlu.model_copy(update={"intent": intent})
        if self._looks_like_person_query(nlu.normalized_text) and intent in {
            Intent.UNKNOWN,
            Intent.ASK_MEMORY,
            Intent.GENERAL_CONVERSATION,
        }:
            intent = Intent.ASK_PERSON_IDENTITY
            nlu = nlu.model_copy(update={"intent": intent})
        if self._looks_like_create_reminder(nlu.normalized_text) and intent in {
            Intent.UNKNOWN,
            Intent.GENERAL_CONVERSATION,
            Intent.CHECK_REMINDER,
        }:
            intent = Intent.CREATE_REMINDER
            nlu = nlu.model_copy(update={"intent": intent})
        if self._looks_like_update_reminder(nlu.normalized_text):
            return self._update_reminder(nlu)
        self.state.last_intent = intent

        combined = self._combine_read_questions(nlu)
        if combined is not None:
            return combined

        routers = {
            Intent.CREATE_REMINDER: self._create_reminder,
            Intent.DELETE_REMINDER: self._delete_reminder,
            Intent.CHECK_REMINDER: self._check_reminders,
            Intent.CHECK_MEDICATION: self._check_medication,
            Intent.CHECK_APPOINTMENT: self._check_appointment,
            Intent.CREATE_APPOINTMENT: self._create_appointment,
            Intent.ASK_PERSON_IDENTITY: self._ask_person,
            Intent.ASK_MEMORY: self._ask_memory,
            Intent.STORE_MEMORY: self._store_memory,
            Intent.ASK_DAILY_ROUTINE: self._daily_routine,
            Intent.CHECK_TIME: self._check_time,
            Intent.CHECK_DATE: self._check_date,
            Intent.MAKE_CALL: self._make_call,
            Intent.EMERGENCY: self._emergency,
            Intent.GENERAL_CONVERSATION: self._chat,
            Intent.UNKNOWN: self._unknown,
        }
        handler = routers.get(intent, self._unknown)
        return handler(nlu)

    def _combine_read_questions(self, nlu: NLUResult) -> DialogueDecision | None:
        pieces = [nlu, *nlu.followups]
        for extra_intent in self._intents_hinted_in_text(nlu.normalized_text):
            pieces.append(nlu.model_copy(update={"intent": extra_intent}))
        seen: set[Intent] = set()
        decisions: list[DialogueDecision] = []
        for piece in pieces:
            intent = piece.intent
            if intent == Intent.UNKNOWN:
                intent = self._recover_intent(piece)
                piece = piece.model_copy(update={"intent": intent})
            if intent not in _READ_INTENTS or intent in seen:
                continue
            seen.add(intent)
            routers = {
                Intent.CHECK_REMINDER: self._check_reminders,
                Intent.CHECK_MEDICATION: self._check_medication,
                Intent.CHECK_APPOINTMENT: self._check_appointment,
                Intent.ASK_PERSON_IDENTITY: self._ask_person,
                Intent.ASK_MEMORY: self._ask_memory,
                Intent.ASK_DAILY_ROUTINE: self._daily_routine,
                Intent.CHECK_TIME: self._check_time,
                Intent.CHECK_DATE: self._check_date,
            }
            decisions.append(routers[intent](piece))
        if len(decisions) < 2:
            return None
        return DialogueDecision(
            user_prompt_for_llm=(
                "Answer every part of the patient's question in short spoken sentences. "
                "Use only the facts. Never say intent, UNKNOWN, or any system label."
            ),
            facts="\n".join(item.facts for item in decisions),
        )

    def _intents_hinted_in_text(self, text: str) -> list[Intent]:
        lowered = text.lower()
        found: list[Intent] = []
        if MemoryService._is_self_question(lowered) or MemoryService._is_family_list_question(lowered):
            found.append(Intent.ASK_PERSON_IDENTITY)
        if "who is my" in lowered:
            found.append(Intent.ASK_PERSON_IDENTITY)
        if "appointment" in lowered or "clinic" in lowered or ("doctor" in lowered and "who" not in lowered):
            found.append(Intent.CHECK_APPOINTMENT)
        if "medicine" in lowered or "medication" in lowered or "tablet" in lowered:
            found.append(Intent.CHECK_MEDICATION)
        return found

    def _recover_intent(self, nlu: NLUResult) -> Intent:
        text = nlu.normalized_text.lower()
        if MemoryService._is_self_question(text) or MemoryService._is_family_list_question(text):
            return Intent.ASK_PERSON_IDENTITY
        if "who is my" in text or text.strip().startswith("who is") or self._looks_like_person_query(text):
            return Intent.ASK_PERSON_IDENTITY
        if self._looks_like_create_reminder(text):
            return Intent.CREATE_REMINDER
        if "appointment" in text or "clinic" in text or ("doctor" in text and "who" not in text):
            return Intent.CHECK_APPOINTMENT
        if "medicine" in text or "medication" in text or "tablet" in text or "pill" in text:
            return Intent.CHECK_MEDICATION
        if "remind" in text:
            return Intent.CHECK_REMINDER
        if "what do i have to do" in text or "routine" in text or "today" in text:
            return Intent.ASK_DAILY_ROUTINE
        if "what time" in text:
            return Intent.CHECK_TIME
        if "what day" in text or "what is today's date" in text or "what's the date" in text:
            return Intent.CHECK_DATE
        return Intent.UNKNOWN

    def _time_from_duckling(self, nlu: NLUResult) -> str | None:
        for item in nlu.temporal:
            value = item.value
            if isinstance(value, dict):
                inner = value.get("value")
                if isinstance(inner, str) and inner.strip():
                    return inner.strip()
                continue
            if value:
                return str(value)
        return None

    def _create_reminder(self, nlu: NLUResult) -> DialogueDecision:
        if self.state.awaiting_reminder_ack:
            snooze = self._snooze_decision(nlu, nlu.normalized_text.lower())
            if snooze is not None:
                return snooze
        when = self._time_from_duckling(nlu)
        
        # Manually extract task and clock to check if they are valid
        from services.reminder_manager import _clock_from_text, _extract_task
        task = _extract_task(nlu.normalized_text)
        time_iso = when or _clock_from_text(nlu.normalized_text) or "unspecified"
        
        if time_iso == "unspecified":
            return DialogueDecision(
                user_prompt_for_llm="Say the facts below in the same words.",
                facts="What time should I remind you?",
                extras={"verbatim": True},
            )
        
        if not task or task.lower() == "your reminder":
            return DialogueDecision(
                user_prompt_for_llm="Say the facts below in the same words.",
                facts="What would you like me to remind you about?",
                extras={"verbatim": True},
            )
        if when is None and self._time_has_passed_today(time_iso):
            return DialogueDecision("Say the facts below in the same words.", f"{time_iso} has already passed today. Would you like me to set it for tomorrow?", extras={"verbatim": True})

        reminder = self.reminders.create_from_utterance(nlu.normalized_text, when)
        return DialogueDecision(
            user_prompt_for_llm="Say the confirmation below in the same words.",
            facts=self.reminders.spoken_created(reminder),
            mutated=True,
            extras={"verbatim": True},
        )

    def _delete_reminder(self, nlu: NLUResult) -> DialogueDecision:
        removed = self.reminders.delete_matching(nlu.normalized_text)
        fact = "Reminder removed." if removed else "I could not find that reminder."
        return DialogueDecision(
            user_prompt_for_llm="Tell the patient the result simply.",
            facts=fact,
            mutated=removed,
        )

    def _update_reminder(self, nlu: NLUResult) -> DialogueDecision:
        from services.reminder_manager import _clock_from_text
        time_iso = self._time_from_duckling(nlu) or _clock_from_text(nlu.normalized_text)
        if not time_iso:
            return DialogueDecision("Say the facts below in the same words.", "What new time would you like for the reminder?", extras={"verbatim": True})
        reminder = self.reminders.update_matching(nlu.normalized_text, time_iso)
        if reminder is None:
            return DialogueDecision("Say the facts below in the same words.", "I could not find one clear reminder to change.", extras={"verbatim": True})
        return DialogueDecision("Say the facts below in the same words.", f"Your reminder for {reminder.title} is now set for {self.reminders.spoken_created(reminder).split(' at ')[-1]}", mutated=True, extras={"verbatim": True})

    def _check_reminders(self, nlu: NLUResult) -> DialogueDecision:
        return DialogueDecision(
            user_prompt_for_llm="List the pending reminders clearly and slowly.",
            facts=self.reminders.spoken_list(),
        )

    def _check_medication(self, nlu: NLUResult) -> DialogueDecision:
        self.state.awaiting_medication_done = True
        return DialogueDecision(
            user_prompt_for_llm="Tell the patient about medication. Mention they can say Done after taking it.",
            facts=self.reminders.spoken_medication(),
        )

    def _check_appointment(self, nlu: NLUResult) -> DialogueDecision:
        return DialogueDecision(
            user_prompt_for_llm="Tell the patient the next appointment using only the facts.",
            facts=self.appointments.spoken_next(),
        )

    def _create_appointment(self, nlu: NLUResult) -> DialogueDecision:
        when = self._time_from_duckling(nlu)
        appointment = self.appointments.create_from_utterance(nlu.normalized_text, when)
        return DialogueDecision(
            user_prompt_for_llm="Confirm the saved appointment briefly.",
            facts=(
                f"Appointment saved with {appointment.doctor} on {appointment.date_iso} "
                f"at {appointment.time_iso}, {appointment.location}."
            ),
            mutated=True,
        )

    def _ask_person(self, nlu: NLUResult) -> DialogueDecision:
        return DialogueDecision(
            user_prompt_for_llm="Say the facts below to the patient in the same words. Do not add extra people.",
            facts=self.memory.identify(nlu),
            extras={"verbatim": True},
        )

    def _ask_memory(self, nlu: NLUResult) -> DialogueDecision:
        return DialogueDecision(
            user_prompt_for_llm="Answer from memory facts only. Do not invent likes or dates.",
            facts=self.memory.recall(nlu.normalized_text),
        )

    def _store_memory(self, nlu: NLUResult) -> DialogueDecision:
        stored = self.memory.store_from_utterance(nlu.normalized_text)
        return DialogueDecision(
            user_prompt_for_llm="Confirm that you will remember this.",
            facts=stored,
            mutated=True,
        )

    def _daily_routine(self, nlu: NLUResult) -> DialogueDecision:
        return DialogueDecision(
            user_prompt_for_llm="Describe today's routine in order, slowly.",
            facts=self.reminders.spoken_daily_routine(),
        )

    def _check_time(self, nlu: NLUResult) -> DialogueDecision:
        now = datetime.now().strftime("%I:%M %p").lstrip("0")
        return DialogueDecision(
            user_prompt_for_llm="Tell the patient the current time in a simple sentence.",
            facts=f"Current time is {now}.",
        )

    def _check_date(self, nlu: NLUResult) -> DialogueDecision:
        today = datetime.now().strftime("%A, %B %d, %Y")
        return DialogueDecision(
            user_prompt_for_llm="Tell the patient today's date in a simple sentence.",
            facts=f"Today is {today}.",
        )

    def _make_call(self, nlu: NLUResult) -> DialogueDecision:
        return DialogueDecision(
            user_prompt_for_llm="Explain that the phone call feature is prepared but not connected yet.",
            facts="Call workflow is modular. No live telephony is configured in this phase.",
            status="ok",
        )

    def _emergency(self, nlu: NLUResult) -> DialogueDecision:
        self.state.awaiting_emergency_confirm = True
        return DialogueDecision(
            user_prompt_for_llm="Ask calmly if they need help right now. Keep it very short.",
            facts="Emergency intent detected. Confirmation required before notifying the caregiver.",
            status="confirm",
        )

    def _finish_emergency_confirm(self, lowered: str) -> DialogueDecision:
        self.state.awaiting_emergency_confirm = False
        yes = lowered in {"yes", "help", "help me", "please", "ok", "okay", "i need help"}
        if yes:
            event = self.emergency.trigger(reason="patient_confirmed")
            return DialogueDecision(
                user_prompt_for_llm="Reassure the patient that help is being requested. Stay calm.",
                facts=f"Emergency workflow started. Event id {event.id}. Caregiver notification is queued for later integration.",
                mutated=True,
                status="emergency",
            )
        return DialogueDecision(
            user_prompt_for_llm="Acknowledge that you will not call for help, and stay available.",
            facts="Emergency was not confirmed.",
        )

    def _chat(self, nlu: NLUResult) -> DialogueDecision:
        lowered = nlu.normalized_text.lower().strip(" .!?")
        if re.fullmatch(r"(?:hello|hi|hey)(?: there)?(?: nice to meet you)?", lowered) or "nice to meet you" in lowered:
            return DialogueDecision("Say the facts below in the same words.", "Hello! It's lovely to meet you. I'm here to help whenever you need me.", extras={"verbatim": True})
        if lowered in {"can you help me", "help me", "i need help"}:
            return DialogueDecision("Say the facts below in the same words.", "Of course. What would you like help with?", extras={"verbatim": True})
        return DialogueDecision(
            user_prompt_for_llm=(
                "Reply to what the patient just said. Stay on that topic. "
                "If they repeat a question, give the same simple answer. "
                "Do not mention medicine, appointments, or family unless they asked. "
                "Never mention conversation history."
            ),
            facts="",
        )

    def _unknown(self, nlu: NLUResult) -> DialogueDecision:
        recovered = self._recover_intent(nlu)
        if recovered != Intent.UNKNOWN:
            nlu = nlu.model_copy(update={"intent": recovered})
            routers = {
                Intent.CHECK_REMINDER: self._check_reminders,
                Intent.CHECK_MEDICATION: self._check_medication,
                Intent.CHECK_APPOINTMENT: self._check_appointment,
                Intent.ASK_PERSON_IDENTITY: self._ask_person,
                Intent.ASK_MEMORY: self._ask_memory,
                Intent.ASK_DAILY_ROUTINE: self._daily_routine,
                Intent.CHECK_TIME: self._check_time,
                Intent.CHECK_DATE: self._check_date,
            }
            return routers[recovered](nlu)
        return DialogueDecision(
            user_prompt_for_llm=(
                "Answer what the patient just said as a kind companion. "
                "Do not list medicine or appointments unless they asked. "
                "Never mention conversation history. Never say UNKNOWN, intent, or classifier."
            ),
            facts="",
            status="unknown",
        )

    def note_reminder_alert(self, reminder_id: str) -> None:
        self.state.awaiting_reminder_ack = True
        self.state.active_reminder_id = reminder_id
        self.state.awaiting_medication_done = True
        self.reminders.set_active(reminder_id)

    def _looks_like_person_query(self, text: str) -> bool:
        lowered = text.lower()
        return lowered.startswith("who is") or "who is" in lowered or "tell me who" in lowered

    def _looks_like_create_reminder(self, text: str) -> bool:
        lowered = text.lower()
        if "remind me again" in lowered or "snooze" in lowered:
            return False
        return bool(re.search(r"\b(remind me|a reminder)\b", lowered)) and any(
            token in lowered for token in (" to ", " at ", " for ")
        )

    def _looks_like_update_reminder(self, text: str) -> bool:
        return bool(re.search(r"\b(change|update|move|reschedule)\b.*\breminder\b|\breminder\b.*\b(change|update|move|reschedule)\b", text.lower()))

    @staticmethod
    def _time_has_passed_today(time_iso: str) -> bool:
        from services.reminder_manager import parse_reminder_datetime
        due = parse_reminder_datetime(time_iso, datetime.now())
        return due is not None and due <= datetime.now() and "T" not in time_iso

    def _snooze_decision(self, nlu: NLUResult, lowered: str) -> DialogueDecision | None:
        minutes = _snooze_minutes(nlu, lowered)
        if minutes is None:
            return None
        reminder = self.reminders.snooze_active(minutes)
        self.state.awaiting_reminder_ack = False
        self.state.active_reminder_id = None
        if reminder is None:
            return DialogueDecision(
                user_prompt_for_llm="Say the facts below in the same words.",
                facts="I could not find that reminder.",
                extras={"verbatim": True},
            )
        return DialogueDecision(
            user_prompt_for_llm="Say the confirmation below in the same words.",
            facts=f"Okay, I'll remind you again in {minutes} minutes.",
            mutated=True,
            extras={"verbatim": True},
        )

    def _remember_from_speech(self, text: str) -> None:
        name = _extract_spoken_name(text)
        if name:
            self.memory.set_preferred_name(name)


_NOT_NAMES = {
    "tired",
    "hungry",
    "sick",
    "lost",
    "fine",
    "okay",
    "scared",
    "confused",
    "here",
    "ready",
    "done",
    "sorry",
    "home",
    "alone",
    "worried",
    "sad",
    "happy",
    "ok",
    "good",
    "cold",
    "hot",
    "back",
    "going",
}


def _snooze_minutes(nlu: NLUResult, lowered: str) -> int | None:
    again = "remind me again" in lowered or "snooze" in lowered
    match = re.search(r"\b(?:in|for)\s+(\d+)\s*(minutes?|mins?|hours?|hrs?)\b", lowered)
    if match:
        amount = int(match.group(1))
        unit = match.group(2)
        minutes = amount * 60 if unit.startswith("hour") or unit.startswith("hr") else amount
        return minutes
    for item in nlu.temporal:
        if item.dim != "duration":
            continue
        value = item.value
        if isinstance(value, dict):
            unit = str(value.get("unit") or "").lower()
            amount = value.get("value")
            normalized = value.get("normalized") or {}
            if isinstance(normalized, dict) and normalized.get("unit") == "second":
                try:
                    return max(1, int(float(normalized["value"]) // 60))
                except (TypeError, ValueError):
                    pass
            if isinstance(amount, (int, float)):
                if unit.startswith("hour"):
                    return int(amount * 60)
                if unit.startswith("min"):
                    return int(amount)
    if again:
        return 10
    return None


def _extract_spoken_name(text: str) -> str | None:
    patterns = (
        r"\bmy name is ([A-Za-z][A-Za-z'\-]{1,30})\b",
        r"\bcall me ([A-Za-z][A-Za-z'\-]{1,30})\b",
        r"\bi am ([A-Za-z][A-Za-z'\-]{1,30})\b",
        r"\bi'm ([A-Za-z][A-Za-z'\-]{1,30})\b",
    )
    for pattern in patterns:
        match = re.search(pattern, text.strip(), flags=re.IGNORECASE)
        if not match:
            continue
        name = match.group(1).strip()
        if name.lower() in _NOT_NAMES:
            continue
        return name
    return None
