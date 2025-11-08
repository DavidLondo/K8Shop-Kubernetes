import os, sys
from pathlib import Path

# Ensure src is on the path
ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src"
sys.path.insert(0, str(SRC))

from dotenv import load_dotenv, find_dotenv
load_dotenv(find_dotenv())

from fastapi.testclient import TestClient
import main

client = TestClient(main.app)

# Health check
r = client.get("/healthz")
assert r.status_code == 200, r.text
print("/healthz ->", r.json())

# Create order (publisher disabled -> should still succeed)
payload = {
    "userId": "user-123",
    "items": [
        {"sku": "SKU-1", "qty": 2, "price": 10.5},
        {"sku": "SKU-2", "qty": 1, "price": 3.0},
    ]
}

r = client.post("/orders", json=payload)
assert r.status_code == 200, r.text
print("/orders ->", r.json())
