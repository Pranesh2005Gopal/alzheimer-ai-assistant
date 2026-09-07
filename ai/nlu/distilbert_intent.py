"""DistilBERT intent classifier. The LLM is never used to pick an intent."""

from __future__ import annotations

import json
from pathlib import Path

from models.intents import INTENT_LABELS, Intent
from utils.config import Settings

LABEL2ID = {label: i for i, label in enumerate(INTENT_LABELS)}
ID2LABEL = {i: label for label, i in LABEL2ID.items()}


class DistilBertIntentClassifier:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._tokenizer = None
        self._model = None

    def load(self) -> None:
        if self._model is not None:
            return
        checkpoint = self._settings.distilbert_dir
        if not (checkpoint / "config.json").exists():
            if self._settings.train_intent_if_missing:
                self._train_from_examples()
            else:
                raise FileNotFoundError(
                    f"No DistilBERT checkpoint at {checkpoint}. "
                    "Run: python scripts/train_intent_classifier.py"
                )
        from transformers import AutoTokenizer, DistilBertForSequenceClassification

        self._tokenizer = AutoTokenizer.from_pretrained(checkpoint)
        self._model = DistilBertForSequenceClassification.from_pretrained(checkpoint)
        self._model.eval()

    def predict(self, text: str) -> tuple[Intent, float]:
        self.load()
        import torch

        assert self._tokenizer is not None and self._model is not None
        encoded = self._tokenizer(
            text,
            return_tensors="pt",
            truncation=True,
            max_length=128,
        )
        with torch.no_grad():
            logits = self._model(**encoded).logits
            probs = torch.softmax(logits, dim=-1)[0]
            idx = int(torch.argmax(probs).item())
            confidence = float(probs[idx].item())
        label = ID2LABEL[idx]
        if confidence < 0.35:
            return Intent.UNKNOWN, confidence
        return Intent(label), confidence

    def _train_from_examples(self) -> None:
        train_intent_model(self._settings)


def train_intent_model(settings: Settings) -> Path:
    """Fine-tune DistilBERT on data/intent_examples.json and save the checkpoint."""
    import numpy as np
    import torch
    from torch.utils.data import DataLoader, Dataset
    from transformers import AutoTokenizer, DistilBertForSequenceClassification, get_linear_schedule_with_warmup

    examples_path = settings.intent_examples_path
    payload = json.loads(examples_path.read_text(encoding="utf-8"))
    texts: list[str] = []
    labels: list[int] = []
    for label, utterances in payload.items():
        if label not in LABEL2ID:
            raise ValueError(f"Unknown intent in training data: {label}")
        for utterance in utterances:
            texts.append(utterance)
            labels.append(LABEL2ID[label])

    tokenizer = AutoTokenizer.from_pretrained(settings.distilbert_base)
    model = DistilBertForSequenceClassification.from_pretrained(
        settings.distilbert_base,
        num_labels=len(INTENT_LABELS),
        id2label=ID2LABEL,
        label2id=LABEL2ID,
    )

    class IntentDataset(Dataset):
        def __len__(self) -> int:
            return len(texts)

        def __getitem__(self, index: int) -> dict:
            encoded = tokenizer(
                texts[index],
                truncation=True,
                padding="max_length",
                max_length=64,
                return_tensors="pt",
            )
            item = {k: v.squeeze(0) for k, v in encoded.items()}
            item["labels"] = torch.tensor(labels[index], dtype=torch.long)
            return item

    loader = DataLoader(IntentDataset(), batch_size=8, shuffle=True)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model.to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=5e-5)
    steps = max(1, len(loader) * 4)
    scheduler = get_linear_schedule_with_warmup(optimizer, 0, steps)

    model.train()
    for _epoch in range(4):
        for batch in loader:
            batch = {k: v.to(device) for k, v in batch.items()}
            loss = model(**batch).loss
            loss.backward()
            optimizer.step()
            scheduler.step()
            optimizer.zero_grad()

    out_dir = settings.distilbert_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    model.save_pretrained(out_dir)
    tokenizer.save_pretrained(out_dir)
    meta = {"labels": INTENT_LABELS, "base": settings.distilbert_base}
    (out_dir / "intent_meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    np.save(out_dir / "label_order.npy", np.array(INTENT_LABELS))
    return out_dir
