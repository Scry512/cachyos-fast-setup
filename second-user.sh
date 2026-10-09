#!/usr/bin/env bash
set -euo pipefail

GAMING_USER="Juegos"

# Identificar al usuario principal
if [[ "$EUID" -eq 0 ]]; then
    echo "Ejecuta el script como tu usuario normal, sin sudo."
    exit 1
fi

MAIN_USER="$USER"
MAIN_HOME="$(getent passwd "$MAIN_USER" | cut -d: -f6)"

if [[ -z "$MAIN_HOME" || ! -d "$MAIN_HOME" ]]; then
    echo "No se pudo identificar la carpeta personal principal."
    exit 1
fi

echo "Usuario principal: $MAIN_USER"
echo "Usuario secundario: $GAMING_USER"

# --------------------------------------------------
# 1. Seleccionar wallpaper
# --------------------------------------------------

WALLPAPER_DIR="$MAIN_HOME/Imágenes/wallpapers"

if [[ ! -d "$WALLPAPER_DIR" ]]; then
    WALLPAPER_DIR="$MAIN_HOME/Imagenes/wallpapers"
fi

if [[ ! -d "$WALLPAPER_DIR" ]]; then
    WALLPAPER_DIR="$MAIN_HOME/Pictures/wallpapers"
fi

if [[ ! -d "$WALLPAPER_DIR" ]]; then
    echo "No se encontró la carpeta de wallpapers."
    exit 1
fi

mapfile -d '' WALLPAPERS < <(
    find "$WALLPAPER_DIR" -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' \
        -o -iname '*.png' -o -iname '*.webp' \
        -o -iname '*.bmp' \) -print0 | sort -z
)

if [[ ${#WALLPAPERS[@]} -eq 0 ]]; then
    echo "No hay imágenes disponibles."
    exit 1
fi

echo
echo "Selecciona el wallpaper para ambos usuarios:"
select WALLPAPER in "${WALLPAPERS[@]}"; do
    if [[ -n "${WALLPAPER:-}" && -f "$WALLPAPER" ]]; then
        break
    fi
    echo "Selecciona un número válido."
done

WALLPAPER="$(realpath "$WALLPAPER")"

# --------------------------------------------------
# 2. Crear usuario sin privilegios administrativos
# --------------------------------------------------

if ! id "$GAMING_USER" &>/dev/null; then
    sudo useradd --create-home --user-group \
        --shell /bin/bash "$GAMING_USER"
    echo "Usuario $GAMING_USER creado."
else
    echo "El usuario $GAMING_USER ya existe."
fi

# Retirar grupos administrativos habituales
for group in wheel sudo; do
    if id -nG "$GAMING_USER" | tr ' ' '\n' | grep -qx "$group"; then
        sudo gpasswd -d "$GAMING_USER" "$group"
    fi
done

# Solicitar contraseña sin incluirla en el script
echo
echo "Establece la contraseña de $GAMING_USER:"
sudo passwd "$GAMING_USER"

# --------------------------------------------------
# 3. Proteger la carpeta personal principal
# --------------------------------------------------

sudo chmod 700 "$MAIN_HOME"
sudo chown "$MAIN_USER":"$(id -gn "$MAIN_USER")" "$MAIN_HOME"

echo "Permisos de $MAIN_HOME establecidos a 700."

# --------------------------------------------------
# 4. Preparar el wallpaper de Juegos
# --------------------------------------------------

GAMING_HOME="$(getent passwd "$GAMING_USER" | cut -d: -f6)"
GAMING_CONFIG="$GAMING_HOME/.config"
GAMING_AUTOSTART="$GAMING_CONFIG/autostart-scripts"

sudo install -d -o "$GAMING_USER" -g "$GAMING_USER" \
    "$GAMING_HOME/Imágenes/wallpapers" "$GAMING_AUTOSTART"

WALLPAPER_NAME="$(basename "$WALLPAPER")"
GAMING_WALLPAPER="$GAMING_HOME/Imágenes/wallpapers/$WALLPAPER_NAME"

sudo install -o "$GAMING_USER" -g "$GAMING_USER" -m 644 \
    "$WALLPAPER" "$GAMING_WALLPAPER"

# Crear un script que se ejecuta dentro de la sesión KDE
# de Juegos, donde las herramientas de Plasma tienen acceso
# a la sesión gráfica correspondiente.
sudo tee "$GAMING_AUTOSTART/set-wallpaper.sh" >/dev/null <<EOF
#!/usr/bin/env bash
set -e

WALLPAPER="\$HOME/Imágenes/wallpapers/$WALLPAPER_NAME"

if command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
    plasma-apply-wallpaperimage "\$WALLPAPER"
fi

if command -v kwriteconfig6 >/dev/null 2>&1; then
    kwriteconfig6 --file kscreenlockerrc \
        --group Greeter \
        --group Wallpaper \
        --group org.kde.image \
        --group General \
        --key Image "file://\$WALLPAPER"
fi
EOF

sudo chmod 755 "$GAMING_AUTOSTART/set-wallpaper.sh"
sudo chown "$GAMING_USER":"$GAMING_USER" \
    "$GAMING_AUTOSTART/set-wallpaper.sh"

# --------------------------------------------------
# 5. Configurar el fondo de inicio de sesión SDDM
# --------------------------------------------------

SDDM_THEME_DIR="/usr/share/sddm/themes/breeze"

if [[ -d "$SDDM_THEME_DIR" ]]; then
    EXTENSION="${WALLPAPER_NAME##*.}"
    SDDM_WALLPAPER="gaming-wallpaper.$EXTENSION"
    SDDM_CONFIG="$SDDM_THEME_DIR/theme.conf.user"

    sudo install -m 644 "$WALLPAPER" \
        "$SDDM_THEME_DIR/$SDDM_WALLPAPER"

    # Crear el archivo si no existe y cambiar solo las claves
    # pertinentes, conservando el resto de las opciones.
    sudo touch "$SDDM_CONFIG"

    sudo kwriteconfig6 --file "$SDDM_CONFIG" \
        --group General --key type image

    sudo kwriteconfig6 --file "$SDDM_CONFIG" \
        --group General --key background "$SDDM_WALLPAPER"

    echo "Fondo de SDDM configurado."
else
    echo "No se encontró el tema Breeze de SDDM."
    echo "No se ha cambiado el fondo de inicio de sesión."
fi

echo
echo "Configuración terminada."
echo "Usuario: $GAMING_USER"
echo "Wallpaper: $GAMING_WALLPAPER"
echo "El fondo del escritorio se aplicará al iniciar sesión en KDE."
