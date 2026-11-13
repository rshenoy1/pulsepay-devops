import os
os.environ["DATABASE_URL"] = "sqlite:///./test_pulsepay.db"

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.main import app, Base, get_db

SQLALCHEMY_TEST_URL = "sqlite:///./test_pulsepay.db"
engine = create_engine(SQLALCHEMY_TEST_URL, connect_args={"check_same_thread": False})
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base.metadata.create_all(bind=engine)

def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db] = override_get_db
client = TestClient(app)

def test_health_check():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"

def test_create_payment_and_idempotency():
    headers = {"Idempotency-Key": "req-unique-001"}
    payload = {"customer_id": "cust_99", "amount_cents": 5000, "currency": "USD"}

    # First request creates the payment
    res1 = client.post("/payments", json=payload, headers=headers)
    assert res1.status_code == 201
    data1 = res1.json()
    assert data1["amount_cents"] == 5000

    # Second identical request with same Idempotency-Key returns the exact same ID (no double charge)
    res2 = client.post("/payments", json=payload, headers=headers)
    assert res2.status_code == 201
    assert res2.json()["id"] == data1["id"]
