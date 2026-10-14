import sys
import unittest.mock as mock
import pytest
import time
import base64
from datetime import datetime, timedelta

# Minimal mock for heavy dependencies not needed for business logic tests
for mod in ['numpy', 'cv2', 'facenet_pytorch', 'torch', 'mediapipe']:
    if mod not in sys.modules:
        sys.modules[mod] = mock.MagicMock()

from models.domain import Person, Reminder, ReminderKind, ReminderStatus
from models.nlu import NLUResult
from models.intents import Intent
from services.memory_service import MemoryService
from repositories.in_memory import InMemoryMemoryRepository, InMemoryReminderRepository
from services.reminder_manager import ReminderManager
from ai.vision.recognizer import FaceRecognizer, RecognitionResult

def test_person_memory_responses():
    repo = InMemoryMemoryRepository()
    repo.add_person(Person(id='1', name='Raju', relationship='son', notes=''))
    ms = MemoryService(repo, None)

    nlu = NLUResult(raw_text='who is Raju', normalized_text='who is Raju', intent=Intent.ASK_PERSON_IDENTITY, intent_confidence=1.0, spacy={})
    assert "Raju is your son." in ms.identify(nlu)

    nlu_unknown = NLUResult(raw_text='who is Arun', normalized_text='who is Arun', intent=Intent.ASK_PERSON_IDENTITY, intent_confidence=1.0, spacy={})
    assert "I don't have information about who Arun is." in ms.identify(nlu_unknown)

def test_face_recognition_responses():
    repo = InMemoryMemoryRepository()
    ram = Person(id='2', name='Ram', relationship='brother', notes='')
    repo.add_person(ram)
    ms = MemoryService(repo, None)

    assert "This is Ram, your brother." in ms.spoken_face_identity(ram, False)
    assert "I don't recognize this person." in ms.spoken_face_identity(None, True)

@mock.patch('time.time')
def test_debounce_behavior(mock_time):
    repo = InMemoryMemoryRepository()
    ram = Person(id='2', name='Ram', relationship='brother', notes='', face_embedding=[0.1, 0.2])
    repo.add_person(ram)
    
    recognizer = FaceRecognizer(repo)
    recognizer.detector.detect = mock.MagicMock(return_value=[mock.MagicMock(y=0, x=0, height=10, width=10)])
    recognizer.embedder.embed = mock.MagicMock(return_value=[0.1, 0.2])
    
    dummy_img = mock.MagicMock()
    dummy_img.__getitem__.return_value = mock.MagicMock(size=100)
    
    mock_time.return_value = 1000.0
    
    with mock.patch('ai.vision.facenet_embedder.FaceNetEmbedder.cosine_similarity', return_value=0.99):
        # 1. Announce first time
        res1 = recognizer.recognize_image(dummy_img)
        assert "Ram" in res1.message
        
        # 2. Debounce immediate repeat
        mock_time.return_value = 1010.0
        res2 = recognizer.recognize_image(dummy_img)
        assert res2.message == ""
    
    with mock.patch('ai.vision.facenet_embedder.FaceNetEmbedder.cosine_similarity', return_value=0.1):
        # 3. New person (unknown) announced immediately
        mock_time.return_value = 1015.0
        res3 = recognizer.recognize_image(dummy_img)
        assert "I don't recognize this person" in res3.message
        
        # 4. Debounce new person
        mock_time.return_value = 1020.0
        res4 = recognizer.recognize_image(dummy_img)
        assert res4.message == ""
        
    with mock.patch('ai.vision.facenet_embedder.FaceNetEmbedder.cosine_similarity', return_value=0.99):
        # 5. Expire debounce for original person 
        mock_time.return_value = 1046.0 # 31 seconds after last unknown, but 46s since Ram
        res5 = recognizer.recognize_image(dummy_img)
        assert "Ram" in res5.message


def test_reminders_and_tts_invocation():
    repo = InMemoryReminderRepository()
    rm = ReminderManager(repo)
    text = "Remind me to take my medicine at 8 PM"
    reminder = rm.create_from_utterance(text, None)
    
    # Test due behavior
    now = datetime.now()
    reminder.time_iso = (now - timedelta(minutes=5)).isoformat(timespec="seconds")
    repo.update(reminder)
    
    due = rm.activate_due_if_needed(now)
    assert due is not None
    assert due.id == reminder.id
    
    due_text = rm.spoken_due(due)
    assert "This is your reminder to take your medicine." in due_text

    # Test TTS invocation path simulation
    mock_tts = mock.MagicMock()
    mock_tts.speak.return_value = b'audio bytes'
    
    needs_speech = rm.needs_speech(due.id)
    assert needs_speech is True
    
    audio = mock_tts.speak(due_text)
    encoded = base64.b64encode(audio).decode("ascii")
    assert encoded == base64.b64encode(b'audio bytes').decode("ascii")
    
    rm.mark_speech_sent(due.id)
    assert rm.needs_speech(due.id) is False

