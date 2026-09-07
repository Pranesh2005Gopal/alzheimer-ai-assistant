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
            return RecognitionResult(
                None,
                max(best_score, 0.0),
                True,
                "I am not sure who this is. I do not want to guess.",
            )
        return RecognitionResult(
            best,
            best_score,
            False,
            f"This is {best.name}. They are your {best.relationship}.",
        )

    def register_person(self, person: Person, image_bgr) -> Person:
        boxes = self.detector.detect(image_bgr)
        if not boxes:
            raise ValueError("No face detected for registration.")
        box = boxes[0]
        y1, x1 = max(0, int(box.y)), max(0, int(box.x))
        crop = image_bgr[y1 : y1 + int(box.height), x1 : x1 + int(box.width)]
        import cv2

        rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
        person.face_embedding = self.embedder.embed(rgb)
        return self.memory.add_person(person)
