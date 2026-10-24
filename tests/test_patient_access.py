import pytest
from fastapi import HTTPException

import backend.auth.dependencies as dependencies


def test_patient_can_access_only_self():
    user = {"id": "patient-a", "role": "patient"}
    assert dependencies.get_patient_access(None, user).patient_id == "patient-a"
    with pytest.raises(HTTPException) as error:
        dependencies.get_patient_access("patient-b", user)
    assert error.value.status_code == 403


def test_caregiver_requires_explicit_authorized_link(monkeypatch):
    user = {"id": "caregiver-a", "role": "caregiver"}
    with pytest.raises(HTTPException) as missing:
        dependencies.get_patient_access(None, user)
    assert missing.value.status_code == 400
    monkeypatch.setattr(dependencies, "get_caregiver_permissions", lambda patient, caregiver: [])
    with pytest.raises(HTTPException) as denied:
        dependencies.get_patient_access("patient-a", user)
    assert denied.value.status_code == 403
    monkeypatch.setattr(dependencies, "get_caregiver_permissions", lambda patient, caregiver: ["care_data"])
    assert dependencies.get_patient_access("patient-a", user).patient_id == "patient-a"
