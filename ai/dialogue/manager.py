"""
Dialogue manager: deterministic routing.

Llama 3 never creates, deletes, or completes reminders/appointments/memories.
Those mutations go through application services only.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime

from models.intents import Intent
from models.nlu import NLUResult
from services.appointment_service import AppointmentService
from services.emergency_service import EmergencyService
from services.memory_service import MemoryService
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


@dataclass
class DialogueState:
    awaiting_emergency_confirm: bool = False
    awaiting_medication_done: bool = False
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
    ) -> None:
        self.reminders = reminders
        self.appointments = appointments
        self.memory = memory
        self.emergency = emergency
        self.state = DialogueState()

    def handle(self, nlu: NLUResult) -> DialogueDecision:
        text = nlu.normalized_text
        lowered = text.lower().strip()

        if self.state.awaiting_emergency_confirm:
            return self._finish_emergency_confirm(lowered)

        if self.state.awaiting_medication_done and lowered in {"done", "yes", "i did", "i took it"}:
            reminder = self.reminders.mark_next_medication_done()
            self.state.awaiting_medication_done = False
            fact = "Medication marked as taken." if reminder else "I could not find a pending medication."
            return DialogueDecision(
                user_prompt_for_llm="The patient said they finished their medication. Reassure them briefly.",
                facts=fact,
                mutated=True,
            )

        intent = nlu.intent
        if intent == Intent.UNKNOWN:
            intent = self._recover_intent(nlu)
            nlu = nlu.model_copy(update={"intent": intent})
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
        if MemoryService._is_self_question(lowered):
            found.append(Intent.ASK_PERSON_IDENTITY)
        if "appointment" in lowered or "doctor" in lowered or "clinic" in lowered:
            found.append(Intent.CHECK_APPOINTMENT)
        if "medicine" in lowered or "medication" in lowered or "tablet" in lowered:
            found.append(Intent.CHECK_MEDICATION)
        return found

    def _recover_intent(self, nlu: NLUResult) -> Intent:
        text = nlu.normalized_text.lower()
        if MemoryService._is_self_question(text) or "who is" in text:
            return Intent.ASK_PERSON_IDENTITY
        if "appointment" in text or "doctor" in text or "clinic" in text:
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
            if item.value:
                return str(item.value)
        return None

    def _create_reminder(self, nlu: NLUResult) -> DialogueDecision:
        when = self._time_from_duckling(nlu)
        reminder = self.reminders.create_from_utterance(nlu.normalized_text, when)
        return DialogueDecision(
            user_prompt_for_llm="Confirm the reminder in one or two short spoken sentences.",
            facts=f"Reminder created: {reminder.title} at {reminder.time_iso} ({reminder.kind.value}).",
            mutated=True,
        )

    def _delete_reminder(self, nlu: NLUResult) -> DialogueDecision:
        removed = self.reminders.delete_matching(nlu.normalized_text)
        fact = "Reminder removed." if removed else "I could not find that reminder."
        return DialogueDecision(
            user_prompt_for_llm="Tell the patient the result simply.",
            facts=fact,
            mutated=removed,
        )

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
            user_prompt_for_llm="Identify the person using only the facts. If unknown, say you are not sure.",
            facts=self.memory.identify(nlu),
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
        return DialogueDecision(
            user_prompt_for_llm=nlu.normalized_text,
            facts="No application data changed. This is general conversation. Be a kind companion.",
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
        overview = "\n".join(
            [
                self.memory.spoken_self(),
                self.appointments.spoken_next(),
                self.reminders.spoken_list(),
            ]
        )
        return DialogueDecision(
            user_prompt_for_llm=(
                "You did not fully understand. Still help using the facts below. "
                "Speak simply. Never say UNKNOWN, intent, or classifier."
            ),
            facts=overview,
            status="unknown",
        )
