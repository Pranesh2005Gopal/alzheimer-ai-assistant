from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


ROOT = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    api_host: str = "0.0.0.0"
    api_port: int = 8080

    # Whisper speech-to-text
    whisper_model: str = "base"

    # DistilBERT intent classifier
    distilbert_dir: Path = ROOT / "data" / "models" / "distilbert-intent"
    distilbert_base: str = "distilbert-base-uncased"
    train_intent_if_missing: bool = True

    # Duckling temporal parser (HTTP)
    duckling_url: str = "http://127.0.0.1:8000"

    # spaCy
    spacy_model: str = "en_core_web_sm"

    # Ollama chat model
    ollama_host: str = "http://127.0.0.1:11434"
    ollama_model: str = "qwen2.5:0.5b"

    # Coqui TTS
    coqui_model: str = "tts_models/en/ljspeech/tacotron2-DDC"

    # Chroma (Phase 3 persistence path; ephemeral client is used until then)
    chroma_path: Path = ROOT / "data" / "chroma"

    seed_path: Path = ROOT / "data" / "seed.json"
    state_path: Path = ROOT / "data" / "assistant_state.json"
    conversation_path: Path = ROOT / "data" / "conversations.json"
    conversation_history_limit: int = 50
    database_url: str = ""
    database_patient_id: str = "patient-1"
    care_admin_emails: str = ""
    intent_examples_path: Path = ROOT / "data" / "intent_examples.json"

    # Isolation Forest (Phase 7) — never used for medical diagnosis
    anomaly_contamination: float = 0.1


def get_settings() -> Settings:
    return Settings()
