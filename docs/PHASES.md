# Development phases

Do not start a later phase until the previous phase works on this machine.

## Phase 1 — Voice pipeline (current)

Microphone (Flutter) → Whisper → spaCy + DistilBERT + Duckling → Dialogue Manager → Llama 3 (Ollama) → Coqui TTS → speaker.

Patient UI: TALK button, conversation text, spoken reply, status (Listening / Thinking / Speaking).

Mocks: `data/seed.json` loaded into in-memory repositories.

## Phase 2 — Reminder system

Scheduled spoken medication / appointment / daily-routine prompts, “Done.” completion, frequencies.

## Phase 3 — Memory assistance + Chroma

Wire `ChromaSemanticMemory` instead of `NullSemanticMemory`. Persist long-term notes, preferences, important conversation snippets. Keep conversation history separate.

## Phase 4 — Face recognition

Flutter camera → MediaPipe detect → FaceNet embed → match registered people → spoken identity. Register name + relationship + embedding. Unknown faces must not be guessed.

## Phase 5 — Patient dashboard

Today overview, activity logs, memory lists, alerts. Still large type and few controls.

## Phase 6 — Caregiver dashboard

Separate, denser view: activity, medication, appointments, routine, alerts, people, emergencies.

## Phase 7 — Isolation Forest

Activity features only. Output: “Unusual activity detected.” Never a medical diagnosis.

## Phase 8 — Emergency / safety

Confirmation flow is already sketched in the dialogue manager. Add real notify/SMS/call adapters behind `Notifier`.
