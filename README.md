# AI-Driven Voice Assistant System for Alzheimer's Patients

Local, modular assistant for PC and phone. The patient talks; the app always talks back.

Flutter is the UI. Python is the brain. No paid cloud APIs.

## Tools — which one does what

Read **[docs/TOOLS.md](docs/TOOLS.md)** for a full page per tool. Short map:

| Tool | Role | Not used for |
|---|---|---|
| **Whisper** | Speech → text | Intent, memory, speech output |
| **spaCy** | Tokens, lemmas, named entities | Intent labels, TTS |
| **DistilBERT** | Intent classification | Chit-chat wording, database writes |
| **Duckling** | Dates / times / durations | Intent, face ID |
| **Dialogue Manager** | Route intent → application services | Generating spoken style |
| **Llama 3 (Ollama)** | Calm wording, conversation, rephrasing facts | Creating reminders, changing appointments, marking meds taken |
| **Coqui TTS** | Text → speech on the speaker | Understanding the user |
| **Chroma** | Semantic long-term memory (Phase 3) | Structured people table |
| **MediaPipe** | Find faces in camera frames (Phase 4) | Naming the person |
| **FaceNet** | Face embeddings + match (Phase 4) | Medical claims; 100% accuracy |
| **Isolation Forest** | Unusual activity flag (Phase 7) | Diagnosing Alzheimer's |

## Conversation, memory, and reminders

```
Microphone → Whisper → spaCy + DistilBERT + Duckling
        → Dialogue Manager → services / mocks
        → Llama 3 wording → Coqui TTS → Speaker
```

Patient Flutter screen: greeting, date, large **TALK** button, next medicine, next appointment, family names, conversation lines, status.

Later phases are stubbed as real modules, not fake replacements of the tools above. See **[docs/PHASES.md](docs/PHASES.md)**.

## Layout

```
frontend/          Flutter (Android + Linux + Windows)
backend/           FastAPI (HTTP only)
ai/                Whisper, spaCy, DistilBERT, Duckling, dialogue, Llama, Coqui,
                   Chroma, MediaPipe, FaceNet, Isolation Forest
services/          Reminder, appointment, memory, emergency, activity, voice pipeline
models/            Intents and domain records
repositories/      Interfaces + in-memory mocks (no locked-in database)
utils/             Settings and audio helpers
tests/             Fast tests that do not need GPU models
data/              seed.json, DistilBERT training utterances
docs/              TOOLS, SETUP, PHASES
scripts/           train DistilBERT, run API
```

The local deployment persists mutable records in `data/assistant_state.json` and the most recent 50 conversation messages in `data/conversations.json`. Both files are written atomically and are ignored by Git. The seed file is read only on the first run; it is never overwritten.

Text and voice use the same pipeline. Reminders are created, updated, completed, and deleted through the reminder service before a confirmation is spoken. If the local LLM is unavailable, the assistant says so plainly instead of returning a misleading generic reply.

## Quick start

Follow **[docs/SETUP.md](docs/SETUP.md)**. You need Python 3.11/3.12, Flutter, Ollama (`llama3`), and (for times) Duckling on port 8000.

## Design rules (unchanged)

- If the patient speaks, Coqui TTS speaks back — including errors.
- Deterministic actions (reminders, appointments, emergency log) go through services.
- Llama 3 does not modify patient data.
- Conversation history ≠ long-term memory.
- Isolation Forest must never be presented as a diagnosis.
- Face recognition must not claim 100% accuracy.
