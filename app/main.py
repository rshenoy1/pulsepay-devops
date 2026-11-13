import os
import uuid
from datetime import datetime, timezone
from fastapi import FastAPI, Depends, HTTPException, Header
from pydantic import BaseModel, Field
from sqlalchemy import create_engine, Column, String, Integer, DateTime, text
from sqlalchemy.orm import declarative_base, sessionmaker, Session

# Twelve-Factor App: Read configuration from environment variables
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://pulsepay:pulsepay_secret@localhost:5432/pulsepay_db"
)

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

class PaymentRecord(Base):
    __tablename__ = "payments"

    id = Column(String, primary_key=True, index=True)
    idempotency_key = Column(String, unique=True, index=True, nullable=False)
    customer_id = Column(String, nullable=False)
    amount_cents = Column(Integer, nullable=False)
    currency = Column(String(3), nullable=False)
    status = Column(String, default="COMPLETED")
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

app = FastAPI(title="PulsePay API", version="1.0.0")

@app.on_event("startup")
def startup_event():
    Base.metadata.create_all(bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

class PaymentCreate(BaseModel):
    customer_id: str = Field(..., min_length=1)
    amount_cents: int = Field(..., gt=0)
    currency: str = Field(..., min_length=3, max_length=3)

class PaymentResponse(BaseModel):
    id: str
    customer_id: str
    amount_cents: int
    currency: str
    status: str

# Deep Health Check: Verifies both the API and PostgreSQL connection
@app.get("/health")
def health_check(db: Session = Depends(get_db)):
    try:
        db.execute(text("SELECT 1"))
        return {"status": "healthy", "database": "connected"}
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"Database unreachable: {exc}")

# Idempotent Payment Endpoint: Prevents duplicate charges on network retries
@app.post("/payments", response_model=PaymentResponse, status_code=201)
def create_payment(
    payload: PaymentCreate,
    idempotency_key: str = Header(..., alias="Idempotency-Key"),
    db: Session = Depends(get_db)
):
    existing = db.query(PaymentRecord).filter(
        PaymentRecord.idempotency_key == idempotency_key
    ).first()
    if existing:
        return PaymentResponse(
            id=existing.id,
            customer_id=existing.customer_id,
            amount_cents=existing.amount_cents,
            currency=existing.currency,
            status=existing.status
        )

    payment = PaymentRecord(
        id=f"pay_{uuid.uuid4().hex[:12]}",
        idempotency_key=idempotency_key,
        customer_id=payload.customer_id,
        amount_cents=payload.amount_cents,
        currency=payload.currency.upper(),
        status="COMPLETED"
    )
    db.add(payment)
    db.commit()
    db.refresh(payment)

    return PaymentResponse(
        id=payment.id,
        customer_id=payment.customer_id,
        amount_cents=payment.amount_cents,
        currency=payment.currency,
        status=payment.status
    )

@app.get("/payments/{payment_id}", response_model=PaymentResponse)
def get_payment(payment_id: str, db: Session = Depends(get_db)):
    payment = db.query(PaymentRecord).filter(PaymentRecord.id == payment_id).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Payment not found")
    return PaymentResponse(
        id=payment.id,
        customer_id=payment.customer_id,
        amount_cents=payment.amount_cents,
        currency=payment.currency,
        status=payment.status
    )
