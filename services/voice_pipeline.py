"""Voice pipeline: Whisper → NLU → Dialogue Manager → Llama 3 → Coqui TTS."""

from __future__ import annotations

from pathlib import Path

from models.domain import VoiceTurnResult

from ai.dialogue.manager import DialogueManager
from ai.llm.ollama_llama import OllamaLlama, patient_facing_speech
from ai.nlu.pipeline import NLUPipeline
from ai.stt.whisper_stt import WhisperSTT
from ai.tts.coqui_tts import CoquiTTS
from services.activity_service import ActivityLogger, ConversationHistory

_UNHEARD = "I didn't quite hear that. Could you please say it again?"


class VoicePipeline:
    def __init__(
        self,
        stt: WhisperSTT,
        nlu: NLUPipeline,
        dialogue: DialogueManager,
        llm: OllamaLlama,
        tts: CoquiTTS,
        history: ConversationHistory,
        activity: ActivityLogger,
    ) -> None:
        self.stt = stt
        self.nlu = nlu
        self.dialogue = dialogue
        self.llm = llm
        self.tts = tts
        self.history = history
        self.activity = activity

    def unheard_reply(self) -> VoiceTurnResult:
        audio = self._speak(_UNHEARD)
        self.activity.log("voice", "Unheard or unreliable transcript", {})
        return VoiceTurnResult(
            transcript="",
            intent="UNKNOWN",
            reply_text=_UNHEARD,
            status="unheard",
            audio_wav=audio,
        )

    def run_audio_file(self, audio_path: Path) -> VoiceTurnResult:
        heard = self.stt.transcribe_file(audio_path, vocabulary_hints=self._vocabulary_hints())
        if not heard.reliable or not heard.text.strip():
            return self.unheard_reply()
        return self.run_text(heard.text)

    def run_text(self, transcript: str) -> VoiceTurnResult:
        cleaned = " ".join(transcript.split()).strip()
        if len([ch for ch in cleaned if ch.isalpha()]) < 2:
            return self.unheard_reply()
        nlu = self.nlu.interpret(cleaned)
        decision = self.dialogue.handle(nlu)
        if decision.extras.get("verbatim") and decision.facts.strip():
            reply = patient_facing_speech(decision.facts, decision.facts)
        else:
            reply = self.llm.generate(
                user_text=cleaned,
                facts=decision.facts,
                conversation=self.history.as_llm_messages(),
            )
            reply = patient_facing_speech(reply, decision.facts)
        audio = self._speak(reply)
        self.history.add("patient", cleaned, nlu.intent.value)
        self.history.add("assistant", reply, nlu.intent.value)
        self.activity.log(
            "voice",
            f"intent={nlu.intent.value} transcript={cleaned[:80]}",
            {"intent": nlu.intent.value, "confidence": nlu.intent_confidence, "mutated": decision.mutated},
        )
        return VoiceTurnResult(
            transcript=cleaned,
            intent=nlu.intent.value,
            reply_text=reply,
            status=decision.status,
            facts={"facts": decision.facts, "confidence": nlu.intent_confidence},
            audio_wav=audio,
        )

    def _vocabulary_hints(self) -> list[str]:
        hints: list[str] = []
        name = self.dialogue.memory.patient_display_name()
        if name:
            hints.append(name)
        for person in self.dialogue.memory.repo.list_people():
            hints.append(person.name)
            if person.relationship:
                hints.append(person.relationship)
        for reminder in self.dialogue.reminders.repo.list_all():
            if reminder.medication_name:
                hints.append(reminder.medication_name)
            if reminder.title:
                hints.append(reminder.title)
        nxt = self.dialogue.appointments.repo.next_appointment()
        if nxt and nxt.doctor:
            hints.append(nxt.doctor)
        return hints

    def _speak(self, reply: str) -> bytes:
        spoken = patient_facing_speech(reply, "")
        if not spoken:
            return b""
        audio = self.tts.speak(spoken)
        if len(audio) <= 44:
            return b""
        return audio
