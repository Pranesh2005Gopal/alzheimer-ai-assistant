from __future__ import annotations

import base64
import math
from typing import List
from uuid import uuid4

import cv2
import numpy as np
from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from ai.vision.webcam import capture_jpeg_bytes
from backend.container import get_container
from models.domain import Person

router = APIRouter(tags=["vision"])


# ---------------------------------------------------------------------------
# Request / Response schemas
# ---------------------------------------------------------------------------

class CreatePersonBody(BaseModel):
    name: str
    relationship: str = "family"
    notes: str = ""


class UpdatePersonBody(BaseModel):
    name: str
    relationship: str = "family"
    notes: str = ""


def _person_to_dict(p: Person) -> dict:
    return {
        "id": p.id,
        "name": p.name,
        "relationship": p.relationship,
        "notes": p.notes,
        "has_face_profile": bool(p.face_embedding and len(p.face_embedding) > 0),
    }


@router.post("/vision/recognize")
async def recognize_face(image: UploadFile = File(...)) -> dict:
    """Identify a person from a camera photo and return identity plus spoken audio."""
    data = await image.read()
    if not data or len(data) < 100:
        raise HTTPException(status_code=400, detail="The provided image was empty or too small.")
    return _recognize(data)


@router.post("/vision/validate")
async def validate_face(image: UploadFile = File(...)) -> dict:
    """Validate a gallery image without running identity matching or TTS."""
    data = await image.read()
    if not data or len(data) < 100:
        raise HTTPException(status_code=400, detail="The provided image was empty or too small.")
    image_bgr = _decode_image_for_validation(data)
    if image_bgr is None:
        return {"usable": False, "quality_feedback": "Could not decode the selected image.", "landmarks": {}}
    validation = get_container().recognizer.validate_image(image_bgr, require_guide=False)
    height, width = image_bgr.shape[:2]
    return {
        "usable": not bool(validation.feedback),
        "quality_feedback": validation.feedback,
        "landmarks": validation.landmarks,
        "image_width": width,
        "image_height": height,
    }


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
    return [_person_to_dict(p) for p in container.repos.memory.list_people()]


@router.post("/vision/people")
def create_person(body: CreatePersonBody) -> dict:
    """Create a new person record (without a face embedding yet)."""
    container = get_container()
    existing = container.repos.memory.get_person_by_name(body.name)
    if existing is not None:
        return _person_to_dict(existing)
    person = Person(
        id=f"person-{body.name.lower().replace(' ', '-')}-{uuid4().hex[:6]}",
        name=body.name.strip(),
        relationship=body.relationship.strip() or "family",
        notes=body.notes.strip(),
    )
    saved = container.repos.memory.add_person(person)
    return _person_to_dict(saved)


@router.put("/vision/people/{person_id}")
def update_person(person_id: str, body: UpdatePersonBody) -> dict:
    """Update name, relationship and notes of an existing person."""
    container = get_container()
    person = container.repos.memory.get_person(person_id)
    if person is None:
        raise HTTPException(status_code=404, detail="Person not found.")
    person.name = body.name.strip() or person.name
    person.relationship = body.relationship.strip() or person.relationship
    person.notes = body.notes.strip()
    saved = container.repos.memory.update_person(person)
    return _person_to_dict(saved)


@router.delete("/vision/people/{person_id}")
def delete_person(person_id: str) -> dict:
    """Delete a person and their face embedding."""
    container = get_container()
    deleted = container.repos.memory.delete_person(person_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Person not found.")
    return {"status": "deleted", "person_id": person_id}


@router.delete("/vision/people/{person_id}/face")
def delete_person_face(person_id: str) -> dict:
    """Remove only the face embedding for a person, keeping the record."""
    container = get_container()
    person = container.repos.memory.get_person(person_id)
    if person is None:
        raise HTTPException(status_code=404, detail="Person not found.")
    person.face_embedding = []
    container.repos.memory.update_person(person)
    return {"status": "face_removed", "person_id": person_id}


@router.post("/vision/register-samples")
async def register_face_multi_sample(
    name: str = Form(...),
    relationship: str = Form(""),
    notes: str = Form(""),
    person_id: str = Form(""),
    images: List[UploadFile] = File(...),
) -> dict:
    """Register a person using multiple image samples (up to 6).

    Averages the FaceNet embeddings for a more robust face profile.
    """
    container = get_container()
    if not images:
        raise HTTPException(status_code=400, detail="At least one image is required.")
    if len(images) > 6:
        images = images[:6]

    embedder = container.recognizer.embedder
    detector = container.recognizer.detector

    all_embeddings: list[list[float]] = []
    for upload in images:
        raw = await upload.read()
        if not raw or len(raw) < 100:
            continue
        try:
            arr = np.frombuffer(raw, np.uint8)
            img_bgr = cv2.imdecode(arr, cv2.IMREAD_COLOR)
            if img_bgr is None:
                continue
            boxes = detector.detect(img_bgr)
            if not boxes:
                continue
            box = boxes[0]
            y1, x1 = max(0, int(box.y)), max(0, int(box.x))
            crop = img_bgr[y1 : y1 + int(box.height), x1 : x1 + int(box.width)]
            if crop.size == 0:
                continue
            face_rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
            emb = embedder.embed(face_rgb)
            if emb:
                all_embeddings.append(emb)
        except Exception:  # noqa: BLE001
            continue

    if not all_embeddings:
        raise HTTPException(status_code=400, detail="No face could be detected in any of the provided images.")

    # Average and L2-normalise
    dim = len(all_embeddings[0])
    avg = [sum(all_embeddings[i][d] for i in range(len(all_embeddings))) / len(all_embeddings) for d in range(dim)]
    norm = math.sqrt(sum(v * v for v in avg)) or 1.0
    normalised = [v / norm for v in avg]

    person = _resolve_person(name=name, relationship=relationship, notes=notes, person_id=person_id)
    person.face_embedding = normalised
    container.repos.memory.update_person(person) if container.repos.memory.get_person(person.id) else container.repos.memory.add_person(person)

    message = f"I will remember {person.name}, your {person.relationship}."
    audio = container.pipeline.tts.speak(message)
    return {
        "status": "registered",
        "person": person.model_dump(),
        "message": message,
        "audio_wav_base64": base64.b64encode(audio).decode("ascii"),
        "samples_used": len(all_embeddings),
    }


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
            "landmarks": result.landmarks or {},
            "quality_feedback": result.quality_feedback,
            "image_width": result.image_width,
            "image_height": result.image_height,
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
        "landmarks": result.landmarks or {},
        "quality_feedback": result.quality_feedback,
        "image_width": result.image_width,
        "image_height": result.image_height,
    }


def _decode_image_for_validation(data: bytes):
    array = np.frombuffer(data, np.uint8)
    return cv2.imdecode(array, cv2.IMREAD_COLOR)


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


# ---------------------------------------------------------------------------
# MJPEG camera stream – Linux/desktop live preview
# ---------------------------------------------------------------------------

def _mjpeg_frame_generator():
    """Yield multipart MJPEG frames from the first available /dev/videoX device.

    The Flutter desktop client polls this endpoint using HTTP chunked transfer.
    Each frame is encoded as a standard MJPEG multipart boundary so that
    Flutter can refresh an Image.memory widget at ~10 fps on Linux desktop
    without needing any extra native camera plugin.
    """
    import glob
    import time

    boundary = b"--frame\r\nContent-Type: image/jpeg\r\n\r\n"
    end = b"\r\n"

    devices = sorted(glob.glob("/dev/video*"))
    cap = None
    for dev in devices:
        candidate = cv2.VideoCapture(dev)
        if candidate.isOpened():
            cap = candidate
            break

    if cap is None:
        # Yield a single error placeholder frame and stop
        error_img = np.zeros((240, 320, 3), dtype=np.uint8)
        cv2.putText(
            error_img, "No camera", (60, 120),
            cv2.FONT_HERSHEY_SIMPLEX, 1.0, (255, 255, 255), 2,
        )
        _, buf = cv2.imencode(".jpg", error_img)
        yield boundary + buf.tobytes() + end
        return

    try:
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            _, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 70])
            yield boundary + buf.tobytes() + end
            time.sleep(0.1)  # ~10 fps
    finally:
        cap.release()


@router.get("/vision/stream")
def camera_stream() -> StreamingResponse:
    """MJPEG live stream from the PC webcam.  Intended for Flutter Linux desktop."""
    return StreamingResponse(
        _mjpeg_frame_generator(),
        media_type="multipart/x-mixed-replace;boundary=frame",
        headers={"Cache-Control": "no-cache"},
    )
