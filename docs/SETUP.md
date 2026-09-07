# Setup (local, no paid APIs)

Use **Python 3.11 or 3.12** for the backend. System Python 3.14 is too new for Whisper, Coqui TTS, spaCy, and PyTorch wheels.

Working directory: the repository root. All Python commands need:

```bash
export PYTHONPATH="$(pwd)"
```

## 1. Flutter (PC and phone)

Flutter SDK is already used to generate `frontend/`.

```bash
cd frontend
flutter doctor
flutter pub get
flutter run -d linux          # PC
flutter run                   # pick an Android device / emulator
```

The app talks to `http://127.0.0.1:8080` on desktop and `http://10.0.2.2:8080` on the Android emulator.

Grant microphone permission when asked.

## 2. Python virtual environment

```bash
python3.12 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements-phase1.txt
python -m spacy download en_core_web_sm
```

Full stack (Chroma, MediaPipe, FaceNet, Isolation Forest):

```bash
pip install -r requirements.txt
```

System packages (Arch): `ffmpeg`, `espeak-ng`, `portaudio`, `git`, `base-devel`. Coqui TTS needs `espeak-ng`.

## 3. Whisper

Installed via `openai-whisper`. First transcription downloads the `base` model into the Hugging Face / Whisper cache. Override with `WHISPER_MODEL=small` if needed.

Where it runs: `ai/stt/whisper_stt.py`.

## 4. Ollama + Llama 3

```bash
# https://ollama.com — then:
ollama pull llama3
ollama run llama3 "Say hello in one short sentence."
```

The API uses `http://127.0.0.1:11434` and model name `llama3`. Change with `OLLAMA_HOST` and `OLLAMA_MODEL`.

Where it runs: `ai/llm/ollama_llama.py`.

## 5. Coqui TTS

Installed via the `TTS` package. First spoken reply downloads `tts_models/en/ljspeech/tacotron2-DDC` (override with `COQUI_MODEL`).

Where it runs: `ai/tts/coqui_tts.py`.

## 6. spaCy

```bash
python -m spacy download en_core_web_sm
```

Where it runs: `ai/nlu/spacy_preprocessor.py`.

## 7. DistilBERT

```bash
python scripts/train_intent_classifier.py
```

This fine-tunes `distilbert-base-uncased` on `data/intent_examples.json` and writes `data/models/distilbert-intent/`.

If that folder is missing and `TRAIN_INTENT_IF_MISSING=true` (default), the first voice/text turn trains automatically (slow).

Where it runs: `ai/nlu/distilbert_intent.py`.

## 8. Duckling

Duckling is a separate HTTP service, not a Python model.

```bash
docker run --rm -p 8000:8000 rasa/duckling
```

The backend posts to `http://127.0.0.1:8000/parse`. If Duckling is down, time slots stay empty and reminders may store `unspecified` time — start Duckling for the CREATE_REMINDER demo.

Where it runs: `ai/nlu/duckling_temporal.py`.

## 9. MediaPipe

`pip install mediapipe` (included in `requirements.txt`). Used in Phase 4 to locate faces.

Where it runs: `ai/vision/mediapipe_detector.py`.

## 10. FaceNet

`pip install facenet-pytorch` (included in `requirements.txt`). Used in Phase 4 to embed and match faces. Do not claim 100% accuracy.

Where it runs: `ai/vision/facenet_embedder.py`, `ai/vision/recognizer.py`.

## 11. Chroma

`pip install chromadb`. Phase 3 replaces `NullSemanticMemory` in `backend/container.py` with `ChromaSemanticMemory`.

Where it runs: `ai/memory/chroma_store.py`.

## 12. Isolation Forest

`scikit-learn`, Phase 7. Activity features only. No medical diagnosis.

Where it runs: `ai/anomaly/isolation_forest.py`.

## Run Phase 1

Terminal A — Duckling (optional but needed for clock times):

```bash
docker run --rm -p 8000:8000 rasa/duckling
```

Terminal B — Ollama must already be running.

Terminal C — API:

```bash
source .venv/bin/activate
export PYTHONPATH="$(pwd)"
python scripts/train_intent_classifier.py   # once
bash scripts/run_backend.sh
```

Check: `curl http://127.0.0.1:8080/health`

Text smoke test (still returns spoken WAV):

```bash
curl -s http://127.0.0.1:8080/v1/text/turn \
  -H 'Content-Type: application/json' \
  -d '{"text":"Who is Arun?"}' | python -c "import sys,json; print(json.load(sys.stdin)['reply_text'])"
```

Terminal D — Flutter:

```bash
cd frontend
flutter run -d linux
```

Press **TALK**, speak, wait for **Speaking**. Every speech turn is played back through the speaker.
