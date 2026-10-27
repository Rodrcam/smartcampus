# SmartCampus: despliegue con Docker Compose y Kubernetes

Prototipo de la plataforma **SmartCampus** para gestionar aulas y reservas de
espacios universitarios. La misma aplicación se despliega de dos formas: con
**Docker Compose** y con **Kubernetes** (Minikube), para comparar ambos
enfoques.

## Arquitectura

```
                    Navegador
                        │  http://localhost:8080 (Compose)
                        │  minikube service frontend-service (Kubernetes)
                        ▼
              ┌───────────────────┐
              │     FRONTEND      │  nginx: sirve la web y reenvía /api/* al backend
              │  HTML + JS, nginx │
              └─────────┬─────────┘
                        │ HTTP  (backend:8000 / backend-service:8000)
                        ▼
              ┌───────────────────┐
              │      BACKEND      │  API REST con Python + FastAPI
              │  FastAPI, :8000   │  (2 réplicas en Kubernetes)
              └─────────┬─────────┘
                        │ SQL   (database:5432 / database-service:5432)
                        ▼
              ┌───────────────────┐
              │     DATABASE      │  PostgreSQL 17 con volumen persistente
              │  PostgreSQL :5432 │
              └───────────────────┘
```

El navegador nunca habla directamente con el backend: pide `/api/...` al
nginx del frontend, que reenvía la petición al backend por el nombre del
servicio. Así, el backend y la base de datos no necesitan estar expuestos
fuera de Docker o del clúster.

## Estructura del repositorio

```
smartcampus/
├── backend/                 API REST (FastAPI)
│   ├── Dockerfile
│   ├── requirements.txt
│   └── app/main.py
├── frontend/                Interfaz web servida por nginx
│   ├── Dockerfile
│   ├── nginx/default.conf.template
│   └── public/              index.html, app.js, styles.css
├── database/
│   └── init.sql             Tablas y datos de ejemplo
├── docker-compose.yml       Despliegue con Docker Compose
├── docker-compose.scale.yml Opcional: permite escalar el backend con Compose
├── .env.example             Variables para Compose (copiar a .env)
├── k8s/                     Manifiestos de Kubernetes
│   ├── 00-namespace.yaml
│   ├── 01-configmap.yaml
│   ├── 02-secret.yaml
│   ├── 03-database-init-configmap.yaml
│   ├── 10-database-statefulset.yaml
│   ├── 11-database-service.yaml
│   ├── 20-backend-deployment.yaml
│   ├── 21-backend-service.yaml
│   ├── 30-frontend-deployment.yaml
│   ├── 31-frontend-service.yaml
│   └── extras/hpa-backend.yaml   Ampliación: autoescalado (opcional)
├── scripts/                 Instalación de los programas necesarios
│   ├── instalar-requisitos.ps1   Windows
│   └── instalar-requisitos.sh    macOS y Linux
└── docs/
    └── GUIA-PRUEBAS.md      Paso a paso de las pruebas y capturas
```

Los ficheros de `k8s/` llevan un número delante porque `kubectl apply -f .`
los aplica en orden alfabético y el namespace debe crearse antes que el resto.

## API

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/health` | Estado del backend y de la conexión con la base de datos. Incluye el nombre del contenedor o Pod que responde |
| GET | `/health/live` | Solo comprueba que el proceso responde (lo usa la *liveness probe*) |
| GET | `/rooms` | Lista de aulas |
| GET | `/rooms/{id}` | Detalle de un aula (404 si no existe) |
| POST | `/rooms` | Crea un aula |
| DELETE | `/rooms/{id}` | Elimina un aula y sus reservas |
| GET | `/bookings` | Lista de reservas (filtro opcional `?aula_id=1`) |
| GET | `/bookings/{id}` | Detalle de una reserva |
| POST | `/bookings` | Crea una reserva (409 si se solapa con otra de la misma aula) |
| DELETE | `/bookings/{id}` | Elimina una reserva |

Ejemplo de aula:

```json
{
  "id": 1,
  "nombre": "Laboratorio de Robótica",
  "edificio": "Edificio A",
  "capacidad": 30,
  "equipamiento": ["ordenadores", "robots", "impresora 3D"]
}
```

Ejemplo de reserva:

```json
{
  "id": 1,
  "aula_id": 1,
  "usuario": "ana.garcia",
  "fecha": "2026-11-03",
  "hora_inicio": "09:00",
  "hora_fin": "11:00"
}
```

La documentación interactiva (Swagger) está en <http://localhost:8000/docs>
cuando se despliega con Docker Compose.

## Requisitos

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (incluye Docker Compose).
- [Minikube](https://minikube.sigs.k8s.io/docs/start/) y [kubectl](https://kubernetes.io/docs/tasks/tools/)
  (`minikube kubectl --` también sirve si no se instala kubectl aparte).
- [Git](https://git-scm.com/downloads), para descargar el repositorio.

No hace falta instalar Python ni las librerías del backend:
`backend/requirements.txt` se instala dentro de la imagen de Docker al hacer
`docker compose build`.

> En Windows (PowerShell), usa `curl.exe` en lugar de `curl` en los comandos
> de este documento: en PowerShell, `curl` es un alias de otro comando.

## Descargar el proyecto

```bash
git clone https://github.com/Rodrcam/smartcampus.git
cd smartcampus
```

Todos los comandos de este documento se ejecutan desde esa carpeta. Sin Git,
también se puede descargar desde GitHub con **Code → Download ZIP**.

## Instalar los requisitos automáticamente

La carpeta `scripts/` tiene un script que instala los programas que falten y
se salta los que ya estén instalados. Se ejecuta desde la carpeta del proyecto
(si todavía no tienes Git, descarga antes el ZIP):

| Sistema | Comando |
|---|---|
| Windows 10 u 11 (PowerShell) | `powershell -ExecutionPolicy Bypass -File scripts\instalar-requisitos.ps1` |
| macOS (necesita [Homebrew](https://brew.sh)) | `bash scripts/instalar-requisitos.sh` |
| Ubuntu, Debian y derivadas | `bash scripts/instalar-requisitos.sh` |

- **Windows**: instala los programas con `winget` y también WSL 2, que Docker
  Desktop necesita. Windows pide permiso de administrador y, si se instala
  WSL, hay que reiniciar antes de abrir Docker Desktop. `-ExecutionPolicy
  Bypass` deja ejecutar el script solo esa vez, sin cambiar la configuración
  de seguridad de Windows.
- **macOS**: instala con Homebrew Git, Minikube (que trae kubectl) y Docker
  Desktop.
- **Linux**: instala Docker Engine desde el repositorio oficial de Docker y
  añade tu usuario al grupo `docker`; cierra la sesión y vuelve a entrar para
  usar `docker` sin `sudo`.

Los dos scripts dejan Minikube configurado para usar Docker
(`minikube config set driver docker`) y al final muestran la versión de cada
herramienta. Antes de seguir, en Windows y macOS abre Docker Desktop y espera
a que indique *Engine running*.

## 1. Despliegue con Docker Compose

```bash
docker compose up -d --build
docker compose ps
```

| Servicio | URL |
|---|---|
| Frontend | <http://localhost:8080> |
| Backend (directo) | <http://localhost:8000/health> y <http://localhost:8000/docs> |
| Backend (a través del frontend) | <http://localhost:8080/api/health> |

Qué configura el `docker-compose.yml`:

- **Servicios**: `frontend`, `backend` y `database`. Cada uno se resuelve por su
  nombre gracias al DNS interno de Docker (`DB_HOST: database`,
  `BACKEND_URL: http://backend:8000`).
- **Redes**: `frontend-net` (frontend y backend) y `backend-net` (backend y base
  de datos). El frontend no puede llegar a la base de datos.
- **Puertos**: solo se publican el 8080 (frontend) y el 8000 (backend, para
  pruebas). PostgreSQL no se publica.
- **Variables de entorno**: con valores por defecto para que funcione sin más.
  Para cambiarlas: `cp .env.example .env` y editar `.env`.
- **Dependencias**: `depends_on` con `condition: service_healthy`, para que el
  backend espere a que PostgreSQL acepte conexiones y el frontend al backend.
- **Volúmenes**: `db-data` guarda los datos de PostgreSQL y se monta
  `database/init.sql` para crear las tablas la primera vez.
- **Reinicio**: `restart: unless-stopped` reinicia un contenedor si su proceso
  termina, salvo que se haya parado a mano.

Escalar el backend (opcional; el fichero extra quita el puerto 8000 publicado,
que no pueden compartir varias réplicas):

```bash
docker compose -f docker-compose.yml -f docker-compose.scale.yml up -d --scale backend=3
```

Parar:

```bash
docker compose down        # para y borra los contenedores; los datos se conservan
docker compose down -v     # además borra el volumen: la próxima vez se vuelve a ejecutar init.sql
```

## 2. Despliegue en Kubernetes (Minikube)

```bash
# 1. Arrancar el clúster
minikube start

# 2. Construir las imágenes y cargarlas en Minikube
#    (no están en ningún registro, así que Minikube no las puede descargar)
docker compose build
minikube image load smartcampus-backend:1.0
minikube image load smartcampus-frontend:1.0

# 3. Desplegar todos los manifiestos
cd k8s
kubectl apply -f .

# 4. Trabajar en el namespace de la aplicación (así no hace falta poner -n smartcampus)
kubectl config set-context --current --namespace=smartcampus

# 5. Esperar a que todo esté Running y ver los recursos
kubectl get pods -w          # Ctrl+C para salir
kubectl get pods
kubectl get services
kubectl get deployments
kubectl get statefulsets
kubectl get pvc

# 6. Abrir el frontend (deja la terminal abierta si Minikube crea un túnel)
minikube service frontend-service -n smartcampus
```

Recursos que se crean:

| Recurso | Nombre | Para qué |
|---|---|---|
| Namespace | `smartcampus` | Agrupa todos los recursos de la aplicación |
| ConfigMap | `smartcampus-config` | Configuración no sensible: `APP_ENV`, `BACKEND_URL`, `DB_HOST`, `DB_PORT`, `DB_NAME` |
| Secret | `smartcampus-db-secret` | Credenciales `DB_USER` y `DB_PASSWORD` |
| ConfigMap | `database-init` | El script `init.sql`, montado en el Pod de PostgreSQL |
| StatefulSet | `database` | PostgreSQL con un volumen persistente propio (`data-database-0`) |
| Service | `database-service` | Acceso estable a PostgreSQL para el backend |
| Service | `database-headless` | Service *headless* que necesita el StatefulSet |
| Deployment | `backend` | API REST con 2 réplicas, *readiness* y *liveness probes* |
| Service | `backend-service` | Reparte las peticiones entre las réplicas del backend |
| Deployment | `frontend` | nginx con la interfaz web (1 réplica) |
| Service | `frontend-service` | `NodePort` 30080 para acceder desde fuera del clúster |

Comandos de los experimentos:

```bash
kubectl scale deployment backend --replicas=4    # escalado
kubectl get pods
kubectl scale deployment backend --replicas=2

kubectl delete pod <nombre-de-un-pod-del-backend>   # self-healing
kubectl get pods

kubectl rollout restart deployment backend frontend   # aplicar cambios del ConfigMap
```

En la interfaz web, el botón **Enviar 20 peticiones** muestra qué réplica del
backend atiende cada petición, lo que permite ver el reparto de carga del
Service.

Limpiar:

```bash
kubectl delete namespace smartcampus   # borra todo, incluido el volumen de la base de datos
minikube stop
```

### Ampliación: autoescalado (HPA)

```bash
minikube addons enable metrics-server
kubectl apply -f k8s/extras/hpa-backend.yaml
kubectl get hpa -w
```

La guía de pruebas explica cómo generar carga para ver cómo sube el número de
réplicas.

## Configuración

| Variable | Usada por | Docker Compose | Kubernetes |
|---|---|---|---|
| `APP_ENV` | backend, frontend | `.env` (por defecto `development`) | ConfigMap (`kubernetes`) |
| `BACKEND_URL` | frontend | `http://backend:8000` | ConfigMap (`http://backend-service.smartcampus.svc.cluster.local:8000`) |
| `DB_HOST`, `DB_PORT`, `DB_NAME` | backend | `docker-compose.yml` / `.env` | ConfigMap |
| `DB_USER`, `DB_PASSWORD` | backend, PostgreSQL | `.env` (con valores por defecto) | Secret |

En Kubernetes, `BACKEND_URL` usa el nombre DNS completo del Service porque
nginx resuelve el nombre en cada petición con su propio *resolver*, que no
aplica los dominios de búsqueda de `/etc/resolv.conf`.

> **Sobre el Secret**: `k8s/02-secret.yaml` está en el repositorio porque es
> una práctica con una contraseña de laboratorio. Los valores van en base64,
> que no es cifrado. En un proyecto real el Secret no se guardaría en Git y se
> gestionaría con herramientas como Sealed Secrets, External Secrets o Vault.

## Pruebas

El paso a paso de las pruebas y experimentos, con los comandos y las capturas
que hay que hacer, está en [docs/GUIA-PRUEBAS.md](docs/GUIA-PRUEBAS.md).

## Problemas frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| `la ejecución de scripts está deshabilitada en este sistema` al lanzar el script de Windows | PowerShell no ejecuta scripts por defecto | Lanzarlo con el comando completo: `powershell -ExecutionPolicy Bypass -File scripts\instalar-requisitos.ps1` |
| Docker Desktop avisa de que falta WSL o de que está desactualizado | Docker Desktop necesita WSL 2.1.5 o posterior | En PowerShell como administrador, `wsl --update` (o `wsl --install --no-distribution` si no estaba instalado) y reiniciar |
| `namespaces "smartcampus" not found` al hacer `kubectl apply -f .` | Se aplicó un recurso antes que el namespace | Los ficheros están numerados para que el namespace vaya primero; si pasa, repite `kubectl apply -f .` |
| Pods en `ErrImagePull` o `ImagePullBackOff` | La imagen no está dentro de Minikube | `minikube image load smartcampus-backend:1.0` (y la del frontend) y después `kubectl rollout restart deployment backend frontend` |
| Cambios en `init.sql` que no aparecen | PostgreSQL solo ejecuta `init.sql` con el volumen vacío | Compose: `docker compose down -v`. Kubernetes: `kubectl delete namespace smartcampus` y volver a aplicar |
| `port is already allocated` | El puerto 8080 u 8000 ya está en uso | Cerrar lo que lo use o cambiar el puerto de la izquierda en `ports:` |
| La web muestra "Backend no disponible" | El backend está parado o no está listo | `docker compose ps` / `kubectl get pods` y revisar `docker compose logs backend` / `kubectl logs deploy/backend` |
| El PVC se queda en `Pending` | El clúster no tiene StorageClass por defecto | En Minikube: `minikube addons enable default-storageclass storage-provisioner` |
