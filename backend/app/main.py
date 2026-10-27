"""API REST de SmartCampus: gestión de aulas y reservas."""

import os
import socket
from contextlib import asynccontextmanager
from datetime import date, time

import psycopg
from fastapi import FastAPI, HTTPException, Request, Response, status
from fastapi.responses import JSONResponse
from psycopg import errors
from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool, PoolTimeout
from pydantic import BaseModel, Field, field_serializer, model_validator

# --- Configuración ---------------------------------------------------------
# Todo llega por variables de entorno: en Docker Compose desde el
# docker-compose.yml y en Kubernetes desde el ConfigMap y el Secret.
APP_ENV = os.getenv("APP_ENV", "development")
HOSTNAME = socket.gethostname()  # nombre del contenedor o del Pod que responde

CONNINFO = make_conninfo(
    host=os.getenv("DB_HOST", "localhost"),
    port=os.getenv("DB_PORT", "5432"),
    dbname=os.getenv("DB_NAME", "smartcampus"),
    user=os.getenv("DB_USER", "smartcampus"),
    password=os.getenv("DB_PASSWORD", ""),
    connect_timeout=3,
    application_name=f"backend@{HOSTNAME}",
)

# El pool reutiliza conexiones y crea otras nuevas si la base de datos se
# reinicia; "check" descarta las conexiones rotas antes de usarlas.
pool = ConnectionPool(
    CONNINFO,
    min_size=1,
    max_size=int(os.getenv("DB_POOL_SIZE", "5")),
    timeout=5,
    open=False,
    kwargs={"row_factory": dict_row, "autocommit": True},
    check=ConnectionPool.check_connection,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # wait=False: la API arranca aunque la base de datos todavía no esté lista.
    pool.open(wait=False)
    yield
    pool.close()


app = FastAPI(
    title="SmartCampus API",
    description="Gestión de aulas y reservas de espacios universitarios.",
    version="1.0.0",
    lifespan=lifespan,
)


@app.exception_handler(PoolTimeout)
@app.exception_handler(psycopg.OperationalError)
async def database_unavailable(request: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        content={"detail": "Base de datos no disponible"},
    )


# --- Modelos ---------------------------------------------------------------
class RoomIn(BaseModel):
    nombre: str = Field(min_length=1, max_length=100)
    edificio: str = Field(min_length=1, max_length=100)
    capacidad: int = Field(gt=0)
    equipamiento: list[str] = []


class Room(BaseModel):
    id: int
    nombre: str
    edificio: str
    capacidad: int
    equipamiento: list[str]


class BookingIn(BaseModel):
    aula_id: int
    usuario: str = Field(min_length=1, max_length=100)
    fecha: date
    hora_inicio: time
    hora_fin: time

    @model_validator(mode="after")
    def check_hours(self) -> "BookingIn":
        if self.hora_fin <= self.hora_inicio:
            raise ValueError("hora_fin debe ser posterior a hora_inicio")
        return self


class Booking(BaseModel):
    id: int
    aula_id: int
    usuario: str
    fecha: date
    hora_inicio: time
    hora_fin: time

    @field_serializer("hora_inicio", "hora_fin")
    def format_hour(self, value: time) -> str:
        return value.strftime("%H:%M")


ROOM_COLUMNS = "id, nombre, edificio, capacidad, equipamiento"
BOOKING_COLUMNS = "id, aula_id, usuario, fecha, hora_inicio, hora_fin"


# --- Salud -----------------------------------------------------------------
@app.get("/health", tags=["salud"])
def health(response: Response) -> dict:
    """Estado del servicio y de su conexión con la base de datos."""
    info = {
        "status": "ok",
        "service": "smartcampus-backend",
        "environment": APP_ENV,
        "hostname": HOSTNAME,
        "database": "ok",
    }
    try:
        with pool.connection(timeout=2) as conn:
            conn.execute("SELECT 1")
    except (PoolTimeout, psycopg.Error):
        info.update(status="degraded", database="unavailable")
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    return info


@app.get("/health/live", tags=["salud"])
def liveness() -> dict:
    """Solo comprueba que el proceso responde (no depende de la base de datos)."""
    return {"status": "ok"}


# --- Aulas -----------------------------------------------------------------
@app.get("/rooms", response_model=list[Room], tags=["aulas"])
def list_rooms():
    with pool.connection() as conn:
        return conn.execute(f"SELECT {ROOM_COLUMNS} FROM aulas ORDER BY id").fetchall()


@app.get("/rooms/{room_id}", response_model=Room, tags=["aulas"])
def get_room(room_id: int):
    with pool.connection() as conn:
        room = conn.execute(
            f"SELECT {ROOM_COLUMNS} FROM aulas WHERE id = %s", (room_id,)
        ).fetchone()
    if room is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, f"Aula {room_id} no encontrada")
    return room


@app.post("/rooms", response_model=Room, status_code=status.HTTP_201_CREATED, tags=["aulas"])
def create_room(room: RoomIn):
    with pool.connection() as conn:
        return conn.execute(
            f"""INSERT INTO aulas (nombre, edificio, capacidad, equipamiento)
                VALUES (%s, %s, %s, %s) RETURNING {ROOM_COLUMNS}""",
            (room.nombre, room.edificio, room.capacidad, room.equipamiento),
        ).fetchone()


@app.delete("/rooms/{room_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["aulas"])
def delete_room(room_id: int):
    """Elimina el aula y, en cascada, sus reservas."""
    with pool.connection() as conn:
        deleted = conn.execute("DELETE FROM aulas WHERE id = %s", (room_id,)).rowcount
    if not deleted:
        raise HTTPException(status.HTTP_404_NOT_FOUND, f"Aula {room_id} no encontrada")


# --- Reservas --------------------------------------------------------------
@app.get("/bookings", response_model=list[Booking], tags=["reservas"])
def list_bookings(aula_id: int | None = None):
    query = f"SELECT {BOOKING_COLUMNS} FROM reservas"
    params: tuple = ()
    if aula_id is not None:
        query += " WHERE aula_id = %s"
        params = (aula_id,)
    with pool.connection() as conn:
        return conn.execute(query + " ORDER BY fecha, hora_inicio, id", params).fetchall()


@app.get("/bookings/{booking_id}", response_model=Booking, tags=["reservas"])
def get_booking(booking_id: int):
    with pool.connection() as conn:
        booking = conn.execute(
            f"SELECT {BOOKING_COLUMNS} FROM reservas WHERE id = %s", (booking_id,)
        ).fetchone()
    if booking is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, f"Reserva {booking_id} no encontrada")
    return booking


@app.post("/bookings", response_model=Booking, status_code=status.HTTP_201_CREATED, tags=["reservas"])
def create_booking(booking: BookingIn):
    try:
        with pool.connection() as conn:
            return conn.execute(
                f"""INSERT INTO reservas (aula_id, usuario, fecha, hora_inicio, hora_fin)
                    VALUES (%s, %s, %s, %s, %s) RETURNING {BOOKING_COLUMNS}""",
                (booking.aula_id, booking.usuario, booking.fecha, booking.hora_inicio, booking.hora_fin),
            ).fetchone()
    except errors.ForeignKeyViolation:
        raise HTTPException(status.HTTP_404_NOT_FOUND, f"Aula {booking.aula_id} no encontrada")
    except errors.ExclusionViolation:
        # Lo garantiza la base de datos, así que vale aunque haya varias réplicas.
        raise HTTPException(status.HTTP_409_CONFLICT, "El aula ya está reservada en esa franja horaria")


@app.delete("/bookings/{booking_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["reservas"])
def delete_booking(booking_id: int):
    with pool.connection() as conn:
        deleted = conn.execute("DELETE FROM reservas WHERE id = %s", (booking_id,)).rowcount
    if not deleted:
        raise HTTPException(status.HTTP_404_NOT_FOUND, f"Reserva {booking_id} no encontrada")
