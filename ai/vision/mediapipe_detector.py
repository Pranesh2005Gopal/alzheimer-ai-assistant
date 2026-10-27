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
    keypoints: dict[str, tuple[float, float]] | None = None


class MediaPipeFaceDetector:
    def __init__(self) -> None:
        self._detector = None

    def load(self) -> None:
        if self._detector is not None:
            return
        import mediapipe as mp

        self._detector = mp.solutions.face_detection.FaceDetection(model_selection=0, min_detection_confidence=0.5)
        # Face Mesh is optional at runtime (some minimal MediaPipe builds omit
        # it). Detection and recognition continue to work without it.
        self._mesh = getattr(mp.solutions, "face_mesh", None)
        if self._mesh is not None:
            self._mesh = self._mesh.FaceMesh(
                static_image_mode=True,
                max_num_faces=1,
                refine_landmarks=True,
                min_detection_confidence=0.5,
            )

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
                    keypoints={
                        name: (point.x, point.y)
                        for name, point in zip(
                            ("right_eye", "left_eye", "nose", "mouth", "right_ear", "left_ear"),
                            detection.location_data.relative_keypoints,
                        )
                    },
                )
            )
        return boxes

    def landmarks(self, image_bgr) -> dict[str, list[tuple[float, float]]]:
        """Return real normalized FaceMesh points grouped for the UI.

        Empty groups mean the installed MediaPipe build does not expose mesh
        landmarks; callers must not fabricate points.
        """
        self.load()
        if self._mesh is None:
            return {}
        import cv2

        result = self._mesh.process(cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB))
        if not result.multi_face_landmarks:
            return {}
        points = result.multi_face_landmarks[0].landmark
        groups = {
            "outline": (10, 109, 67, 103, 54, 21, 162, 127, 234, 93, 132, 58, 172, 136, 150, 176, 148, 152, 377, 400, 378, 365, 397, 356, 454, 323, 361, 288, 397, 365, 454),
            "left_eye": (33, 160, 158, 133, 153, 144),
            "right_eye": (362, 385, 387, 263, 373, 380),
            "left_eyebrow": (70, 63, 105, 66, 107),
            "right_eyebrow": (336, 296, 334, 293, 300),
            "nose": (168, 6, 197, 195, 5, 4),
            "mouth": (61, 40, 0, 267, 291, 17, 14, 87),
            "jawline": (234, 93, 132, 58, 172, 136, 150, 176, 148, 152, 377, 400, 378, 365, 454),
            "chin": (175, 152, 199),
        }
        return {
            name: [(points[i].x, points[i].y) for i in indexes]
            for name, indexes in groups.items()
            if all(i < len(points) for i in indexes)
        }
