#!/bin/bash

# Mensaje de bienvenida
echo "====================================================="
echo "     Bienvenido al script de creación de usuario"
echo "====================================================="
echo "Este script le permitirá unir un cliente Ubuntu a un dominio OpenLDAP."
echo

# Actualizar los repositorios
echo "Actualizando repositorios..."
if sudo apt update -y > /dev/null 2>&1; then
    echo "Repositorios actualizados con éxito."
    echo " "
else
    echo "Repositorios no actualizados, vuelva a intentarlo."
    echo " "
    exit 1
fi
sleep 2

# Instalar los paquetes necesarios, incluyendo slapd
echo "Instalando paquetes LDAP necesarios..."
if sudo DEBIAN_FRONTEND=noninteractive apt install -y libnss-ldap libpam-ldap ldap-utils nslcd slapd > /dev/null 2>&1; then
    echo "Paquetes LDAP instalados con éxito."
    echo " "
else
    echo "Error al instalar paquetes LDAP. Verifique su conexión a internet o la configuración del sistema."
    exit 1
fi
sleep 2

# Solicitar parámetros al usuario
read -p "Ingrese la IP o nombre del servidor LDAP: " ldap_server
read -p "Ingrese el nombre del dominio (ejemplo: example): " domain_name
read -p "Ingrese la extensión del dominio (ejemplo: com): " domain_ext
read -p "Ingrese el CN del administrador LDAP: " admin_cn
read -sp "Ingrese la contraseña del administrador LDAP: " admin_pass
echo
read -p "Ingrese el nombre del nuevo usuario: " new_user
read -sp "Ingrese la contraseña del nuevo usuario: " user_password
echo

# Apartado sobre UO
echo " "
read -p "¿Desea entrar en una unidad organizativa específica? (s/n): " enter_ou
sleep 2
if [[ $enter_ou =~ ^[sS]$ ]]; then
    read -p "Ingrese el nombre de la Unidad Organizativa (OU) (ejemplo: people): " user_ou
    sleep 2
else
    echo ""
    user_ou="people" # Default OU si no se especifica
fi

domain="${domain_name}.${domain_ext}"

# Verificación de conexión al servidor LDAP
echo "Comprobando conectividad con el servidor LDAP..."
ping -c 3 "$ldap_server" > /dev/null 2>&1 # Ocultar salida de ping
if [ $? -ne 0 ]; then
    echo "No se pudo establecer conexión con el servidor LDAP. Verifique la IP o nombre."
    exit 1
fi

echo "Conexión establecida correctamente."
echo " "
sleep 2

# Comprobar si la OU especificada existe
echo "Verificando si la unidad organizativa '$user_ou' existe..."
if ldapsearch -x -H ldap://${ldap_server} -D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" -w "${admin_pass}" -b "dc=${domain_name},dc=${domain_ext}" "(ou=${user_ou})" | grep -q "ou: ${user_ou}"; then
    echo "La unidad organizativa '$user_ou' ya existe."
    sleep 2
    echo " "
else
    echo "La unidad organizativa '$user_ou' no existe."
    read -p "¿Desea crear la unidad organizativa '$user_ou'? (s/n): " create_ou
    echo " "
    if [[ $create_ou =~ ^[sS]$ ]]; then
        echo "Creando la unidad organizativa '$user_ou'..."
        sleep 1
        
        # Crear archivo LDIF para la OU
        sudo bash -c "cat > /tmp/create_ou.ldif <<EOF
dn: ou=${user_ou},dc=${domain_name},dc=${domain_ext}
objectClass: organizationalUnit
ou: ${user_ou}
EOF"
        
        # Añadir la OU al servidor LDAP
        if ldapadd -x -H ldap://${ldap_server} -D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" -w "${admin_pass}" -f /tmp/create_ou.ldif > /dev/null 2>&1; then
            echo "La unidad organizativa '$user_ou' se ha creado correctamente."
            echo " "
        else
            echo "Error: No se pudo crear la unidad organizativa '$user_ou'."
            exit 1
        fi
    else
        echo "No se creará la unidad organizativa '$user_ou'."
        exit 1
    fi
fi

# Consultar última ID asignada y calcular la nueva
echo "Consultando la última ID asignada en el dominio LDAP..."
last_id=$(ldapsearch -x -H ldap://${ldap_server} -D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" -w "${admin_pass}" -b "dc=${domain_name},dc=${domain_ext}" "(uid=*)" uidNumber | grep uidNumber | sort -n -k2 | tail -n1 | awk '{print $2}')
new_id=$((last_id + 1))

echo "La última UID asignada fue: $last_id"
echo "Se asignará la nueva UID: $new_id"
echo " "
sleep 2

# Crear un archivo temporal con los datos del nuevo usuario
echo "Creando el usuario en LDAP..."
sudo bash -c "cat > /tmp/new_user.ldif <<EOF
dn: uid=${new_user},ou=${user_ou},dc=${domain_name},dc=${domain_ext}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: ${new_user}
sn: ${new_user}
givenName: ${new_user}
cn: ${new_user}
displayName: ${new_user}
uidNumber: ${new_id}
gidNumber: 10000
userPassword: $(slappasswd -s ${user_password})
loginShell: /bin/bash
homeDirectory: /home/${new_user}
EOF"

# Añadir el nuevo usuario al servidor LDAP
ldapadd -x -H ldap://${ldap_server} -D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" -w "${admin_pass}" -f /tmp/new_user.ldif > /dev/null 2>&1 # Ocultar salida de ldapadd
if [ $? -ne 0 ]; then
    echo "Error: No se ha podido crear el usuario ${new_user}."
    exit 1
fi

# Comprobación del nuevo usuario
echo "Comprobando si el usuario fue creado correctamente..."
ldapsearch -x -H ldap://${ldap_server} -D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" -w "$admin_pass" -b "dc=${domain_name},dc=${domain_ext}" "(uid=${new_user})" uid cn | grep "uid:\|cn:" > /dev/null 2>&1 # Ocultar salida de ldapsearch
if [ $? -eq 0 ]; then
    echo "El usuario ${new_user} se ha creado correctamente."
    echo " "
else
    echo "Error: No se ha podido crear el usuario ${new_user}."
fi

# Eliminar archivo temporal
sudo rm /tmp/new_user.ldif

# Preguntar si se desea crear un perfil móvil
read -p "¿Desea crear un perfil móvil para el nuevo usuario? (s/n): " create_mobile_profile
echo " "
sleep 2

if [[ $create_mobile_profile =~ ^[sS]$ ]]; then
    # Verificar si la carpeta para perfiles móviles ya existe
    if [ ! -d "/moviles" ]; then
        echo "Creando carpeta para perfiles móviles en el servidor..."
        sudo mkdir -p /moviles
        echo "Carpeta /moviles creada con éxito."
        echo " "
    else
        echo "La carpeta /moviles ya existe. Se trabajará sobre ella."
        echo " "
        sleep 2
    fi

    # Comprobación de si /etc/exports existe
    if [ ! -f /etc/exports ]; then
        echo "El archivo /etc/exports no existe. Creándolo..."
        sudo touch /etc/exports
    fi

    # Compartir el directorio /moviles
    echo "Compartiendo el directorio /moviles..."
    if ! grep -q "/moviles" /etc/exports; then
        echo "/moviles *(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports > /dev/null
        echo "Directorio /moviles compartido con permisos de lectura/escritura."
    else
        echo "El directorio /moviles ya está compartido."
        echo " "
        sleep 2
    fi

    # Modificar la cuenta de usuario LDAP para incluir el directorio home
    home_directory="/moviles/${new_user}"
    sudo bash -c "cat > /tmp/update_user.ldif <<EOF
dn: uid=${new_user},ou=${user_ou},dc=${domain_name},dc=${domain_ext}
changetype: modify
replace: homeDirectory
homeDirectory: ${home_directory}
EOF"

    # Aplicar la modificación al servidor LDAP
    if ldapmodify -x -H ldap://${ldap_server} -D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" -w "${admin_pass}" -f /tmp/update_user.ldif > /dev/null 2>&1; then
        echo "Perfil móvil configurado para el usuario ${new_user}."
        echo " "
        sleep 2

        # Verificar si el cambio fue exitoso
        echo "Verificando la configuración del perfil móvil..."
        result=$(ldapsearch -x -H ldap://${ldap_server} -D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" -w "${admin_pass}" -b "uid=${new_user},ou=${user_ou},dc=${domain_name},dc=${domain_ext}" homeDirectory | grep "^homeDirectory: " | awk '{print $2}')
        
        if [[ "$result" == "$home_directory" ]]; then
            echo "El perfil móvil ha sido configurado correctamente en ${home_directory}."
            sleep 2
            echo " "
        else
            echo "Error: No se pudo configurar correctamente el perfil móvil. Directorio actual: $result"
            echo " "
        fi
    else
        echo "Error: No se pudo configurar el perfil móvil para el usuario ${new_user}."
        echo " "
    fi

    # Eliminar archivo temporal
    sudo rm /tmp/update_user.ldif
else
    echo "No se creará un perfil móvil para el nuevo usuario."
fi


# Mensaje de finalización
echo "============================================="
echo "           Proceso completado."
echo "============================================="
