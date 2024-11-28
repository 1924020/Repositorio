#!/bin/bash

LOCKFILE="/tmp/monitorizacion_supervisar.lock"
ALERT_EMAIL="nohomothoo@gmail.com"
TEMP_FILE="/tmp/monitoreo_ps_output.txt"  # El archivo temporal donde monitoreo_ps.sh guarda su salida 

umask 000 #Prevenir problemas de permisos

send_alert() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local subject="ALERTA CRÍTICA EN EL SERVIDOR[$timestamp]"

    # Usamos un archivo temporal para crear el correo con los encabezados
    (echo "Subject: $subject"
     echo "To: $ALERT_EMAIL"
     echo "Content-Type: text/plain; charset=UTF-8"
     echo "MIME-Version: 1.0"
     echo ""
     echo "$message") | msmtp "$ALERT_EMAIL"
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
bash /home/monitorizacion/monitoreo_ps.sh

# Verificar si el archivo temporal existe (creado desde el script de monitorizacion principal)
if [ -f "$TEMP_FILE" ]; then
    # Leer el archivo temporal que contiene las alertas y verificar si hay alertas críticas que hayan sido registrados con logcheck
    critical_alerts=$(grep -i "CRITICAL" "$TEMP_FILE")
    
    if [ -n "$critical_alerts" ]; then
        # Si hay alertas críticas, enviamos un correo con el contenido del archivo temporal
        send_alert "$critical_alerts"
    else
        echo "No se detectaron alertas críticas."
    fi
    
    # Borrar el archivo temporal después de enviarlo (para evitar que se acumule)
    rm -f "$TEMP_FILE"
else
    #Control de errores, debug al ejecutar
    echo "No se generó el archivo temporal. Asegúrate de que monitoreo_ps.sh se ejecute correctamente." 
fi
