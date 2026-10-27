# Instala lo que necesita la práctica en Windows 10 u 11: WSL 2, Git,
# Docker Desktop, Minikube y kubectl. Usa winget, el instalador de
# aplicaciones que trae Windows.
#
# Uso, en PowerShell y desde la carpeta del repositorio:
#   powershell -ExecutionPolicy Bypass -File scripts\instalar-requisitos.ps1
#
# Lo que ya esté instalado se salta, así que se puede ejecutar varias veces.
# Windows pedirá permiso de administrador para instalar WSL y Docker Desktop.
#
# Está escrito para Windows PowerShell 5.1, la versión que trae Windows, y
# guardado en UTF-8 con BOM para que esa versión lea bien las tildes.

$avisos = New-Object System.Collections.Generic.List[string]

function Paso([string]$texto) {
    Write-Host ''
    Write-Host "==> $texto" -ForegroundColor Cyan
}

function Instalado([string]$comando) {
    return [bool](Get-Command $comando -ErrorAction SilentlyContinue)
}

# Vuelve a leer el PATH del registro para encontrar lo que se acaba de
# instalar sin tener que abrir otra terminal.
function Recargar-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
        [Environment]::GetEnvironmentVariable('Path', 'User')
}

if (-not (Instalado 'winget')) {
    Write-Host 'No se encuentra winget. Instala o actualiza "Instalador de aplicación" desde Microsoft Store y vuelve a ejecutar este script.' -ForegroundColor Red
    exit 1
}

# 1. WSL 2. Docker Desktop ejecuta los contenedores en una máquina virtual de
#    WSL 2. La versión actual de WSL se instala en "Archivos de programa\WSL";
#    la que venía de serie con Windows es demasiado antigua para Docker.
Paso 'WSL 2'
$archivosDePrograma = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$wsl = Join-Path $archivosDePrograma 'WSL\wsl.exe'
if (Test-Path $wsl) {
    Write-Host 'Ya está instalado.'
} else {
    Write-Host 'Instalando WSL. Windows pedirá permiso de administrador.'
    try {
        Start-Process -FilePath 'wsl.exe' -ArgumentList '--install', '--no-distribution' -Verb RunAs -Wait -ErrorAction Stop
    } catch {
        Write-Host "No se pudo ejecutar el instalador de WSL: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    if (Test-Path $wsl) {
        $avisos.Add('Reinicia el ordenador para terminar de instalar WSL antes de abrir Docker Desktop.')
    } else {
        $avisos.Add('No se pudo instalar WSL. Abre PowerShell como administrador, ejecuta "wsl --install --no-distribution" (o "wsl --update" si ya tenías WSL) y reinicia el ordenador.')
    }
}

# 2. Programas, con winget. Si el comando ya existe, se salta.
#    Códigos de winget que no son un error: ya estaba instalado o no hay
#    versión nueva, y "reinicia para terminar la instalación".
$yaInstalado = @(-1978335189, -1978335135, -1978334963)
$hayQueReiniciar = -1978334967
$programas = @(
    @{ Nombre = 'Git';            Id = 'Git.Git';              Comando = 'git' },
    @{ Nombre = 'Docker Desktop'; Id = 'Docker.DockerDesktop'; Comando = 'docker' },
    @{ Nombre = 'Minikube';       Id = 'Kubernetes.minikube';  Comando = 'minikube' },
    @{ Nombre = 'kubectl';        Id = 'Kubernetes.kubectl';   Comando = 'kubectl' }
)
foreach ($programa in $programas) {
    Paso $programa.Nombre
    if (Instalado $programa.Comando) {
        Write-Host 'Ya está instalado.'
        continue
    }
    winget install --id $programa.Id --exact --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq $hayQueReiniciar) {
        $avisos.Add("Reinicia el ordenador para terminar de instalar $($programa.Nombre).")
    } elseif ($LASTEXITCODE -ne 0 -and $yaInstalado -notcontains $LASTEXITCODE) {
        $avisos.Add("No se pudo instalar $($programa.Nombre) (winget devolvió el código $LASTEXITCODE). Revisa el mensaje de arriba.")
    }
    Recargar-Path
}

# 3. Minikube usará Docker para crear el clúster, que es lo que espera la guía.
if (Instalado 'minikube') {
    & minikube config set driver docker *> $null
}

# 4. Comprobación: la primera línea de la versión de cada herramienta.
Paso 'Comprobación'
$falta = $false
$comprobaciones = @(
    @('Git', 'git', '--version'),
    @('Docker', 'docker', '--version'),
    @('Docker Compose', 'docker', 'compose', 'version'),
    @('Minikube', 'minikube', 'version', '--short'),
    @('kubectl', 'kubectl', 'version', '--client')
)
foreach ($c in $comprobaciones) {
    $nombre = $c[0]
    $comando = $c[1]
    $argumentos = @($c[2..($c.Count - 1)])
    $version = $null
    if (Instalado $comando) {
        $version = & $comando @argumentos 2>$null | Select-Object -First 1
    }
    if ($version) {
        Write-Host ('  {0,-15} {1}' -f $nombre, $version)
    } else {
        Write-Host ('  {0,-15} {1}' -f $nombre, 'NO DISPONIBLE') -ForegroundColor Yellow
        $falta = $true
    }
}

Write-Host ''
if ($falta) {
    $avisos.Add('Lo que sale como NO DISPONIBLE no se ha instalado bien o necesita reiniciar: reinicia, abre una terminal nueva y vuelve a ejecutar el script.')
}
foreach ($aviso in $avisos) {
    Write-Host "- $aviso" -ForegroundColor Yellow
}
Write-Host '- Abre Docker Desktop desde el menú Inicio y espera a que indique "Engine running".'
Write-Host '- Después sigue el README a partir de "1. Despliegue con Docker Compose".'
