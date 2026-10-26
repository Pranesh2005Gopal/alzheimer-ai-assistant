from pathlib import Path

from repositories.postgres import (
    PostgresRepositoryBundle,
    get_caregiver_profile,
    list_caregiver_assignments,
    sync_caregiver_assignment,
    upsert_caregiver_profile,
)


def test_caregiver_profile_and_multiple_assignments_persist(tmp_path):
    """The caregiver-only relational data survives a new repository instance."""
    database_url = f"sqlite:///{tmp_path / 'care.db'}"
    seed_path = Path(__file__).resolve().parents[1] / "data" / "seed.json"
    bundle = PostgresRepositoryBundle(database_url, "patient-a", seed_path)

    saved = upsert_caregiver_profile(bundle.factory, "caregiver-a", {
        "designation": "Registered Nurse",
        "specialization": "Dementia care",
        "organization": "Memory Clinic",
        "professional_email": "nurse@example.test",
    })
    assert saved["designation"] == "Registered Nurse"
    sync_caregiver_assignment(bundle.factory, "caregiver-a", "patient-a", ["care_data"])
    sync_caregiver_assignment(bundle.factory, "caregiver-a", "patient-b", ["private_info"])

    reopened = PostgresRepositoryBundle(database_url, "patient-a", seed_path)
    assert get_caregiver_profile(reopened.factory, "caregiver-a")["organization"] == "Memory Clinic"
    assert {row["patient_id"] for row in list_caregiver_assignments(reopened.factory, "caregiver-a")} == {"patient-a", "patient-b"}
