from __future__ import annotations

from functools import lru_cache

from ai.dialogue.manager import DialogueManager
from ai.llm.ollama_llama import OllamaLlama
from ai.memory.chroma_store import NullSemanticMemory
from ai.nlu.pipeline import NLUPipeline
from ai.stt.whisper_stt import WhisperSTT
from ai.tts.coqui_tts import CoquiTTS
from repositories.in_memory import RepositoryBundle, load_seed
from services.activity_service import ActivityLogger, ConversationHistory
from services.appointment_service import AppointmentService
from services.emergency_service import EmergencyService
from services.memory_service import MemoryService
from services.reminder_manager import ReminderManager
from services.voice_pipeline import VoicePipeline
from utils.config import Settings, get_settings


class AppContainer:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.repos: RepositoryBundle = load_seed(settings.seed_path)
        self.history = ConversationHistory()
        self.activity = ActivityLogger(self.repos.activity)
        self.reminders = ReminderManager(self.repos.reminders)
        self.appointments = AppointmentService(self.repos.appointments)
        # Phase 3 replaces NullSemanticMemory with ChromaSemanticMemory.
        self.memory = MemoryService(self.repos.memory, NullSemanticMemory())
        self.emergency = EmergencyService(self.repos.activity)
        self.dialogue = DialogueManager(
            reminders=self.reminders,
            appointments=self.appointments,
            memory=self.memory,
            emergency=self.emergency,
        )
        self.pipeline = VoicePipeline(
            stt=WhisperSTT(settings),
            nlu=NLUPipeline(settings),
            dialogue=self.dialogue,
            llm=OllamaLlama(settings),
            tts=CoquiTTS(settings),
            history=self.history,
            activity=self.activity,
        )


@lru_cache(maxsize=1)
def get_container() -> AppContainer:
    return AppContainer(get_settings())
