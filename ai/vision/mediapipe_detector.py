"""MediaPipe face detection (Phase 4). Locates faces; does not identify people."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class FaceBox:
    x: float
    y: float
    width: float
    height: float
    score: float


class MediaPipeFaceDetector:
    def __init__(self) -> None:
        self._detector = None

    def load(self) -> None:
        if self._detector is not None:
            return
        import mediapipe as mp

        self._detector = mp.solutions.face_detection.FaceDetection(model_selection=0, min_detection_confidence=0.5)

    def detect(self, image_bgr) -> list[FaceBox]:
        self.load()
        import cv2

        assert self._detector is not None
        rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)
        results = self._detector.process(rgb)
        boxes: list[FaceBox] = []
        if not results.detections:
            return boxes
        height, width = image_bgr.shape[:2]
        for detection in results.detections:
            loc = detection.location_data.relative_bounding_box
            boxes.append(
                FaceBox(
                    x=loc.xmin * width,
                    y=loc.ymin * height,
                    width=loc.width * width,
                    height=loc.height * height,
                    score=float(detection.score[0]) if detection.score else 0.0,
                )
            )
        return boxes
