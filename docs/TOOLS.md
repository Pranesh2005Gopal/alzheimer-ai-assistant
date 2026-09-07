# Whisper — Speech-to-Text (input)

Patient microphone audio is sent from Flutter to the backend. **OpenAI Whisper** transcribes that audio into text. No other STT engine is used.

Where: `ai/stt/whisper_stt.py`  
Phase: 1 (required)

# spaCy — NLP preprocessing and named entities

After Whisper, **spaCy** tokenizes the sentence, lemmatizes words, and extracts named entities (people, dates mentioned in text). This prepares a clean document for DistilBERT and the dialogue manager. spaCy does **not** decide the intent.

Where: `ai/nlu/spacy_preprocessor.py`  
Phase: 1 (required)

# DistilBERT — Intent classification

**DistilBERT** (`distilbert-base-uncased` with a classification head) maps the sentence to one label:

`CREATE_REMINDER`, `DELETE_REMINDER`, `CHECK_REMINDER`, `CHECK_MEDICATION`, `CHECK_APPOINTMENT`, `CREATE_APPOINTMENT`, `ASK_PERSON_IDENTITY`, `ASK_MEMORY`, `STORE_MEMORY`, `ASK_DAILY_ROUTINE`, `CHECK_TIME`, `CHECK_DATE`, `MAKE_CALL`, `EMERGENCY`, `GENERAL_CONVERSATION`, `UNKNOWN`

The LLM is not used to classify intent.

Where: `ai/nlu/distilbert_intent.py`  
Train: `scripts/train_intent_classifier.py`  
Phase: 1 (required)

# Duckling — Dates, times, durations

**Duckling** parses temporal expressions such as “8 tonight”, “tomorrow”, “in 10 minutes”. It runs as a small HTTP service. The reminder and appointment managers consume its structured time values. DistilBERT does not parse clocks.

Where: `ai/nlu/duckling_temporal.py`  
Phase: 1 (required for time-slot filling; install the Duckling server)

# Dialogue Manager — Conversation control

A deterministic state machine. It reads DistilBERT’s intent + Duckling slots + spaCy entities, then calls application services (reminders, memory, emergency). It never lets Llama write patient data. For `GENERAL_CONVERSATION` it asks Llama only to talk.

Where: `ai/dialogue/manager.py`  
Phase: 1 (required)

# Llama 3 (Ollama) — Natural language only

**Llama 3** runs locally through **Ollama**. It:

- Speaks in calm, short sentences
- Rephrases structured facts (appointment at 10:00 → “Your next doctor’s appointment is tomorrow at 10 AM”)
- Handles chit-chat

It must **not** create reminders, mark medicine taken, or change appointments by itself.

Where: `ai/llm/ollama_llama.py`  
Phase: 1 (required)

# Coqui TTS — Speech output

Every assistant reply is sent to **Coqui TTS** and played on the device speaker. Flutter does not use a second TTS engine. If the patient spoke, they get audio back.

Where: `ai/tts/coqui_tts.py`  
Phase: 1 (required)

# Chroma — Semantic long-term memory (RAG)

**Chroma** stores embeddings of long-term memories, important conversation snippets, and preferences. Query → embedding → Chroma search → facts → Dialogue Manager / Llama.

Structured people/dates still go through `MemoryRepository`. Chroma is the vector index, not the only store.

Where: `ai/memory/chroma_store.py`  
Phase: 3 (class is present; voice pipeline uses structured mock memory in Phase 1)

# MediaPipe — Face detection

**MediaPipe** finds faces in camera frames (bounding boxes). It does not identify who the person is.

Where: `ai/vision/mediapipe_detector.py`  
Phase: 4

# FaceNet — Face embeddings and matching

**FaceNet** turns a cropped face into an embedding and compares it with registered people. Unknown faces are reported as unknown. Accuracy is not claimed to be 100%.

Where: `ai/vision/facenet_embedder.py`, `ai/vision/recognizer.py`  
Phase: 4

# Isolation Forest — Unusual activity (not diagnosis)

**Isolation Forest** (scikit-learn) looks at activity features: interactions per day, repeated questions, missed medications, odd hours. It may emit “Unusual activity detected.” It must **never** be used to diagnose Alzheimer’s.

Where: `ai/anomaly/isolation_forest.py`  
Phase: 7

# Flutter + Dart — Patient and (later) caregiver UI

Cross-platform **PC and phone**. Patient UI: large TALK button, little text, high contrast. Voice is the primary input. Caregiver UI is a later phase and stays more detailed.

Where: `frontend/`  
Phase: 1 patient home; Phase 5 dashboard; Phase 6 caregiver

# Application repositories (no permanent database yet)

Interfaces only: `MemoryRepository`, `ReminderRepository`, `AppointmentRepository`, `PatientRepository`, `ActivityRepository`. Phase 1 uses in-memory mocks plus `data/seed.json`. Later you can attach SQLite, PostgreSQL, MongoDB, or persistent Chroma without rewriting services.
