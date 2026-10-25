FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app

# ffmpeg is used for uploaded microphone audio; espeak-ng and the shared
# libraries support the existing Coqui, MediaPipe, OpenCV, and PyTorch stack.
RUN apt-get update \
    && apt-get install --no-install-recommends -y ffmpeg espeak-ng libgl1 libglib2.0-0 libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt \
    && python -m spacy download en_core_web_sm

COPY . ./

EXPOSE 8080

CMD ["uvicorn", "backend.app:app", "--host", "0.0.0.0", "--port", "8080"]
