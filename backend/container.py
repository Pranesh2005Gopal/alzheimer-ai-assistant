from __future__ import annotations

from functools import lru_cache

from ai.dialogue.manager import DialogueManager
from ai.llm.ollama_llama import OllamaLlama
from ai.memory.chroma_store import NullSemanticMemory
from ai.nlu.pipeline import NLUPipeline
from ai.stt.whisper_stt import WhisperSTT
from ai.tts.coqui_tts import CoquiTTS
from ai.vision.recognizer import FaceRecognizer
from repositories.in_memory import RepositoryBundle
from repositories.persistent import PersistentConversationHistory, PersistentRepositoryBundle
from repositories.postgres import PostgresConversationHistory, PostgresRepositoryBundle
from services.activity_service import ActivityLogger
from services.appointment_service import AppointmentService
from services.emergency_service import EmergencyService
from services.memory_service import MemoryService
from services.patient_context import PatientContextService
from services.reminder_manager import ReminderManager
from services.voice_pipeline import VoicePipeline
from utils.config import Settings, get_settings


class AppContainer:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        if settings.database_url:
            self.repos = PostgresRepositoryBundle(
                settings.database_url,
                settings.database_patient_id,
                settings.seed_path,
                pool_size=settings.database_pool_size,
                max_overflow=settings.database_max_overflow,
                pool_timeout=settings.database_pool_timeout,
                pool_recycle=settings.database_pool_recycle,
            )
            self.history = PostgresConversationHistory(self.repos.factory, settings.database_patient_id, settings.conversation_history_limit)
        else:
            patient_id = settings.database_patient_id
            # Local JSON persistence follows the same patient boundary as the
            # SQL repositories.  Demo seed content is never copied to a new
            # authenticated patient.
            state_path = settings.state_path.with_name(f"{settings.state_path.stem}-{patient_id}{settings.state_path.suffix}")
            conversation_path = settings.conversation_path.with_name(f"{settings.conversation_path.stem}-{patient_id}{settings.conversation_path.suffix}")
            self.repos: RepositoryBundle = PersistentRepositoryBundle(settings.seed_path, state_path, use_seed=patient_id == "patient-1", patient_id=patient_id)
            self.history = PersistentConversationHistory(conversation_path, settings.conversation_history_limit)
        self.activity = ActivityLogger(self.repos.activity)
        self.reminders = ReminderManager(self.repos.reminders)
        self.appointments = AppointmentService(self.repos.appointments)
        # Phase 3 replaces NullSemanticMemory with ChromaSemanticMemory.
        self.memory = MemoryService(self.repos.memory, NullSemanticMemory())
        self.emergency = EmergencyService(self.repos.activity)
        self.patient_context = PatientContextService(settings.database_patient_id or "patient-1", self.repos)
        self.recognizer = FaceRecognizer(self.repos.memory)
        self.dialogue = DialogueManager(
            reminders=self.reminders,
            appointments=self.appointments,
            memory=self.memory,
            emergency=self.emergency,
            patient_context=self.patient_context,
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


@lru_cache(maxsize=32)
def get_container(patient_id: str | None = None) -> AppContainer:
    settings = get_settings()
    if patient_id:
        settings = settings.model_copy(update={"database_patient_id": patient_id})
    return AppContainer(settings)
