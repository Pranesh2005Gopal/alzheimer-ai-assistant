import sys
import os
import cv2
import numpy as np

sys.path.append('.')
from backend.container import get_container
from ai.vision.webcam import capture_jpeg_bytes
from backend.api.routes_vision import _recognize

try:
    data = capture_jpeg_bytes()
    print("Captured", len(data), "bytes")
    res = _recognize(data)
    print("Recognized!")
except Exception as e:
    import traceback
    traceback.print_exc()

