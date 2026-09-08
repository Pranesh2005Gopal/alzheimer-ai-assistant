"""Voice pipeline: Whisper → NLU → Dialogue Manager → Llama 3 → Coqui TTS."""

from __future__ import annotations

from pathlib import Path

from models.domain import VoiceTurnResult

from ai.dialogue.manager import DialogueManager
from ai.llm.ollama_llama import OllamaLlama
from ai.nlu.pipeline import NLUPipeline
from ai.stt.whisper_stt import WhisperSTT
from ai.tts.coqui_tts import CoquiTTS
from services.activity_service import ActivityLogger, ConversationHistory


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

    def run_audio_file(self, audio_path: Path) -> VoiceTurnResult:
        transcript = self.stt.transcribe_file(audio_path)
        if not transcript:
            reply = "I did not catch that. Please press the button and speak again."
            audio = self.tts.speak(reply)
            self.activity.log("voice", "Empty transcript", {})
            return VoiceTurnResult(
                transcript="",
                intent="UNKNOWN",
                reply_text=reply,
                status="unknown",
                audio_wav=audio,
            )
        return self.run_text(transcript)

    def run_text(self, transcript: str) -> VoiceTurnResult:
        nlu = self.nlu.interpret(transcript)
        decision = self.dialogue.handle(nlu)
        reply = self.llm.generate(
            user_text=f"The patient said: {transcript}\n\nInstruction: {decision.user_prompt_for_llm}",
            facts=decision.facts,
            conversation=self.history.as_llm_messages(),
        )
        audio = self.tts.speak(reply)
        if len(audio) <= 44:
            audio = self.tts.speak("I am here with you.")
        self.history.add("patient", transcript, nlu.intent.value)
        self.history.add("assistant", reply, nlu.intent.value)
        self.activity.log(
            "voice",
            f"intent={nlu.intent.value} transcript={transcript[:80]}",
            {"intent": nlu.intent.value, "confidence": nlu.intent_confidence, "mutated": decision.mutated},
        )
        return VoiceTurnResult(
            transcript=transcript,
            intent=nlu.intent.value,
            reply_text=reply,
            status=decision.status,
            facts={"facts": decision.facts, "confidence": nlu.intent_confidence},
            audio_wav=audio,
        )
