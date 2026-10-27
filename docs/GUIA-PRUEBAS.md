# Guía de pruebas y capturas

Esta guía recorre, en orden, todas las pruebas y experimentos que pide el
enunciado. Para cada uno indica qué comandos ejecutar, qué debería salir, qué
captura hacer y qué hay que explicar en la memoria.

Guarda las capturas en `docs/evidencias/` con el nombre que se indica
(📸). Así es fácil enlazarlas desde la memoria.

**Antes de empezar**

- Necesitas Docker Desktop, Minikube, kubectl y Git instalados.
- Descarga el repositorio y entra en su carpeta; todos los comandos se
  ejecutan desde ahí:

  ```bash
  git clone https://github.com/Rodrcam/smartcampus.git
  cd smartcampus
  ```

- Si te falta algún programa, instálalo con el script de `scripts/` (en
  Windows: `powershell -ExecutionPolicy Bypass -File scripts\instalar-requisitos.ps1`;
  en macOS o Linux: `bash scripts/instalar-requisitos.sh`). El README explica
  qué hace cada uno en "Instalar los requisitos automáticamente".
- Abre Docker Desktop y espera a que indique *Engine running* antes de empezar.

- En **Windows (PowerShell)** escribe `curl.exe` en vez de `curl`, y para
  filtrar la salida usa `Select-String` en vez de `grep`.
- Apunta **cualquier error** que te salga y cómo lo resolviste (mensaje
  exacto, causa y solución). Es la sección 22.7 de la memoria, "Problemas
  encontrados", y el enunciado dice que es importante.

---

## Parte 1. Docker Compose

### Experimento 1 / Prueba 1: levantar la aplicación

```bash
docker compose up -d --build
docker compose ps
```

Debe salir algo así: los tres servicios `Up`, y `backend` y `database` con
`(healthy)`:

```
NAME                     IMAGE                      SERVICE    STATUS                   PORTS
smartcampus-backend-1    smartcampus-backend:1.0    backend    Up 8 seconds (healthy)   0.0.0.0:8000->8000/tcp
smartcampus-database-1   postgres:17-alpine         database   Up 13 seconds (healthy)  5432/tcp
smartcampus-frontend-1   smartcampus-frontend:1.0   frontend   Up 2 seconds             0.0.0.0:8080->80/tcp
```

📸 `01-compose-ps.png`: la salida de `docker compose ps`.

Para la memoria: el orden de arranque lo marca `depends_on` con
`condition: service_healthy`. Primero la base de datos, cuando `pg_isready`
responde el backend, y cuando el backend está sano el frontend.

### Prueba 2: endpoint /health del backend

```bash
curl http://localhost:8000/health
```

```json
{"status":"ok","service":"smartcampus-backend","environment":"development","hostname":"6290a10eba37","database":"ok"}
```

También se puede abrir en el navegador. `hostname` es el ID del contenedor que
responde.

📸 `02-compose-health.png`

### Prueba 3: comunicación backend ↔ base de datos

Tres evidencias, de menos a más directa:

1. `/health` devuelve `"database":"ok"`: el backend ejecuta `SELECT 1` contra
   PostgreSQL en cada llamada.
2. Los datos salen de la base de datos:
   ```bash
   curl http://localhost:8000/rooms/1
   ```
3. Desde PostgreSQL se ve la conexión abierta por el backend. El backend se
   identifica como `backend@<hostname>`:
   ```bash
   docker compose exec database psql -U smartcampus -d smartcampus -c "SELECT application_name, client_addr, state FROM pg_stat_activity WHERE application_name LIKE 'backend%';"
   ```
   ```
      application_name   | client_addr | state
   ----------------------+-------------+-------
    backend@6290a10eba37 | 172.19.0.3  | idle
   ```

📸 `03-compose-backend-bd.png`: la consulta del punto 3 (y si quieres, el punto 2).

Para la memoria: el backend se conecta con `DB_HOST=database`, el nombre del
servicio en Compose, que resuelve el DNS interno de Docker. El frontend no está
en la red `backend-net`, así que no puede llegar a la base de datos. Se puede
comprobar con:

```bash
docker compose exec frontend nslookup database
```

que responde `NXDOMAIN` (no encuentra el nombre).

### Prueba 4: el frontend obtiene datos del backend

1. Abre <http://localhost:8080>.
2. Arriba a la derecha debe salir en verde **Backend OK · BD OK · \<id del contenedor\>**.
3. Las tablas de aulas y reservas se rellenan con los datos del backend.
4. Crea una reserva desde **Nueva reserva**. Si intentas reservar la misma aula
   en una franja que se solapa, sale el error "El aula ya está reservada en esa
   franja horaria" (409).

📸 `04-compose-app.png`: la web funcionando. Es la captura "Aplicación
funcionando con Docker".

Para la memoria: el navegador llama a `/api/...` en el propio nginx del
frontend, y nginx reenvía la petición a `http://backend:8000`. Se puede ver
abriendo <http://localhost:8080/api/rooms>.

### Prueba 5: persistencia

```bash
# 1. Crea una reserva desde la web con usuario "prueba.persistencia"

# 2. Borra los contenedores, pero NO el volumen
docker compose down
docker volume ls          # sigue existiendo smartcampus_db-data

# 3. Vuelve a levantar todo
docker compose up -d
docker compose ps

# 4. La reserva sigue ahí
curl http://localhost:8000/bookings
```

📸 `05-compose-persistencia.png`: `docker compose down`, `docker volume ls`,
`docker compose up -d` y la reserva en la lista (en la web o con curl).

Para la memoria: los datos están en el volumen `db-data`, fuera del
contenedor. `docker compose down -v` sí borraría el volumen. En ese caso, al
volver a arrancar, PostgreSQL ejecutaría otra vez `init.sql` y solo quedarían
los datos de ejemplo.

### Experimento 2: fallo de un contenedor

**a) Parada manual con `docker stop`**

```bash
docker stop smartcampus-backend-1
docker compose ps -a
curl http://localhost:8080/api/health        # 502 Bad Gateway
```

La web muestra en rojo **Backend no disponible**. Espera 30 segundos y vuelve
a mirar `docker compose ps -a`: el backend **sigue parado**.

📸 `06-compose-stop.png`

Vuelve a arrancarlo:

```bash
docker compose start backend
```

**b) El proceso del contenedor muere solo**

```bash
docker compose exec backend sh -c "kill 1"
docker compose ps
docker inspect -f "{{.RestartCount}}" smartcampus-backend-1
```

A los pocos segundos el backend vuelve a estar `Up` y `RestartCount` vale 1.

📸 `07-compose-restart.png`

Para la memoria:

- Docker Compose **no** recupera un contenedor parado a mano. La política
  `restart: unless-stopped` (o `always`) solo lo reinicia si el proceso termina
  por sí mismo o si se reinicia Docker. Con `restart: on-failure` solo se
  reiniciaría si sale con un código de error.
- El *healthcheck* marca el contenedor como `unhealthy`, pero Docker **no** lo
  reinicia por eso.
- Todo ocurre en una sola máquina: si se cae el host, no hay otra réplica que
  siga atendiendo.

### Opcional: escalar con Docker Compose

```bash
docker compose up -d --scale backend=3
```

Falla con `Bind for 0.0.0.0:8000 failed: port is already allocated`, porque
las tres réplicas intentan publicar el mismo puerto del host. El fichero
`docker-compose.scale.yml` quita esa publicación:

```bash
docker compose -f docker-compose.yml -f docker-compose.scale.yml up -d --scale backend=3
docker compose ps
```

En la web, **Enviar 20 peticiones** muestra los tres contenedores
respondiendo, porque el DNS de Docker devuelve la IP de todas las réplicas.
Para volver a la normalidad:

```bash
docker compose up -d --scale backend=1
```

Esto sirve para la pregunta 13 de la memoria ("¿Cómo se escala la aplicación
con Docker Compose?") y para la comparativa: se puede escalar, pero a mano, en
una sola máquina y sin autoescalado.

Cuando termines con Docker, puedes dejarlo funcionando o pararlo con
`docker compose down`.

---

## Parte 2. Kubernetes (Minikube)

### Preparación

```bash
minikube start

# Construir las imágenes y cargarlas en Minikube
docker compose build
minikube image load smartcampus-backend:1.0
minikube image load smartcampus-frontend:1.0
minikube image ls | grep smartcampus      # PowerShell: minikube image ls | Select-String smartcampus
```

Las imágenes se construyen en tu Docker, pero Minikube tiene su propio
almacén de imágenes. Si no se cargan, los Pods se quedan en `ErrImagePull`.

### Experimento 3: desplegar la aplicación

```bash
cd k8s
kubectl apply -f .
kubectl config set-context --current --namespace=smartcampus
kubectl get pods -w          # espera a que todos estén Running y 1/1, luego Ctrl+C
```

Después:

```bash
kubectl get pods
kubectl get services
kubectl get deployments
```

Salida esperada (los sufijos de los nombres y las IPs serán otros). Si al aplicar sale el aviso `spec.SessionAffinity is ignored for headless services`, es informativo y se puede ignorar:

```
NAME                        READY   STATUS    RESTARTS   AGE
backend-6f669486b7-8kdjc    1/1     Running   0          2m
backend-6f669486b7-fgzrl    1/1     Running   0          2m
database-0                  1/1     Running   0          2m
frontend-57c46747bc-7k2jk   1/1     Running   0          2m

NAME                TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
backend-service     ClusterIP   10.43.144.178   <none>        8000/TCP       2m
database-headless   ClusterIP   None            <none>        5432/TCP       2m
database-service    ClusterIP   10.43.239.106   <none>        5432/TCP       2m
frontend-service    NodePort    10.43.67.230    <none>        80:30080/TCP   2m

NAME       READY   UP-TO-DATE   AVAILABLE   AGE
backend    2/2     2            2           2m
frontend   1/1     1            1           2m
```

📸 `08-k8s-apply.png`: la salida de `kubectl apply -f .`
📸 `09-k8s-get-pods.png`
📸 `10-k8s-get-services.png`
📸 `11-k8s-get-deployments.png`

Para la sección de la base de datos de la memoria (StatefulSet frente a
Deployment):

```bash
kubectl get statefulsets
kubectl get pvc
```

📸 `12-k8s-statefulset-pvc.png`

Para demostrar que la comunicación va por Services y no por IPs de Pods:

```bash
kubectl get endpointslices -l kubernetes.io/service-name=backend-service
kubectl exec deploy/backend -- python -c "import socket; print(socket.gethostbyname('database-service'))"
```

El primero muestra las IPs de los Pods que hay detrás de `backend-service`. El
segundo muestra que el backend resuelve `database-service` por DNS a la IP
fija del Service (la `CLUSTER-IP` de `kubectl get services`).

### Exposición del frontend

```bash
minikube service frontend-service -n smartcampus
```

Se abre el navegador con la aplicación. En Windows y Mac, Minikube crea un
túnel y la terminal tiene que quedarse abierta. Comprueba que:

- arriba pone **entorno: kubernetes** (viene del ConfigMap);
- la píldora verde muestra el nombre de un Pod del backend;
- **Enviar 20 peticiones** reparte las respuestas entre los 2 Pods del backend.

📸 `13-k8s-app.png`: es la captura "Aplicación funcionando en Kubernetes".

### Experimento 4: escalado

```bash
kubectl scale deployment backend --replicas=4
kubectl get pods
```

Justo después salen 2 Pods nuevos en `ContainerCreating`. Unos segundos más
tarde:

```bash
kubectl get pods -l app=backend
kubectl get deployment backend       # READY 4/4
```

En la web, **Enviar 20 peticiones** muestra ahora 4 Pods distintos.

📸 `14-k8s-escalado-4.png`: `kubectl get pods` con las 4 réplicas.
📸 `15-k8s-escalado-web.png`: la web repartiendo entre 4 Pods.

Bajar otra vez:

```bash
kubectl scale deployment backend --replicas=2
kubectl get pods -l app=backend      # 2 Pods en Terminating y, después, solo 2
```

📸 `16-k8s-escalado-2.png`

### Experimento 5: self-healing

Abre una **segunda terminal** y deja esto en marcha para ver la secuencia:

```bash
kubectl get pods -l app=backend -w
```

En la primera terminal:

```bash
kubectl get pods -l app=backend
kubectl delete pod <nombre-de-uno-de-los-pods-del-backend>
kubectl get pods -l app=backend
```

En la segunda terminal se ve el Pod borrado pasar a `Terminating` y, a la vez,
un Pod nuevo `Pending` → `ContainerCreating` → `Running`.

Para ver quién lo ha hecho:

```bash
kubectl describe replicaset -l app=backend      # al final, en Events: SuccessfulCreate
kubectl get events --sort-by=.lastTimestamp
```

📸 `17-k8s-delete-pod.png`: el `kubectl delete pod` y el `kubectl get pods` de justo después.
📸 `18-k8s-recuperacion.png`: la segunda terminal con la secuencia y/o los eventos.

Para la memoria, el enunciado pide documentar:

1. **Qué Pod se eliminó**: el nombre exacto.
2. **Qué ocurrió inmediatamente después**: apareció otro Pod con un nombre
   nuevo, y en pocos segundos volvió a haber 2 réplicas `Running`.
3. **Qué recurso mantuvo el estado deseado**: el **ReplicaSet** que crea el
   Deployment `backend`. Su controlador compara las réplicas deseadas (2) con
   las que existen (1) y crea las que faltan.
4. **Diferencia con Docker**: con `docker stop` o `docker rm` el contenedor no
   vuelve (Experimento 2). Docker solo reinicia el mismo contenedor si su
   proceso muere, y en la misma máquina. Kubernetes trabaja con un estado
   deseado: crea un Pod nuevo, puede ponerlo en otro nodo, y el Service deja de
   enviar tráfico al Pod borrado.

Opcional, para la base de datos:

```bash
kubectl delete pod database-0
kubectl get pods -l app=database -w
```

El StatefulSet crea otro Pod **con el mismo nombre** (`database-0`), que vuelve
a montar el mismo volumen (`data-database-0`). Las reservas que hubieras
creado siguen ahí.

### Experimento 6: cambiar el ConfigMap

```bash
# 1. Valor actual dentro de un Pod
kubectl exec deploy/backend -- printenv APP_ENV       # kubernetes
```

2. Edita `k8s/01-configmap.yaml` y cambia `APP_ENV: "kubernetes"` por
   `APP_ENV: "kubernetes-v2"`.

```bash
# 3. Aplicar solo el ConfigMap
kubectl apply -f 01-configmap.yaml
kubectl get configmap smartcampus-config -o yaml      # ya pone kubernetes-v2

# 4. Los Pods NO se enteran
kubectl exec deploy/backend -- printenv APP_ENV       # sigue en kubernetes
kubectl get pods                                      # los mismos Pods, misma AGE
```

En la web sigue poniendo **entorno: kubernetes**.

📸 `19-k8s-configmap-antes.png`

```bash
# 5. Reiniciar los Deployments para que lean la nueva configuración
kubectl rollout restart deployment backend frontend
kubectl rollout status deployment backend
kubectl get pods                                      # Pods nuevos
kubectl exec deploy/backend -- printenv APP_ENV       # kubernetes-v2
```

Recarga la web: ahora pone **entorno: kubernetes-v2**, y `/api/health`
devuelve `"environment":"kubernetes-v2"`.

📸 `20-k8s-configmap-despues.png`

Para la memoria: las variables de entorno se leen **una sola vez, al arrancar
el contenedor**. Cambiar el ConfigMap no reinicia los Pods. Hay que hacer un
`rollout restart`, que sustituye los Pods de uno en uno sin cortar el servicio.
Si el ConfigMap se montara como volumen, el fichero sí se actualizaría solo
(tras un minuto aproximadamente), pero la aplicación tendría que volver a
leerlo.

Al terminar, puedes volver a poner `kubernetes` y repetir el `apply` y el
`rollout restart`.

### Ampliación opcional: autoescalado (HPA)

```bash
minikube addons enable metrics-server
kubectl apply -f extras/hpa-backend.yaml
kubectl get hpa          # TARGETS puede salir <unknown> durante 1-2 minutos

# Generar carga: un Pod que hace peticiones al backend sin parar
kubectl run carga --image=busybox:1.37 --restart=Never -- /bin/sh -c "for i in 1 2 3 4 5 6; do (while true; do wget -q -O /dev/null http://backend-service:8000/rooms; done) & done; wait"

kubectl get hpa -w       # el uso de CPU supera el 50 % y REPLICAS sube
kubectl get pods -l app=backend
```

📸 `21-k8s-hpa.png`: `kubectl get hpa` con las réplicas subiendo.

Para terminar:

```bash
kubectl delete pod carga
kubectl delete -f extras/hpa-backend.yaml
kubectl scale deployment backend --replicas=2
```

Sin carga, el HPA tarda unos 5 minutos en reducir réplicas, para no estar
subiendo y bajando continuamente. Mientras el HPA esté aplicado, deshace los
cambios hechos a mano con `kubectl scale`. Por eso está en otra carpeta y no
se aplica con `kubectl apply -f .`.

### Limpieza

```bash
kubectl delete namespace smartcampus     # borra todo, incluido el volumen de la base de datos
minikube stop
docker compose down
```

---

## Resumen de capturas

| Captura | Entregable del enunciado | Sección de la memoria |
|---|---|---|
| `01-compose-ps.png` | `docker compose ps` | 22.5 Pruebas (Docker) |
| `02-compose-health.png` | Prueba 2: backend | 22.5 |
| `03-compose-backend-bd.png` | Prueba 3: comunicación | 22.5 |
| `04-compose-app.png` | Aplicación funcionando con Docker | 22.5 |
| `05-compose-persistencia.png` | Prueba 5: persistencia | 22.5 |
| `06-compose-stop.png`, `07-compose-restart.png` | Experimento 2 | 22.5 y comparativa |
| `08-k8s-apply.png` | Experimento 3 | 22.5 (Kubernetes) |
| `09-k8s-get-pods.png` | `kubectl get pods` | 22.5 |
| `10-k8s-get-services.png` | `kubectl get services` | 22.5 |
| `11-k8s-get-deployments.png` | `kubectl get deployments` | 22.5 |
| `12-k8s-statefulset-pvc.png` | Base de datos en Kubernetes | 22.4 |
| `13-k8s-app.png` | Aplicación funcionando en Kubernetes | 22.5 |
| `14`, `15`, `16-k8s-escalado-*.png` | Escalado | 22.5 |
| `17-k8s-delete-pod.png` | Eliminación de un Pod | 22.5 |
| `18-k8s-recuperacion.png` | Recuperación automática | 22.5 |
| `19`, `20-k8s-configmap-*.png` | Experimento 6 | 22.5 |
| `21-k8s-hpa.png` | Ampliación HPA (opcional) | 22.5 |

## Plantilla para anotar problemas

Copia esta tabla y rellénala según te vayan pasando cosas. Sirve directamente
para la sección 22.7 de la memoria.

| # | Fase | Síntoma (mensaje de error exacto) | Causa | Solución |
|---|---|---|---|---|
| 1 | Construcción de imágenes / Compose / Kubernetes | | | |
