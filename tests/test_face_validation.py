"""Focused face-capture validation tests (standard-library runner compatible)."""

from types import SimpleNamespace
import unittest

from ai.vision.recognizer import FaceRecognizer, _position_feedback
from repositories.in_memory import InMemoryMemoryRepository


def _landmarks():
    return {
        "left_eye": [(0.40, 0.40)],
        "right_eye": [(0.60, 0.40)],
        "nose": [(0.50, 0.50)],
        "mouth": [(0.50, 0.60)],
    }


class FaceValidationTests(unittest.TestCase):
    def setUp(self):
        self.centered = SimpleNamespace(x=220, y=80, width=200, height=300)

    def test_centered_face_with_both_detected_eyes_is_position_valid(self):
        self.assertEqual(_position_feedback(self.centered, (480, 640), _landmarks(), require_guide=True), "")

    def test_face_outside_guide_is_rejected(self):
        outside = SimpleNamespace(x=5, y=80, width=200, height=300)
        self.assertIn("Center", _position_feedback(outside, (480, 640), _landmarks(), require_guide=True))

    def test_missing_eye_landmark_is_rejected(self):
        bad = _landmarks()
        bad.pop("right_eye")
        self.assertIn("eyes", _position_feedback(self.centered, (480, 640), bad, require_guide=False))

    def test_no_face_and_multiple_faces_fail_closed(self):
        recognizer = FaceRecognizer(InMemoryMemoryRepository())
        recognizer.detector.detect = lambda _: []
        no_face = recognizer.validate_image(object())
        self.assertIn("No face", no_face.feedback)
        recognizer.detector.detect = lambda _: [self.centered, self.centered]
        multiple = recognizer.validate_image(object())
        self.assertIn("Only one", multiple.feedback)


if __name__ == "__main__":
    unittest.main()
