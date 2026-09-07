"""FaceNet embeddings (Phase 4). Compare with registered people; never claim 100% accuracy."""

from __future__ import annotations

import numpy as np


class FaceNetEmbedder:
    def __init__(self) -> None:
        self._model = None

    def load(self) -> None:
        if self._model is not None:
            return
        from facenet_pytorch import InceptionResnetV1

        self._model = InceptionResnetV1(pretrained="vggface2").eval()

    def embed(self, face_rgb) -> list[float]:
        self.load()
        import torch
        from PIL import Image
        from torchvision import transforms

        assert self._model is not None
        image = Image.fromarray(face_rgb)
        tensor = transforms.Compose(
            [
                transforms.Resize((160, 160)),
                transforms.ToTensor(),
                transforms.Normalize([0.5, 0.5, 0.5], [0.5, 0.5, 0.5]),
            ]
        )(image).unsqueeze(0)
        with torch.no_grad():
            vector = self._model(tensor).squeeze().cpu().numpy()
        return vector.astype(float).tolist()

    @staticmethod
    def cosine_similarity(a: list[float], b: list[float]) -> float:
        va = np.asarray(a, dtype=float)
        vb = np.asarray(b, dtype=float)
        denom = np.linalg.norm(va) * np.linalg.norm(vb)
        if denom == 0:
            return 0.0
        return float(np.dot(va, vb) / denom)
