#!/usr/bin/env python3
"""Fine-tune DistilBERT on data/intent_examples.json."""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from ai.nlu.distilbert_intent import train_intent_model
from utils.config import get_settings


def main() -> None:
    path = train_intent_model(get_settings())
    print(f"Saved DistilBERT intent classifier to {path}")


if __name__ == "__main__":
    main()
