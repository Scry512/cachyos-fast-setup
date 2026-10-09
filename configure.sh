#!/usr/bin/env bash
set -euo pipefail

# Evitar ejecutar como root
if [[ "$EUID" -eq 0 ]]; then
    echo "Ejecuta este script como tu usuario normal, dentro de KDE Plasma."
    exit 1
fi

# Comprobar sesión KDE
if [[ -z "${KDE_SESSION_VERSION:-}" ]]; then
    echo "Aviso: no se detecta una sesión KDE Plasma."
fi

# --------------------------------------------------
# 1. Tema oscuro de KDE Plasma
# --------------------------------------------------

echo
echo "Configurando el tema oscuro..."

if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
    plasma-apply-colorscheme BreezeDark
else
    echo "No se encuentra plasma-apply-colorscheme."
    exit 1
fi

if command -v plasma-apply-desktoptheme >/dev/null 2>&1; then
    plasma-apply-desktoptheme breeze-dark
fi

echo "Tema oscuro configurado."

# --------------------------------------------------
# 2. Copiar wallpapers al directorio personal
# --------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WALLPAPER_SOURCE="$SCRIPT_DIR/wallpapers"
WALLPAPER_DEST="$HOME/Imágenes/wallpapers"

if [[ ! -d "$WALLPAPER_SOURCE" ]]; then
    echo "No existe el directorio: $WALLPAPER_SOURCE"
    exit 1
fi

mkdir -p "$WALLPAPER_DEST"

# Copiar sin sobrescribir archivos existentes
cp -an "$WALLPAPER_SOURCE/." "$WALLPAPER_DEST/"

# --------------------------------------------------
# 3. Seleccionar wallpaper
# --------------------------------------------------

echo
echo "Wallpapers disponibles:"
echo

mapfile -d '' WALLPAPERS < <(
    find "$WALLPAPER_DEST" -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' \
        -o -iname '*.png' -o -iname '*.webp' \
        -o -iname '*.bmp' \) -print0 | sort -z
)

if [[ ${#WALLPAPERS[@]} -eq 0 ]]; then
    echo "No se encontraron wallpapers."
    exit 1
fi

select WALLPAPER in "${WALLPAPERS[@]}"; do
    if [[ -n "${WALLPAPER:-}" && -f "$WALLPAPER" ]]; then
        break
    fi
    echo "Selecciona un número válido."
done

# Obtener ruta absoluta
WALLPAPER="$(realpath "$WALLPAPER")"

echo
echo "Wallpaper seleccionado: $WALLPAPER"

# --------------------------------------------------
# 4. Fondo del escritorio
# --------------------------------------------------

echo
echo "Configurando el fondo del escritorio..."

if command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
    plasma-apply-wallpaperimage "$WALLPAPER"
    echo "Fondo del escritorio aplicado."
else
    echo "No se encuentra plasma-apply-wallpaperimage."
fi

# --------------------------------------------------
# 5. Fondo de la pantalla de bloqueo
# --------------------------------------------------

echo
echo "Configurando la pantalla de bloqueo..."

if command -v kwriteconfig6 >/dev/null 2>&1; then
    kwriteconfig6 --file kscreenlockerrc \
        --group Greeter \
        --group Wallpaper \
        --group org.kde.image \
        --group General \
        --key Image "file://$WALLPAPER"

    echo "Configuración de bloqueo guardada."
    echo "Bloquea y desbloquea la sesión para comprobar el resultado."
else
    echo "No se encuentra kwriteconfig6."
fi

# --------------------------------------------------
# 6. Fondo de inicio de sesión SDDM (Breeze)
# --------------------------------------------------

echo
echo "Configurando la pantalla de inicio de sesión..."

SDDM_THEME_DIR="/usr/share/sddm/themes/breeze"

if [[ -d "$SDDM_THEME_DIR" ]]; then
    SDDM_CONFIG="$SDDM_THEME_DIR/theme.conf.user"

    # Usar el nombre original para conservar la extensión
    WALLPAPER_EXT="${WALLPAPER##*.}"
    SDDM_WALLPAPER_NAME="custom-wallpaper.${WALLPAPER_EXT}"
    SDDM_WALLPAPER="$SDDM_THEME_DIR/$SDDM_WALLPAPER_NAME"

    # Copiar la imagen al directorio del tema
    sudo install -m 644 "$WALLPAPER" "$SDDM_WALLPAPER"

    # Modificar únicamente las claves necesarias,
    # conservando otras opciones de configuración
    if command -v kwriteconfig6 >/dev/null 2>&1; then
        sudo kwriteconfig6 --file "$SDDM_CONFIG" \
            --group General \
            --key type image

        sudo kwriteconfig6 --file "$SDDM_CONFIG" \
            --group General \
            --key background "$SDDM_WALLPAPER_NAME"

        echo "Fondo de SDDM configurado."
    else
        echo "No se encuentra kwriteconfig6; no se modifica SDDM."
    fi
else
    echo "No se encuentra el tema Breeze en:"
    echo "$SDDM_THEME_DIR"
    echo "Se omite la configuración de SDDM."
fi

# --------------------------------------------------
# Fin
# --------------------------------------------------

echo
echo "Configuración terminada."
echo "Wallpaper: $WALLPAPER"
echo
echo "Comprueba el escritorio, bloquea la sesión y"
echo "revisa SDDM en el próximo inicio de sesión."

# --------------------------------------------------
# 7. Aplicaciones fijadas en la barra de tareas
# --------------------------------------------------

echo
echo "Configurando aplicaciones de la barra de tareas..."

APPLETSC="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

if [[ ! -f "$APPLETSC" ]]; then
    echo "No se encuentra la configuración del panel de Plasma."
    exit 1
fi

# Identificadores de aplicaciones (.desktop).
# Comprueba los nombres de CachyOS Settings y Shelly
# en tu instalación antes de ejecutar el bloque.

LAUNCHERS=(
    "applications:org.kde.konsole.desktop"
    "applications:org.kde.filelight.desktop"
    "applications:systemsettings.desktop"
    "applications:org.kde.dolphin.desktop"
    "applications:com.shellyorg.shelly.desktop"
    "applications:vlc.desktop"
    "applications:org.keepassxc.KeePassXC.desktop"
    "applications:firefox.desktop"
    "applications:spotify-launcher.desktop"
    "applications:steam.desktop"
)

# Crear copia de seguridad
cp -n "$APPLETSC" "$APPLETSC.backup"

# Actualizar únicamente la clave launchers del gestor
# de tareas, manteniendo el resto del archivo intacto.
python - "$APPLETSC" "${LAUNCHERS[*]}" <<'PY'
import re
import sys

path = sys.argv[1]
launchers = sys.argv[2].split()

with open(path, encoding="utf-8") as f:
    lines = f.readlines()

# Localizar los bloques de configuración General
# pertenecientes a widgets del gestor de tareas.
targets = []

for i, line in enumerate(lines):
    match = re.fullmatch(
        r"\[Containments\]\[(\d+)\]\[Applets\]\[(\d+)\]\n?",
        line.strip()
    )
    if not match:
        continue

    containment, applet = match.groups()
    prefix = f"[Containments][{containment}][Applets][{applet}]"

    end = i + 1
    while end < len(lines):
        if re.match(r"^\[Containments\]\[\d+\]\[Applets\]\[\d+\]", lines[end]):
            break
        end += 1

    block = "".join(lines[i:end])

    if not re.search(
        r"(?m)^plugin=org\.kde\.plasma\.(?:taskmanager|icontasks)$",
        block
    ):
        continue

    general = prefix + "[Configuration][General]"
    section_start = next(
        (j for j in range(i, end) if lines[j].strip() == general),
        None
    )

    if section_start is not None:
        targets.append((section_start, end))

if not targets:
    sys.exit(
        "No se encontró un gestor de tareas compatible. "
        "No se modificó la configuración."
    )

# Modificar de abajo arriba para conservar los índices.
value = ",".join(launchers)

for start, end in reversed(targets):
    launchers_line = next(
        (j for j in range(start + 1, end)
         if lines[j].startswith("launchers=")),
        None
    )

    if launchers_line is not None:
        lines[launchers_line] = f"launchers={value}\n"
    else:
        lines.insert(start + 1, f"launchers={value}\n")

with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)

print("Orden de lanzadores actualizado.")
PY

echo "Reinicia Plasma o cierra y vuelve a abrir la sesión"
echo "para que los cambios se reflejen en el panel.
