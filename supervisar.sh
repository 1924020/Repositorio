#!/bin/bash
LOCKFILE="/tmp/monitorizacion_supervisar.lock"
# Dirección de correo para las alertas
ALERT_EMAIL="nohomothoo@gmail.com"
TEMP_FILE="/tmp/monitoreo_ps_output.txt"  # El archivo temporal donde monitoreo_ps.sh guarda su salida

send_alert() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local subject="ALERTA CRÍTICA [$timestamp]"

    # Usamos un archivo temporal para crear el correo con los encabezados
    (echo "Subject: $subject"
     echo "To: $ALERT_EMAIL"
     echo "Content-Type: text/plain; charset=UTF-8"
     echo "MIME-Version: 1.0"
     echo ""
     echo "ALERTA CRÍTICA [$timestamp]: $message") | msmtp "$ALERT_EMAIL"
}

# Comprobar si el script ya está en ejecución
if [ -e "$LOCKFILE" ]; then
    echo "El script ya se está ejecutando. Saliendo..."
    exit 0
fi

# Crear el archivo de bloqueo
touch "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

# Ejecutar monitoreo_ps.sh
echo "Ejecutando monitoreo_ps.sh..."
bash /path/to/monitoreo_ps.sh  # Asegúrate de usar la ruta correcta a tu script

# Verificar si el archivo temporal existe (esto indica que se ejecutó desde supervisar.sh)
if [ -f "$TEMP_FILE" ]; then
    # Leer el archivo temporal que contiene las alertas y verificar si hay alertas críticas
    critical_alerts=$(grep -i "ALERTA CRÍTICA" "$TEMP_FILE")
    
    if [ -n "$critical_alerts" ]; then
        # Si hay alertas críticas, enviamos un correo con el contenido del archivo temporal
        send_alert "$critical_alerts"
    else
        echo "No se detectaron alertas críticas."
    fi
    
    #Borrar el archivo temporal después de enviarlo (para evitar que se acumule)
    rm -f "$TEMP_FILE"
else
    echo "No se generó el archivo temporal. Asegúrate de que monitoreo_ps.sh se ejecute correctamente." > dev/null
fi
