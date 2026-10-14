import sys
import httpx
import asyncio
from datetime import datetime

async def test_reminder_nlu():
    print("Testing Reminder NLU...")
    try:
        async with httpx.AsyncClient() as client:
            res = await client.post("http://127.0.0.1:8080/v1/text/turn", json={"text": "Set a reminder at 7:30 PM to meet a friend."}, timeout=10)
            print("Status:", res.status_code)
            if res.status_code == 200:
                print("Response:", res.json().get("reply_text"))
                print("Intent:", res.json().get("intent"))
                print("Facts:", res.json().get("facts"))
            else:
                print("Error:", res.text)
    except Exception as e:
        print("API Error:", e)

async def test_face_recognition():
    print("\nTesting Face Recognition...")
    try:
        async with httpx.AsyncClient() as client:
            res = await client.post("http://127.0.0.1:8080/v1/vision/recognize-camera", timeout=20)
            print("Status:", res.status_code)
            if res.status_code != 200:
                print("Error:", res.text)
            else:
                print("Success:", res.json().get("message"))
    except Exception as e:
        print("API Error:", e)

if __name__ == "__main__":
    asyncio.run(test_reminder_nlu())
    asyncio.run(test_face_recognition())
