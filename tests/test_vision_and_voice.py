from backend.app import app
from backend.container import get_container
from fastapi.testclient import TestClient
from models.domain import Person
from ai.vision.recognizer import FaceRecognizer


def test_vision_people_endpoint():
    client = TestClient(app)
    response = client.get("/v1/vision/people")
    assert response.status_code == 200
    data = response.json()
    assert len(data) >= 3
    names = [p["name"] for p in data]
    assert "Arun" in names
    assert "Priya" in names
    assert "Dr. Kumar" in names


def test_recognizer_does_not_guess_invalid_photo():
    result = get_container().recognizer.recognize_bytes(b"not-an-image")
    assert result.unknown is True
    assert result.person is None
    assert "could not read" in result.message.lower() or "face" in result.message.lower()


def test_register_updates_existing_person_record():
    memory = get_container().repos.memory
    before = memory.get_person_by_name("Arun")
    assert before is not None
    original = list(before.face_embedding)
    person = Person(
        id=before.id,
        name=before.name,
        relationship=before.relationship,
        notes=before.notes,
        face_embedding=[0.1, 0.2, 0.3],
    )
    saved = memory.add_person(person)
    assert saved.id == before.id
    listed = [p for p in memory.list_people() if p.name == "Arun"]
    assert len(listed) == 1
    before.face_embedding = original
    memory.add_person(before)


def test_face_identity_uses_memory_relationship():
    memory = get_container().memory
    recognizer = FaceRecognizer(get_container().repos.memory)
    ram = memory.repo.get_person_by_name("Ram")
    assert ram is not None
    known = recognizer._spoken_identity(ram, False)
    assert known == "This is Ram, your brother."
    assert memory.spoken_face_identity(ram, False) == "This is Ram, your brother."
    unknown = recognizer._spoken_identity(None, True)
    assert unknown == "I don't recognize this person."
    assert memory.spoken_face_identity(None, True) == "I don't recognize this person."
