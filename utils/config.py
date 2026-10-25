from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


ROOT = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    api_host: str = "0.0.0.0"
    api_port: int = 8080
    environment: str = "development"
    cors_origins: str = ""
    auth_encryption_key: str = Field(default="", validation_alias="AUTH_ENCRYPT_KEY")

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
    database_pool_size: int = 5
    database_max_overflow: int = 5
    database_pool_timeout: int = 30
    database_pool_recycle: int = 1800
    care_admin_emails: str = ""
    intent_examples_path: Path = ROOT / "data" / "intent_examples.json"

    # Isolation Forest (Phase 7) — never used for medical diagnosis
    anomaly_contamination: float = 0.1

    @property
    def is_production(self) -> bool:
        return self.environment.strip().lower() in {"production", "prod"}

    def cors_origin_list(self) -> list[str]:
        origins = [origin.strip().rstrip("/") for origin in self.cors_origins.split(",") if origin.strip()]
        if origins:
            return origins
        # Keep local development behavior unchanged. Production is validated
        # before the application starts.
        return ["*"]

    def validate_production(self) -> None:
        if not self.is_production:
            return
        if not self.database_url:
            raise RuntimeError("DATABASE_URL is required when ENVIRONMENT=production.")
        if not self.cors_origins.strip():
            raise RuntimeError("CORS_ORIGINS is required when ENVIRONMENT=production.")
        if not self.auth_encryption_key.strip() or self.auth_encryption_key == "alzheimer-dev-key-change-in-prod":
            raise RuntimeError("AUTH_ENCRYPT_KEY must be set to a non-default value when ENVIRONMENT=production.")


def get_settings() -> Settings:
    return Settings()
