import sys
import httpx
import asyncio

async def test_audio():
    async with httpx.AsyncClient() as client:
        res = await client.post("http://127.0.0.1:8080/v1/text/turn", json={"text": "hello"}, timeout=10)
        data = res.json()
        audio = data.get("audio_wav_base64", "")
        print("Audio length:", len(audio))

if __name__ == "__main__":
    asyncio.run(test_audio())
