"use strict";

// El navegador nunca llama al backend directamente: todas las peticiones van a
// /api/... en el mismo nginx que sirve esta página, y nginx las reenvía.

const $ = (id) => document.getElementById(id);
let rooms = [];

async function api(path, options = {}) {
  const response = await fetch(`/api${path}`, {
    cache: "no-store",
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  if (!response.ok) {
    let detail = `${response.status} ${response.statusText}`;
    try {
      const body = await response.json();
      if (typeof body.detail === "string") detail = body.detail;
      else if (Array.isArray(body.detail)) detail = body.detail.map((e) => e.msg).join("; ");
    } catch {
      // Respuesta sin JSON, por ejemplo un 502 de nginx si el backend no responde
    }
    throw new Error(detail);
  }
  return response.status === 204 ? null : response.json();
}

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (key === "class") node.className = value;
    else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value);
  }
  node.append(...children);
  return node;
}

function showMessage(text, type = "ok") {
  const box = $("message");
  box.textContent = text;
  box.className = `message ${type}`;
  box.hidden = false;
  clearTimeout(showMessage.timer);
  showMessage.timer = setTimeout(() => { box.hidden = true; }, 6000);
}

// --- Estado y configuración ---------------------------------------------------

async function loadConfig() {
  try {
    const config = await (await fetch("/config.json", { cache: "no-store" })).json();
    $("env-badge").textContent = `entorno: ${config.appEnv}`;
    $("backend-url").textContent = config.backendUrl;
  } catch {
    $("env-badge").textContent = "entorno: desconocido";
  }
}

async function checkHealth() {
  const pill = $("backend-status");
  const label = pill.querySelector(".label");
  try {
    const health = await (await fetch("/api/health", { cache: "no-store" })).json();
    const ok = health.status === "ok";
    pill.className = `pill ${ok ? "ok" : "warn"}`;
    label.textContent = ok
      ? `Backend OK · BD OK · ${health.hostname}`
      : `Backend sin base de datos · ${health.hostname}`;
  } catch {
    pill.className = "pill error";
    label.textContent = "Backend no disponible";
  }
}

// --- Aulas -------------------------------------------------------------------

function roomName(id) {
  const room = rooms.find((r) => r.id === id);
  return room ? room.nombre : `Aula ${id}`;
}

async function loadRooms() {
  try {
    rooms = await api("/rooms");
  } catch (error) {
    rooms = [];
    showMessage(`No se pudieron cargar las aulas: ${error.message}`, "error");
  }
  $("rooms-count").textContent = `${rooms.length} aulas`;
  $("rooms-body").replaceChildren(
    ...rooms.map((room) =>
      el("tr", {},
        el("td", {}, String(room.id)),
        el("td", {}, room.nombre),
        el("td", {}, room.edificio),
        el("td", { class: "num" }, String(room.capacidad)),
        el("td", {}, ...room.equipamiento.map((item) => el("span", { class: "chip" }, item))),
        el("td", { class: "actions" },
          el("button", { type: "button", class: "danger", onclick: () => deleteRoom(room) }, "Eliminar")),
      )),
  );

  // Selects de reservas
  const filter = $("bookings-filter");
  const selected = filter.value;
  filter.replaceChildren(el("option", { value: "" }, "Todas"),
    ...rooms.map((room) => el("option", { value: room.id }, room.nombre)));
  filter.value = rooms.some((r) => String(r.id) === selected) ? selected : "";
  $("booking-room").replaceChildren(...rooms.map((room) => el("option", { value: room.id }, room.nombre)));
}

async function deleteRoom(room) {
  if (!confirm(`¿Eliminar "${room.nombre}" y todas sus reservas?`)) return;
  try {
    await api(`/rooms/${room.id}`, { method: "DELETE" });
    showMessage(`Aula "${room.nombre}" eliminada`);
    await refresh();
  } catch (error) {
    showMessage(error.message, "error");
  }
}

$("room-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const data = new FormData(event.target);
  const room = {
    nombre: data.get("nombre").trim(),
    edificio: data.get("edificio").trim(),
    capacidad: Number(data.get("capacidad")),
    equipamiento: data.get("equipamiento").split(",").map((s) => s.trim()).filter(Boolean),
  };
  try {
    const created = await api("/rooms", { method: "POST", body: JSON.stringify(room) });
    showMessage(`Aula "${created.nombre}" creada con id ${created.id}`);
    event.target.reset();
    await refresh();
  } catch (error) {
    showMessage(error.message, "error");
  }
});

// --- Reservas ----------------------------------------------------------------

async function loadBookings() {
  const aulaId = $("bookings-filter").value;
  let bookings = [];
  try {
    bookings = await api(aulaId ? `/bookings?aula_id=${aulaId}` : "/bookings");
  } catch (error) {
    showMessage(`No se pudieron cargar las reservas: ${error.message}`, "error");
  }
  const rows = bookings.map((booking) =>
    el("tr", {},
      el("td", {}, String(booking.id)),
      el("td", {}, roomName(booking.aula_id)),
      el("td", {}, booking.usuario),
      el("td", {}, booking.fecha),
      el("td", {}, `${booking.hora_inicio} – ${booking.hora_fin}`),
      el("td", { class: "actions" },
        el("button", { type: "button", class: "danger", onclick: () => deleteBooking(booking) }, "Eliminar")),
    ));
  if (rows.length === 0) {
    rows.push(el("tr", {}, el("td", { colspan: "6", class: "empty" }, "No hay reservas")));
  }
  $("bookings-body").replaceChildren(...rows);
}

async function deleteBooking(booking) {
  if (!confirm(`¿Eliminar la reserva ${booking.id} de ${booking.usuario}?`)) return;
  try {
    await api(`/bookings/${booking.id}`, { method: "DELETE" });
    showMessage(`Reserva ${booking.id} eliminada`);
    await loadBookings();
  } catch (error) {
    showMessage(error.message, "error");
  }
}

$("bookings-filter").addEventListener("change", loadBookings);

$("booking-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const data = new FormData(event.target);
  const booking = {
    aula_id: Number(data.get("aula_id")),
    usuario: data.get("usuario").trim(),
    fecha: data.get("fecha"),
    hora_inicio: data.get("hora_inicio"),
    hora_fin: data.get("hora_fin"),
  };
  try {
    const created = await api("/bookings", { method: "POST", body: JSON.stringify(booking) });
    showMessage(`Reserva ${created.id} creada para ${roomName(created.aula_id)}`);
    event.target.reset();
    await loadBookings();
  } catch (error) {
    showMessage(error.message, "error");
  }
});

// --- Reparto de carga entre réplicas -----------------------------------------

$("lb-test").addEventListener("click", async (event) => {
  const button = event.target;
  button.disabled = true;
  const counts = {};
  for (let i = 0; i < 20; i++) {
    let host;
    try {
      host = (await (await fetch("/api/health", { cache: "no-store" })).json()).hostname;
    } catch {
      host = "(sin respuesta)";
    }
    counts[host] = (counts[host] || 0) + 1;
  }
  $("lb-results").replaceChildren(
    ...Object.entries(counts)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([host, n]) =>
        el("li", {},
          el("span", { class: "host" }, host),
          el("span", { class: "bar", style: `--w: ${n * 5}%` }),
          el("span", { class: "n" }, String(n)))),
  );
  button.disabled = false;
});

// --- Arranque ----------------------------------------------------------------

async function refresh() {
  await loadRooms();
  await loadBookings();
}

loadConfig();
checkHealth();
refresh();
setInterval(checkHealth, 5000);
