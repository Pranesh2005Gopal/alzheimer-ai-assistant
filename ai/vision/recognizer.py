"""Identify a detected face against MemoryRepository people (Phase 4)."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from models.domain import Person
from repositories.in_memory import InMemoryMemoryRepository

from ai.vision.facenet_embedder import FaceNetEmbedder
from ai.vision.mediapipe_detector import MediaPipeFaceDetector


@dataclass
class RecognitionResult:
    person: Optional[Person]
    score: float
    unknown: bool
    message: str


class FaceRecognizer:
    def __init__(self, memory: InMemoryMemoryRepository, match_threshold: float = 0.70) -> None:
        self.memory = memory
        self.detector = MediaPipeFaceDetector()
        self.embedder = FaceNetEmbedder()
        self.match_threshold = match_threshold

    def recognize_image(self, image_bgr) -> RecognitionResult:
        boxes = self.detector.detect(image_bgr)
        if not boxes:
            return RecognitionResult(None, 0.0, True, "I cannot see a face clearly.")
        box = boxes[0]
        y1, x1 = max(0, int(box.y)), max(0, int(box.x))
        y2, x2 = y1 + int(box.height), x1 + int(box.width)
        crop = image_bgr[y1:y2, x1:x2]
        if crop.size == 0:
            return RecognitionResult(None, 0.0, True, "I cannot see a face clearly.")
        import cv2

        rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
        embedding = self.embedder.embed(rgb)
        best: Optional[Person] = None
        best_score = -1.0
        for person in self.memory.list_people():
            if not person.face_embedding:
                continue
            score = FaceNetEmbedder.cosine_similarity(embedding, person.face_embedding)
            if score > best_score:
                best_score = score
                best = person
        if best is None or best_score < self.match_threshold:
            stored = None
            unknown = True
            current_identity = "unknown"
        else:
            stored = self.memory.get_person_by_name(best.name) or best
            unknown = False
            current_identity = stored.name

        import time
        now = time.time()
        # Debounce for 30 seconds
        if hasattr(self, "_last_identity") and self._last_identity == current_identity:
            if hasattr(self, "_last_time") and now - self._last_time < 30:
                # Return empty message to indicate skipped speech
                return RecognitionResult(stored, max(best_score, 0.0) if unknown else best_score, unknown, "")
        
        self._last_identity = current_identity
        self._last_time = now

        return RecognitionResult(
            stored,
            max(best_score, 0.0) if unknown else best_score,
            unknown,
            self._spoken_identity(stored, unknown),
        )

    def _spoken_identity(self, person: Optional[Person], unknown: bool) -> str:
        if unknown or person is None:
            return "I don't recognize this person."
        stored = self.memory.get_person_by_name(person.name) or person
        relationship = (stored.relationship or "").strip()
        if relationship:
            return f"This is {stored.name}, your {relationship}."
        return f"This is {stored.name}, but I don't have information about their relationship to you."

    def recognize_bytes(self, image_bytes: bytes) -> RecognitionResult:
        image_bgr = _decode_image(image_bytes)
        if image_bgr is None:
            return RecognitionResult(None, 0.0, True, "I could not read that photo.")
        return self.recognize_image(image_bgr)

    def register_person(self, person: Person, image_bgr) -> Person:
        boxes = self.detector.detect(image_bgr)
        if not boxes:
            raise ValueError("No face detected for registration.")
        box = boxes[0]
        y1, x1 = max(0, int(box.y)), max(0, int(box.x))
        crop = image_bgr[y1 : y1 + int(box.height), x1 : x1 + int(box.width)]
        if crop.size == 0:
            raise ValueError("No face detected for registration.")
        import cv2

        rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
        person.face_embedding = self.embedder.embed(rgb)
        return self.memory.add_person(person)

    def register_person_bytes(self, person: Person, image_bytes: bytes) -> Person:
        image_bgr = _decode_image(image_bytes)
        if image_bgr is None:
            raise ValueError("Could not decode the provided image.")
        return self.register_person(person, image_bgr)


def _decode_image(image_bytes: bytes):
    import cv2
    import numpy as np

    arr = np.frombuffer(image_bytes, np.uint8)
    return cv2.imdecode(arr, cv2.IMREAD_COLOR)
