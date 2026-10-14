from __future__ import annotations

import base64
from uuid import uuid4

from fastapi import APIRouter, File, Form, HTTPException, UploadFile

from ai.vision.webcam import capture_jpeg_bytes
from backend.container import get_container
from models.domain import Person

router = APIRouter(tags=["vision"])


@router.post("/vision/recognize")
async def recognize_face(image: UploadFile = File(...)) -> dict:
    """Identify a person from a camera photo and return identity plus spoken audio."""
    data = await image.read()
    if not data or len(data) < 100:
        raise HTTPException(status_code=400, detail="The provided image was empty or too small.")
    return _recognize(data)


@router.post("/vision/recognize-camera")
def recognize_from_pc_camera() -> dict:
    """Capture the PC webcam on the backend machine, then identify the face."""
    try:
        data = capture_jpeg_bytes()
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return _recognize(data)


@router.post("/vision/register")
async def register_face(
    name: str = Form(...),
    relationship: str = Form(""),
    notes: str = Form(""),
    person_id: str = Form(""),
    image: UploadFile = File(...),
) -> dict:
    """Save a FaceNet embedding for an existing (or new) family member."""
    container = get_container()
    data = await image.read()
    if not data or len(data) < 100:
        raise HTTPException(status_code=400, detail="The provided image was empty or too small.")

    person = _resolve_person(name=name, relationship=relationship, notes=notes, person_id=person_id)
    try:
        saved = container.recognizer.register_person_bytes(person, data)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    message = f"I will remember {saved.name}, your {saved.relationship}."
    audio = container.pipeline.tts.speak(message)
    return {
        "status": "registered",
        "person": saved.model_dump(),
        "message": message,
        "audio_wav_base64": base64.b64encode(audio).decode("ascii"),
    }


@router.get("/vision/people")
def list_people_with_face_status() -> list[dict]:
    """List all people with indicator if a face profile exists."""
    container = get_container()
    return [
        {
            "id": p.id,
            "name": p.name,
            "relationship": p.relationship,
            "notes": p.notes,
            "has_face_profile": bool(p.face_embedding and len(p.face_embedding) > 0),
        }
        for p in container.repos.memory.list_people()
    ]


def _recognize(data: bytes) -> dict:
    container = get_container()
    result = container.recognizer.recognize_bytes(data)
    if result.message == "":
        return {
            "recognized": not result.unknown,
            "person": result.person.model_dump() if result.person else None,
            "score": result.score,
            "message": "",
            "audio_wav_base64": "",
        }
    if result.message.startswith("I cannot see") or result.message.startswith("I could not read"):
        message = result.message
    else:
        person = None
        if result.person is not None:
            person = container.memory.repo.get_person_by_name(result.person.name) or result.person
        message = container.memory.spoken_face_identity(person, result.unknown)
    audio = container.pipeline.tts.speak(message)
    container.activity.log(
        "vision",
        f"Face recognition: {message}",
        {"recognized": not result.unknown, "score": result.score},
    )
    return {
        "recognized": not result.unknown,
        "person": result.person.model_dump() if result.person else None,
        "score": result.score,
        "message": message,
        "audio_wav_base64": base64.b64encode(audio).decode("ascii"),
    }


def _resolve_person(name: str, relationship: str, notes: str, person_id: str) -> Person:
    container = get_container()
    people = container.repos.memory.list_people()
    if person_id:
        for person in people:
            if person.id == person_id:
                if relationship.strip():
                    person.relationship = relationship.strip()
                if notes.strip():
                    person.notes = notes.strip()
                return person
    existing = container.repos.memory.get_person_by_name(name)
    if existing is not None:
        if relationship.strip():
            existing.relationship = relationship.strip()
        if notes.strip():
            existing.notes = notes.strip()
        return existing
    return Person(
        id=f"person-{name.lower().replace(' ', '-')}-{uuid4().hex[:6]}",
        name=name.strip(),
        relationship=relationship.strip() or "family",
        notes=notes.strip(),
    )
