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
    landmarks: dict[str, list[tuple[float, float]]] | None = None
    quality_feedback: str = ""
    image_width: int = 0
    image_height: int = 0


@dataclass
class FaceValidation:
    box: object | None
    landmarks: dict[str, list[tuple[float, float]]]
    feedback: str = ""


class FaceRecognizer:
    def __init__(self, memory: InMemoryMemoryRepository, match_threshold: float = 0.70) -> None:
        self.memory = memory
        self.detector = MediaPipeFaceDetector()
        self.embedder = FaceNetEmbedder()
        self.match_threshold = match_threshold

    def recognize_image(self, image_bgr) -> RecognitionResult:
        validation = self.validate_image(image_bgr, require_guide=True)
        if validation.feedback:
            return RecognitionResult(None, 0.0, True, validation.feedback,
                                     validation.landmarks, validation.feedback)
        assert validation.box is not None
        crop = _aligned_face_crop(image_bgr, validation.box, validation.landmarks)
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
                return RecognitionResult(stored, max(best_score, 0.0) if unknown else best_score, unknown, "", validation.landmarks)
        
        self._last_identity = current_identity
        self._last_time = now

        return RecognitionResult(
            stored,
            max(best_score, 0.0) if unknown else best_score,
            unknown,
            self._spoken_identity(stored, unknown),
            validation.landmarks,
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
        result = self.recognize_image(image_bgr)
        result.image_height, result.image_width = image_bgr.shape[:2]
        return result

    def register_person(self, person: Person, image_bgr) -> Person:
        validation = self.validate_image(image_bgr, require_guide=False)
        if validation.feedback:
            raise ValueError(validation.feedback)
        assert validation.box is not None
        crop = _aligned_face_crop(image_bgr, validation.box, validation.landmarks)
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

    def validate_image(self, image_bgr, *, require_guide: bool = True) -> FaceValidation:
        """Apply the same capture rules to scanner frames and gallery files."""
        try:
            boxes = self.detector.detect(image_bgr)
        except Exception:  # detector/model failures must fail closed
            return FaceValidation(None, {}, "Face detection is unavailable. Please try again.")
        if not boxes:
            return FaceValidation(None, {}, "No face detected. Center one face in the guide.")
        if len(boxes) != 1:
            return FaceValidation(None, {}, "Only one face can be registered at a time.")
        box = boxes[0]
        try:
            landmarks = self.detector.landmarks(image_bgr)
        except Exception:
            landmarks = {}
        if not landmarks and getattr(box, "keypoints", None):
            # FaceDetection's six keypoints are model-produced landmarks, not
            # inferred from the bounding box. They provide a safe fallback on
            # deployments whose MediaPipe build lacks FaceMesh.
            keypoints = box.keypoints
            landmarks = {
                "left_eye": [keypoints["left_eye"]],
                "right_eye": [keypoints["right_eye"]],
                "nose": [keypoints["nose"]],
                "mouth": [keypoints["mouth"]],
            }
        feedback = _position_feedback(
            box, image_bgr.shape[:2], landmarks, require_guide=require_guide)
        if feedback:
            return FaceValidation(box, landmarks, feedback)
        # Measure image quality before affine eye alignment. Rotating a good
        # JPEG softens pixels at its border and previously caused false blur
        # rejections during registration.
        feedback = _quality_feedback(_face_crop(image_bgr, box), image_bgr.shape[:2])
        return FaceValidation(box, landmarks, feedback)


def _decode_image(image_bytes: bytes):
    import cv2
    import numpy as np

    arr = np.frombuffer(image_bytes, np.uint8)
    return cv2.imdecode(arr, cv2.IMREAD_COLOR)


def _quality_feedback(face_bgr, image_shape: tuple[int, int]) -> str:
    """Reject captures that cannot produce a dependable template."""
    try:
        import cv2

        image_h, image_w = image_shape
        face_h, face_w = face_bgr.shape[:2]
        if min(face_h, face_w) < 80 or face_h * face_w < image_h * image_w * 0.04:
            return "Move closer so your face fills the oval."
        gray = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2GRAY)
        if float(gray.mean()) < 45:
            return "The face is too dark. Please improve the lighting."
        # At a face crop this is deliberately conservative: a threshold of 35
        # rejects ordinary smooth, well-focused portraits.  Values below 12
        # consistently indicate motion/defocus while retaining real checks.
        if float(cv2.Laplacian(gray, cv2.CV_64F).var()) < 12:
            return "The image is blurry. Hold still and try again."
    except (TypeError, ValueError, AttributeError):
        # Keeps lightweight unit tests and optional image backends usable.
        return ""
    return ""


def _position_feedback(box, image_shape: tuple[int, int], landmarks: dict[str, list[tuple[float, float]]], *, require_guide: bool) -> str:
    """Validate the oval-safe region and real mesh landmarks, never a box alone."""
    try:
        height, width = image_shape
        left, top = box.x / width, box.y / height
        right, bottom = (box.x + box.width) / width, (box.y + box.height) / height
        face_width = box.width / width
    except (TypeError, ValueError, ZeroDivisionError):
        return ""
    # The guide is a central 62% x 72% oval.  This rectangular inner margin
    # deliberately rejects edge/cropped faces before a template is created.
    if require_guide and (left < .22 or right > .78 or top < .16 or bottom > .84):
        return "Center your face in the oval."
    if face_width < .20:
        return "Move closer so your face fills the guide."
    if face_width > .58:
        return "Move back so your whole face fits in the guide."
    left_eye, right_eye = landmarks.get("left_eye"), landmarks.get("right_eye")
    if not left_eye or not right_eye:
        return "Keep both eyes visible and look at the camera."
    lx = sum(x for x, _ in left_eye) / len(left_eye)
    ly = sum(y for _, y in left_eye) / len(left_eye)
    rx = sum(x for x, _ in right_eye) / len(right_eye)
    ry = sum(y for _, y in right_eye) / len(right_eye)
    eye_distance = abs(rx - lx)
    if eye_distance < .10:
        return "Move closer and keep both eyes visible."
    import math
    if abs(math.degrees(math.atan2(ry - ly, rx - lx))) > 12:
        return "Look straight at the camera and keep your head level."
    nose = landmarks.get("nose")
    if not nose:
        return "Look straight at the camera."
    nose_x = sum(x for x, _ in nose) / len(nose)
    if abs(nose_x - (lx + rx) / 2) > eye_distance * .32:
        return "Look straight at the camera."
    return ""


def _aligned_face_crop(image_bgr, box, landmarks):
    """Level the detected eye line before FaceNet embedding when mesh is available."""
    import cv2
    import math

    y1, x1 = max(0, int(box.y)), max(0, int(box.x))
    try:
        y2, x2 = min(image_bgr.shape[0], y1 + int(box.height)), min(image_bgr.shape[1], x1 + int(box.width))
        crop = image_bgr[y1:y2, x1:x2]
    except TypeError:
        return image_bgr[y1:y1 + int(box.height), x1:x1 + int(box.width)]
    try:
        left, right = landmarks["left_eye"], landmarks["right_eye"]
        lx = sum(p[0] for p in left) / len(left) * image_bgr.shape[1]
        ly = sum(p[1] for p in left) / len(left) * image_bgr.shape[0]
        rx = sum(p[0] for p in right) / len(right) * image_bgr.shape[1]
        ry = sum(p[1] for p in right) / len(right) * image_bgr.shape[0]
        angle = math.degrees(math.atan2(ry - ly, rx - lx))
        matrix = cv2.getRotationMatrix2D(((lx + rx) / 2, (ly + ry) / 2), angle, 1.0)
        rotated = cv2.warpAffine(image_bgr, matrix, (image_bgr.shape[1], image_bgr.shape[0]))
        crop = rotated[y1:y2, x1:x2]
    except (KeyError, TypeError, ValueError, ZeroDivisionError):
        pass
    return crop


def _face_crop(image_bgr, box):
    """Unrotated bounded crop used only for lighting/sharpness checks."""
    y1, x1 = max(0, int(box.y)), max(0, int(box.x))
    y2 = min(image_bgr.shape[0], y1 + int(box.height))
    x2 = min(image_bgr.shape[1], x1 + int(box.width))
    return image_bgr[y1:y2, x1:x2]
