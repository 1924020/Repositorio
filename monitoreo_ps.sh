#!/bin/bash

LOG_FILE="/var/log/monitorizacion.log"
LOCKFILE="/tmp/monitorizacion.lock"

log_event() {
    local message="$1"
    local level="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    logger -t monitorizacion "$message"
    echo "$timestamp - [$level] - $message" >> "$LOG_FILE"
}

if [ -e "$LOCKFILE" ]; then
    log_event "El script ya se está ejecutando. Saliendo..." "CRITICAL"
    exit 1
fi
touch "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

log_event "======================== Inicio de la Supervisión =======================" "INFO"

# 1. Procesos más pesados (CPU y Memoria)
log_event "Procesos que más CPU y memoria consumen:" "INFO"
ps aux --sort=-%cpu | head -n 11 | tail -n 5 >> "$LOG_FILE"  # Mejora la forma de mostrar los primeros 5 procesos con más CPU
ps aux --sort=-%mem | head -n 11 | tail -n 5 >> "$LOG_FILE"  # Mejora la forma de mostrar los primeros 5 procesos con más Memoria

# 2. Espacio en disco
log_event "Revisando espacio en disco..." "INFO"
df -h --output=source,pcent,avail | grep -E '([0-9]{1,2})%' | awk '{ if ($2+0 > 90) print "Advertencia: La partición " $1 " tiene menos del 10% de espacio libre. Espacio disponible: " $3 }' >> "$LOG_FILE"

# 3. Logs críticos
log_event "Revisando logs críticos..." "INFO"
grep -I -iE "error|fail|warn|critical" /var/log/syslog | tail -n 20 >> "$LOG_FILE"
dmesg | grep -iE "error|fail|warn|critical" | tail -n 20 >> "$LOG_FILE"

# 4. Tiempo de actividad
log_event "Tiempo de actividad del sistema:" "INFO"
uptime -p >> "$LOG_FILE"

# 5. Supervisión de Servicios Activos
log_event "======================== Servicios Activos =======================" "INFO"
active_services=$(systemctl list-units --type=service --state=active --no-pager | awk 'NR>1 {print $1}' | grep -E 'apache2|mysql|nginx|sshd|ufw|network|cups')
total_active_services=$(systemctl list-units --type=service --state=active --no-pager | awk 'NR>1 {print $1}' | wc -l)

log_event "Total de servicios activos: $total_active_services" "INFO"
if [ -n "$active_services" ]; then
    echo "$active_services" >> "$LOG_FILE"
else
    log_event "No hay servicios activos relevantes." "INFO"
fi

# 6. Supervisión de Servicios Inactivos o Fallidos
log_event "======================== Servicios Inactivos o Fallidos =======================" "INFO"
failed_services=$(systemctl list-units --type=service --state=failed --no-pager | awk 'NR>1 {print $1}' | grep -E 'apache2|mysql|nginx|sshd|ufw|network|cups')
inactive_services=$(systemctl list-units --type=service --state=inactive --no-pager | awk 'NR>1 {print $1}' | grep -E 'apache2|mysql|nginx|sshd|ufw|network|cups')

total_failed_services=$(systemctl list-units --type=service --state=failed --no-pager | awk 'NR>1 {print $1}' | wc -l)
total_inactive_services=$(systemctl list-units --type=service --state=inactive --no-pager | awk 'NR>1 {print $1}' | wc -l)

log_event "Total de servicios fallidos: $total_failed_services" "INFO"
log_event "Total de servicios inactivos: $total_inactive_services" "INFO"

if [ -n "$failed_services" ]; then
    log_event "Servicios Fallidos:" "INFO"
    echo "$failed_services" >> "$LOG_FILE"
else
    log_event "No se encontraron servicios fallidos relevantes." "INFO"
fi

if [ -n "$inactive_services" ]; then
    log_event "Servicios Inactivos:" "INFO"
    echo "$inactive_services" >> "$LOG_FILE"
else
    log_event "No se encontraron servicios inactivos relevantes." "INFO"
fi

# 7. Uso de swap
log_event "Uso de swap:" "INFO"
free -h | grep "Swap" >> "$LOG_FILE"

# 8. Conectividad a Internet y al Servidor Local
log_event "Comprobando conectividad a Internet..." "INFO"
ping -c 4 8.8.8.8 &>/dev/null
if [ $? -eq 0 ]; then
    log_event "Conexión a internet: OK" "INFO"
else
    log_event "Conexión a internet: FALLIDA" "CRITICAL"
fi

log_event "Comprobando conectividad al Servidor Local..." "INFO"
ping -c 4 192.168.1.100 &>/dev/null
if [ $? -eq 0 ]; then
    log_event "Conexión al servidor local: OK" "INFO"
else
    log_event "Conexión al servidor local: FALLIDA" "CRITICAL"
fi

# 9. Uso de red
log_event "Uso de red por interfaz:" "INFO"
ifstat -t 1 1 | grep -v 'Time' | tail -n +3 >> "$LOG_FILE"

# 10. Usuarios conectados
log_event "Usuarios actualmente conectados:" "INFO"
who >> "$LOG_FILE"

# 11. Carga promedio
log_event "Carga promedio del sistema (1, 5, 15 minutos):" "INFO"
uptime | awk -F'load average:' '{print $2}' >> "$LOG_FILE"

# 12. Actualizaciones pendientes
log_event "Comprobando actualizaciones pendientes..." "INFO"
updates=$(apt list --upgradeable 2>/dev/null | tail -n +2)
if [ -n "$updates" ]; then
    log_event "Actualizaciones disponibles:" "INFO"
    echo "$updates" >> "$LOG_FILE"
else
    log_event "El sistema está actualizado." "INFO"
fi

# 13. Permisos de archivos críticos
log_event "Verificando permisos de archivos clave..." "INFO"
for file in /etc/passwd /etc/shadow /etc/hosts; do
    perms=$(stat -c "%a %n" "$file")
    echo "$perms" >> "$LOG_FILE"
    if [[ "$perms" =~ ^[0-7]{3}$ && "$perms" -gt 600 ]]; then
        log_event "Permisos inseguros detectados en $file: $perms" "WARNING"
    fi
done

log_event "======================== Fin de la Supervisión ==========================" "INFO"

exit 0