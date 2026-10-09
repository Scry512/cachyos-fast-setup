#!/usr/bin/env bash
set -euo pipefail

# Paquetes generales
PACKAGES=(
    7zip
    discord
    firefox
    keepassxc
    lutris
    neovim
    libreoffice-fresh
    proton-vpn-cli-app
    qbittorrent
    spotify-launcher
    steam
    vlc
    python
)

# Comprobar que se ejecuta como usuario normal
if [[ "$EUID" -eq 0 ]]; then
    echo "No ejecutes este script como root."
    exit 1
fi

# Herramientas necesarias para instalar paquetes del AUR
sudo pacman -S --needed git base-devel

# Instalar yay si todavía no existe
if ! command -v yay >/dev/null 2>&1; then
    echo "Instalando yay desde el AUR..."

    BUILD_DIR="$(mktemp -d)"
    trap 'rm -rf "$BUILD_DIR"' EXIT

    git clone https://aur.archlinux.org/yay-bin.git "$BUILD_DIR/yay-bin"
    (
        cd "$BUILD_DIR/yay-bin"
        makepkg -si
    )

    rm -rf "$BUILD_DIR"
    trap - EXIT
fi

# Instalar programas generales y resolver dependencias
yay -S --needed "${PACKAGES[@]}"

# Preguntar por las herramientas específicas de portátiles ASUS
read -r -p "¿Instalar asusctl y rog-control-center? [y/N] " ANSWER

case "$ANSWER" in
    [yY]|[yY][eE][sS]|[sS][iI]|[sS][iIíÍ])
        yay -S --needed asusctl rog-control-center
        ;;
    *)
        echo "Se omiten las herramientas ASUS."
        ;;
esac

echo "Instalación terminada."
