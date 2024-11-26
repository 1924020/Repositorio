#!/bin/bash

# Archivo de lock para evitar ejecuciones simultáneas
LOCKFILE="/tmp/monitorizacion.lock"
# Dirección de alerta
ALERT_EMAIL="nohomothoo@gmail.com"
# Ruta al script de supervisión completa
SUPERVISION_SCRIPT="/home/monitoreo_ps.sh"

# Función para generar una alerta por correo en caso de eventos críticos
send_alert() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "ALERTA CRÍTICA [$timestamp]: $message" | msmtp "$ALERT_EMAIL"
}

# Evitar ejecuciones simultáneas
if [ -e "$LOCKFILE" ]; then
    echo "El script ya se está ejecutando. Saliendo..."
    exit 0
fi
touch "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

# Ejecutar el script de supervisión completa y capturar su salida sin registrar en el log
events=$(bash "$SUPERVISION_SCRIPT" 2>&1)

# Filtrar solo las líneas que contienen "ALERTA", "Advertencia", "error", "fail", "warn" o "critical"
critical_events=$(echo "$events" | grep -iE "ALERTA|Advertencia|error|fail|warn|critical")

# Si encontramos eventos críticos, generar una alerta
if [ -n "$critical_events" ]; then
    send_alert "$critical_events"
fi

# Salir sin registrar nada en el log
exit 0