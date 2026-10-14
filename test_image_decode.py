import sys
sys.path.append('.')
from ai.vision.webcam import capture_jpeg_bytes
import cv2
import numpy as np
try:
    data = capture_jpeg_bytes()
    print("Length:", len(data))
    print("Start bytes:", data[:10])
    arr = np.frombuffer(data, np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    print("Decoded image:", img is not None)
    if img is None:
        print("Failed to decode!")
except Exception as e:
    print("Error:", e)
