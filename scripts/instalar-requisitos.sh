#!/usr/bin/env bash
# Instala lo que necesita la práctica en macOS o en Linux (Ubuntu, Debian y
# derivadas): Git, Docker con Docker Compose, Minikube y kubectl.
#
# Uso, desde la carpeta del repositorio:
#   bash scripts/instalar-requisitos.sh
#
# Lo que ya esté instalado se salta, así que se puede ejecutar varias veces.
# En Linux pide la contraseña de sudo. En Windows se usa
# scripts/instalar-requisitos.ps1.
#
# Solo usa funciones de bash 3.2, la versión que trae macOS.
set -eo pipefail

avisos=()

instalado() { command -v "$1" >/dev/null 2>&1; }

paso() { printf '\n==> %s\n' "$*"; }

# descargar URL DESTINO: baja un fichero y comprueba su SHA-256 con el
# fichero URL.sha256 que publican Minikube y Kubernetes junto a cada binario.
descargar() {
  curl -fL --progress-bar -o "$2" "$1"
  echo "$(curl -fsSL "$1.sha256")  $2" | sha256sum --check --quiet
}

instalar_en_mac() {
  if ! instalado brew; then
    echo "Falta Homebrew, el gestor de paquetes de macOS. Instálalo con el"
    echo "comando que aparece en https://brew.sh y vuelve a ejecutar este script."
    exit 1
  fi
  if ! instalado git; then
    paso "Instalando Git"
    brew install git
  fi
  # La fórmula de Minikube instala kubectl (kubernetes-cli) como dependencia.
  if ! instalado minikube; then
    paso "Instalando Minikube y kubectl"
    brew install minikube
  fi
  if ! instalado kubectl; then
    paso "Instalando kubectl"
    brew install kubernetes-cli
  fi
  if ! instalado docker && [ ! -d /Applications/Docker.app ]; then
    paso "Instalando Docker Desktop"
    brew install --cask docker-desktop
  fi
  avisos+=("Abre Docker Desktop desde Aplicaciones, acepta sus condiciones y espera a que indique \"Engine running\".")
}

instalar_en_linux() {
  local distro version arch usuario tmp

  if ! instalado apt-get; then
    echo "Este script solo sabe instalar en Ubuntu, Debian y sus derivadas (apt)."
    echo "En otra distribución, instala los programas con los enlaces del README."
    exit 1
  fi
  # shellcheck source=/dev/null
  . /etc/os-release
  if [ -n "${UBUNTU_CODENAME:-}" ]; then
    # Ubuntu y sus derivadas (Linux Mint, Pop!_OS...)
    distro=ubuntu
    version=$UBUNTU_CODENAME
  else
    distro=debian
    version=$VERSION_CODENAME
  fi
  arch=$(dpkg --print-architecture)    # amd64 o arm64

  paso "Instalando Git, curl y certificados"
  sudo apt-get update
  sudo apt-get install -y git curl ca-certificates

  if ! instalado docker; then
    # Pasos de https://docs.docker.com/engine/install/ubuntu/ (y debian/)
    paso "Instalando Docker Engine y Docker Compose desde el repositorio de Docker"
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL "https://download.docker.com/linux/$distro/gpg" -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$distro $version stable" |
      sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi

  # Sin pertenecer al grupo docker, docker y Minikube (con el driver docker)
  # solo funcionan con sudo.
  usuario=${USER:-$(id -un)}
  if getent group docker >/dev/null && [[ " $(id -nG "$usuario") " != *" docker "* ]]; then
    sudo usermod -aG docker "$usuario"
    avisos+=("Cierra la sesión y vuelve a entrar (o reinicia) para poder usar docker sin sudo.")
  fi

  tmp=$(mktemp -d)
  if ! instalado minikube; then
    paso "Instalando Minikube"
    descargar "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-$arch" "$tmp/minikube"
    sudo install -m 0755 "$tmp/minikube" /usr/local/bin/minikube
  fi
  if ! instalado kubectl; then
    paso "Instalando kubectl"
    descargar "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/$arch/kubectl" "$tmp/kubectl"
    sudo install -m 0755 "$tmp/kubectl" /usr/local/bin/kubectl
  fi
  rm -rf "$tmp"
}

# mostrar_version NOMBRE COMANDO [ARGUMENTOS...]: escribe la primera línea
# de la salida del comando, o NO DISPONIBLE si falla.
mostrar_version() {
  local nombre=$1 salida
  shift
  if salida=$("$@" 2>/dev/null) && [ -n "$salida" ]; then
    printf '  %-15s %s\n' "$nombre" "${salida%%$'\n'*}"
  else
    printf '  %-15s %s\n' "$nombre" "NO DISPONIBLE"
    falta=1
  fi
}

case "$(uname -s)" in
  Darwin) instalar_en_mac ;;
  Linux) instalar_en_linux ;;
  *)
    echo "Sistema no reconocido. En Windows usa scripts/instalar-requisitos.ps1."
    exit 1
    ;;
esac

# Minikube usará Docker para crear el clúster (es lo que espera la guía).
if instalado minikube; then
  minikube config set driver docker >/dev/null 2>&1 || true
fi

paso "Comprobación"
falta=0
mostrar_version Git git --version
mostrar_version Docker docker --version
mostrar_version "Docker Compose" docker compose version
mostrar_version Minikube minikube version --short
mostrar_version kubectl kubectl version --client

echo
if [ "$falta" -eq 1 ]; then
  avisos+=("Lo que sale como NO DISPONIBLE no se ha instalado bien: revisa los mensajes de arriba, abre una terminal nueva y vuelve a ejecutar el script.")
fi
for aviso in "${avisos[@]}"; do
  echo "- $aviso"
done
echo "- Después sigue el README a partir de \"1. Despliegue con Docker Compose\"."
