import httpx
import base64
from fastapi.testclient import TestClient
from backend.app import app

client = TestClient(app)

def test_text_turn():
    res = client.post("/v1/text/turn", json={"text": "who is Raju?"})
    print("Text turn status:", res.status_code)
    data = res.json()
    print("Text turn response message:", data.get("reply_text"))
    print("Text turn audio base64 length:", len(data.get("audio_wav_base64", "")))
    return data

def test_camera_recognition():
    res = client.post("/v1/vision/recognize-camera")
    print("Camera recognition status:", res.status_code)
    if res.status_code == 200:
        data = res.json()
        print("Camera recognition message:", data.get("message"))
        print("Camera recognition recognized:", data.get("recognized"))
        print("Camera audio base64 length:", len(data.get("audio_wav_base64", "")))
    else:
        print("Camera recognition error:", res.text)

if __name__ == "__main__":
    test_text_turn()
    test_camera_recognition()
