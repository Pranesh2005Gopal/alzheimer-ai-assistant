"""
Synthea synthetic patient data importer.
Imports from Synthea FHIR R4 JSON bundles (the standard Synthea output format).

Download Synthea output from: https://synthetichealth.github.io/downloads.html
Expected: a directory of FHIR JSON Bundle files, one per patient.

Usage:
    python -m backend.synthea_import <path_to_synthea_output_dir> <user_email>

This creates a demo patient account and populates their private medical
information from the first Synthea patient file found.

NEVER use real patient data. Synthea generates fully synthetic records.

Expected Synthea FHIR file structure (JSON Bundle):
{
  "resourceType": "Bundle",
  "entry": [
    {
      "resource": {
        "resourceType": "Patient",
        "name": [{"given": ["..."], "family": "..."}],
        "birthDate": "YYYY-MM-DD",
        ...
      }
    },
    {
      "resource": {
        "resourceType": "Condition",
        "code": {"text": "condition name"},
        ...
      }
    },
    {
      "resource": {
        "resourceType": "AllergyIntolerance",
        "code": {"text": "allergen name"},
        ...
      }
    },
    {
      "resource": {
        "resourceType": "MedicationRequest",
        "medicationCodeableConcept": {"text": "medication name"},
        "dosageInstruction": [{"text": "dosage"}],
        ...
      }
    },
    {
      "resource": {
        "resourceType": "Practitioner",
        "name": [{"given": ["..."], "family": "..."}],
        ...
      }
    }
  ]
}
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any, Optional


def _text(obj: Any) -> str:
    if isinstance(obj, dict):
        return obj.get("text", "")
    return str(obj)


def _name(name_list: list) -> str:
    if not name_list:
        return ""
    n = name_list[0]
    given = " ".join(n.get("given", []))
    family = n.get("family", "")
    return f"{given} {family}".strip()


def parse_synthea_bundle(bundle_path: Path) -> dict:
    """
    Parse a Synthea FHIR R4 JSON bundle and extract medical data.
    Returns a dict suitable for update_private().
    """
    data = json.loads(bundle_path.read_text(encoding="utf-8"))
    entries = data.get("entry", [])
    resources = [e["resource"] for e in entries if "resource" in e]

    patient_info: dict = {}
    conditions: list[str] = []
    allergies: list[str] = []
    medications: list[dict] = []
    practitioners: list[str] = []

    for r in resources:
        rt = r.get("resourceType", "")

        if rt == "Patient":
            patient_info = {
                "name": _name(r.get("name", [])),
                "birth_date": r.get("birthDate", ""),
                "gender": r.get("gender", ""),
            }

        elif rt == "Condition":
            # Only active/resolved conditions
            status = r.get("clinicalStatus", {})
            status_code = ""
            for coding in status.get("coding", []):
                status_code = coding.get("code", "")
            if status_code not in ("resolved",):
                label = _text(r.get("code", {}))
                if label:
                    conditions.append(label)

        elif rt == "AllergyIntolerance":
            label = _text(r.get("code", {}))
            if label:
                allergies.append(label)

        elif rt == "MedicationRequest":
            med_name = _text(r.get("medicationCodeableConcept", {}))
            dosage_list = r.get("dosageInstruction", [{}])
            dosage = dosage_list[0].get("text", "") if dosage_list else ""
            if med_name:
                medications.append({"name": med_name, "dosage": dosage})

        elif rt == "Practitioner":
            pname = _name(r.get("name", []))
            if pname:
                practitioners.append(pname)

    doctor = practitioners[0] if practitioners else ""
    return {
        "synthea_patient": patient_info,
        "medical_conditions": list(dict.fromkeys(conditions))[:20],  # deduplicate
        "allergies": list(dict.fromkeys(allergies))[:20],
        "medications": medications[:20],
        "doctor_details": {"name": doctor, "source": "Synthea synthetic data"},
    }


def import_to_user(bundle_path: Path, user_id: str) -> dict:
    """Parse bundle and write to user's private store."""
    from backend.auth.store import update_private
    extracted = parse_synthea_bundle(bundle_path)
    patient = extracted.pop("synthea_patient", {})
    update_private(user_id, extracted)
    return {"imported": True, "patient_meta": patient, "fields": list(extracted.keys())}


def find_first_bundle(synthea_dir: Path) -> Optional[Path]:
    """Find the first patient JSON bundle in a Synthea output directory."""
    # Synthea places bundles in output/fhir/ or directly as *.json
    candidates = list(synthea_dir.glob("**/*.json"))
    for f in candidates:
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
            if data.get("resourceType") == "Bundle":
                return f
        except Exception:
            continue
    return None


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python -m backend.synthea_import <synthea_dir_or_bundle_file> <user_id>")
        print("\nExpected Synthea FHIR R4 JSON bundles.")
        print("Download from: https://synthetichealth.github.io/downloads.html")
        sys.exit(1)

    input_path = Path(sys.argv[1])
    user_id = sys.argv[2]

    if input_path.is_dir():
        bundle = find_first_bundle(input_path)
        if bundle is None:
            print(f"No FHIR JSON Bundle found in {input_path}")
            sys.exit(1)
        print(f"Using bundle: {bundle}")
    else:
        bundle = input_path

    result = import_to_user(bundle, user_id)
    print(json.dumps(result, indent=2))
