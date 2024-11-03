#!/bin/bash
# Mensaje de bienvenida
clear
echo "============================================================"
echo "         Bienvenido al gestor de su dominio OpenLDAP"
echo "============================================================"
echo "Este script le permitirá insertar, modificar, eliminar y consultar objetos en OpenLDAP :) "
echo " "
sleep 2
echo "Por favor, asegúrese de que está ejecutando este script con sudo."
echo "Proporcione los siguientes parámetros para poder trabajar sobre su dominio:"
echo " "
sleep 2

# Solicitar parámetros al usuario
read -p "Ingrese la IP o nombre del servidor LDAP: " ldap_server
read -p "Ingrese el nombre del dominio (ejemplo: example): " domain_name
read -p "Ingrese la extensión del dominio (ejemplo: com): " domain_ext
read -p "Ingrese el CN del administrador LDAP: " admin_cn
read -sp "Ingrese la contraseña del administrador LDAP: " admin_pass
echo " "

sleep 2
# Verificar conexión con el servidor LDAP
ldapsearch -x -H "ldap://$ldap_server" -D "cn=$admin_cn,dc=$domain_name,dc=$domain_ext" -w "$admin_pass" -b "dc=$domain_name,dc=$domain_ext" >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "No se pudo conectar al servidor LDAP. Verifique los datos de conexión."
    echo " "
    exit 1
else
    echo "Conexión exitosa al servidor LDAP."
    echo " "
    sleep 3
fi

# Función para mostrar el menú principal
menu() {
    clear
    echo "============================================================"
    echo "           Bienvenido a $domain_name.$domain_ext"
    echo "============================================================"
    echo " "
    echo "Menú de opciones:"
    echo "1) Crear una entrada (usuario, grupo, OU)"
    echo "2) Modificar una entrada existente"
    echo "3) Eliminar una entrada"
    echo "4) Realizar una consulta"
    echo "5) Ayuda"
    echo "6) Salir"
    echo " "
    read -p "Seleccione una opción: " option
}

move_user() {

    local user_dn old_ou new_ou base_dn sv_dn  

    # Construcción del DN base del servidor LDAP
    base_dn="dc=${domain_name},dc=${domain_ext}"
    sv_dn="cn=${admin_cn},$base_dn"

    # Solicita el usuario a mover, OU actual y nueva ubicación
    user_dn="uid=${user}"
    old_ou=${user_ou}

    read -p "Introduce la nueva unidad organizativa (dejar en blanco para mover a raíz): " new_ou

    # Construcción de los DNs según la ubicación actual y destino
    if [[ -n "$old_ou" ]]; then
        old_dn="$user_dn,ou=$old_ou,$base_dn"
    else
        old_dn="$user_dn,$base_dn"
    fi

    if [[ -n "$new_ou" ]]; then
        new_dn="$user_dn,ou=$new_ou,$base_dn"
        new_ou_dn="ou=$new_ou,$base_dn"
    else
        new_dn="$user_dn,$base_dn"
        new_ou_dn="$base_dn"  # La nueva ubicación es el directorio raíz
    fi

    # Verificar si la nueva OU existe, y crearla si no existe
    if [[ -n "$new_ou" ]]; then
        echo "Verificando si la OU de destino '$new_ou_dn' existe..."
        echo " "
        ldapsearch -x -H "ldap://${ldap_server}" -D "$sv_dn" -w "$admin_pass" -b "$new_ou_dn" "(objectClass=organizationalUnit)" > /dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            echo "La OU de destino no existe. Creándola ahora..."
            cat <<EOF | ldapadd -x -H "ldap://${ldap_server}" -D "$sv_dn" -w "$admin_pass"
dn: $new_ou_dn
objectClass: organizationalUnit
ou: $new_ou
description: Unidad organizativa creada automáticamente
EOF
            if [[ $? -eq 0 ]]; then
                echo "OU '$new_ou_dn' creada exitosamente."
            else
                echo "Error al crear la OU '$new_ou_dn'. Verifica los permisos."
                return 1
            fi
        else
            echo "La OU de destino '$new_ou_dn' ya existe."
        fi
    fi

    # Verificar si el DN actual existe antes de proceder
    echo "Buscando usuario en: $old_dn"
    ldapsearch -x -H "ldap://${ldap_server}" -D "$sv_dn" -w "$admin_pass" -b "$old_dn" > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        echo "Usuario encontrado. Procediendo con la reubicación..."
        echo " "

        # Archivo LDIF temporal para el cambio de ubicación
        ldif_file=$(mktemp)

        # Crear contenido del LDIF para mover el usuario
        cat <<EOF > "$ldif_file"
dn: $old_dn
changetype: modrdn
newrdn: $user_dn
deleteoldrdn: 1
newsuperior: ${new_ou:+ou=$new_ou,}$base_dn
EOF

        # Ejecutar el comando de modificación y eliminar archivo temporal
        ldapmodify -x -H "ldap://${ldap_server}" -D "$sv_dn" -w "$admin_pass" -f "$ldif_file" > /dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            echo " "
            echo "Usuario reubicado con éxito de '$old_dn' a '$new_dn'."
        else
            echo " "
            echo "Error al intentar reubicar al usuario. Verifica los DN y permisos."
        fi
        rm -f "$ldif_file"
    else
        echo " "
        echo "El usuario especificado no existe en la ubicación actual '$old_dn' o hubo un problema en la búsqueda."
        echo " "
    fi
}

delete_reubicar() {

    local base_dn ou_dn object_count

    # Construcción del DN base del servidor LDAP
    base_dn="dc=${domain_name},dc=${domain_ext}"

    # Solicita el nombre de la unidad organizativa a borrar
    ou_dn=$(ldapsearch -x -H "ldap://$ldap_server" -D "cn=$admin_cn,$base_dn" \
        -w "$admin_pass" -b "$base_dn" "(ou=$entry_name)" | grep "^dn: " | awk '{print $2}')

    if [[ -n "$ou_dn" ]]; then
        # Listar objetos dentro de la OU, excluyendo la propia OU
        object_count=$(ldapsearch -x -H "ldap://$ldap_server" -D "cn=$admin_cn,$base_dn" \
            -w "$admin_pass" -b "$ou_dn" "(!(distinguishedName=$ou_dn))" | grep "^dn: " | wc -l)

        if (( object_count > 0 )); then
            echo -e "\n=== La unidad organizativa '$entry_name' contiene $object_count objeto(s): ==="
            ldapsearch -x -H "ldap://$ldap_server" -D "cn=$admin_cn,$base_dn" \
            -w "$admin_pass" -b "$ou_dn" "(!(distinguishedName=$ou_dn))" dn | grep "^dn: " | sed 's/^dn: / • /'
            echo -e "===========================================\n"

            # Preguntar al usuario si desea reubicar o borrar los objetos
            read -p "¿Desea reubicar los objetos en otra ubicación? (s/n): " relocate_confirm
            if [[ $relocate_confirm =~ ^[sS]$ ]]; then
                # Solicitar la nueva OU de destino
                read -p "Introduce la unidad organizativa de destino (dejar en blanco para mover al raíz): " new_ou
                new_base_dn="${new_ou:+ou=$new_ou,}$base_dn"

                # Verificar si la OU de destino existe, y crearla si no existe
                if [[ -n "$new_ou" ]]; then
                    ou_check=$(ldapsearch -x -H "ldap://$ldap_server" -D "cn=$admin_cn,$base_dn" -w "$admin_pass" -b "$base_dn" "(ou=$new_ou)" | grep "^dn: ")
                    if [[ -z "$ou_check" ]]; then
                        echo "La OU de destino no existe. Creándola ahora..."
                        cat <<EOF | ldapadd -x -H "ldap://$ldap_server" -D "cn=$admin_cn,$base_dn" -w "$admin_pass"
dn: $new_base_dn
objectClass: organizationalUnit
ou: $new_ou
description: Unidad organizativa creada automáticamente
EOF
                    fi
                fi

                # Reubicar los objetos sin incluir la OU original en el DN nuevo
                ldapsearch -x -H "ldap://$ldap_server" -D "cn=$admin_cn,$base_dn" \
                    -w "$admin_pass" -b "$ou_dn" "(!(distinguishedName=$ou_dn))" dn | grep "^dn: " | while read -r dn; do
                    clean_dn=$(echo "$dn" | sed 's/^dn: //')
                    # Extraer solo el identificador de la entrada (ej. "uid=fuki")
                    entry_rdn=$(echo "$clean_dn" | cut -d, -f1)
                    ldapmodify -x -H "ldap://$ldap_server" -D "cn=$admin_cn,$base_dn" -w "$admin_pass" <<EOF
dn: $clean_dn
changetype: modrdn
newrdn: $entry_rdn
deleteoldrdn: 1
newsuperior: $new_base_dn
EOF
                    echo " • Objeto '$clean_dn' reubicado exitosamente a '$new_base_dn'."
                done
                echo -e "\nReubicación completada."
            else
                # Confirmar borrado de todos los objetos dentro de la OU
                read -p "¿Está seguro de que desea borrar la OU '$entry_name' y todos sus objetos? (s/n): " confirm
                if [[ $confirm =~ ^[sS]$ ]]; then
                    ldapsearch -x -H "ldap://$ldap_server" -D "cn=$admin_cn,$base_dn" \
                    -w "$admin_pass" -b "$ou_dn" "(!(distinguishedName=$ou_dn))" dn | grep "^dn: " | while read -r dn; do
                        clean_dn=$(echo "$dn" | sed 's/^dn: //')
                        if ldapdelete -x -H "ldap://$ldap_server" -D "cn=$admin_cn,$base_dn" \
                            -w "$admin_pass" "$clean_dn" 2>/dev/null; then
                                echo " • Objeto '$clean_dn' borrado exitosamente."
                        else
                                echo " "
                        fi
                    done
                    # Ahora borrar la OU
                    if ldapdelete -x -H "ldap://$ldap_server" -D "cn=$admin_cn,$base_dn" \
                        -w "$admin_pass" "$ou_dn" 2>/dev/null; then
                            echo -e "\nUnidad organizativa '$entry_name' borrada exitosamente.\n"
                    else
                            echo -e " "
                    fi
                else
                    echo -e "\nOperación cancelada.\n"
                fi
            fi
        else
            # Confirmar borrado de una OU vacía
            read -p "La OU '$entry_name' está vacía. ¿Desea borrarla? (s/n): " confirm
            if [[ $confirm =~ ^[sS]$ ]]; then
                if ldapdelete -x -H "ldap://$ldap_server" -D "cn=$admin_cn,$base_dn" \
                    -w "$admin_pass" "$ou_dn" 2>/dev/null; then
                        echo -e "\nUnidad organizativa '$entry_name' borrada exitosamente.\n"
                else
                        echo -e " "
                fi
            else
                echo -e "\nOperación cancelada.\n"
            fi
        fi
    else
        echo -e "\nLa unidad organizativa '$entry_name' no existe.\n"
    fi

    echo " "
    echo "Puede comprobar los cambios con las consultas del gestor"
}

create_entry() {
    clear
    read -p "¿Tienes un archivo .ldif con los datos? (s/n): " has_ldif
    echo " "
    if [[ "$has_ldif" == "s" ]]; then
        read -p "Ingrese la ruta del archivo .ldif: " ldif_file
        if [ -f "$ldif_file" ]; then
            ldapadd -x -H "ldap://$ldap_server" -D "cn=$admin_cn,dc=$domain_name,dc=$domain_ext" -w "$admin_pass" -f "$ldif_file" >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo "Entrada creada exitosamente desde el archivo $ldif_file."
                echo " "
            else
                echo "Error al crear la entrada desde el archivo $ldif_file. Revisa el formato del archivo."
                echo " "
            fi
        else
            echo "El archivo especificado no existe. Verifica la ruta e intenta nuevamente."
            echo " "
        fi
    else
        read -p "Ingrese el tipo de objeto (usuario, grupo, OU): " entry_type
        case $entry_type in
            
  usuario)
    read -p "Ingrese el nombre del nuevo usuario: " new_user
    read -sp "Ingrese la contraseña del nuevo usuario: " user_password
    echo " "
    read -p "Ingrese el email (opcional): " user_email
    read -p "Ingrese el teléfono (opcional): " user_phone
    echo " "
    
    read -p "¿Desea asignar el usuario a una unidad organizativa específica? (s/n): " enter_ou
    if [[ $enter_ou =~ ^[sS]$ ]]; then
        read -p "Ingrese el nombre de la Unidad Organizativa (OU) (ejemplo: people): " user_ou
    else
        user_ou=""  # No se establece ninguna OU
    fi

    # Verificar si la OU existe solo si fue especificada
    if [[ -n $user_ou ]]; then
        if ! ldapsearch -x -H ldap://${ldap_server} -D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" -w "${admin_pass}" -b "dc=${domain_name},dc=${domain_ext}" "(ou=${user_ou})" | grep -q "ou: ${user_ou}"; then
            read -p "La unidad organizativa '$user_ou' no existe. ¿Desea crearla? (s/n): " create_ou
            if [[ $create_ou =~ ^[sS]$ ]]; then
                echo "Creando la unidad organizativa '$user_ou'..."
                {
                    echo "dn: ou=${user_ou},dc=${domain_name},dc=${domain_ext}"
                    echo "objectClass: organizationalUnit"
                    echo "ou: ${user_ou}"
                } > /tmp/create_ou.ldif
                
                ldapadd -x -H ldap://${ldap_server} -D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" -w "${admin_pass}" -f /tmp/create_ou.ldif >/dev/null 2>&1
                
                if [ $? -eq 0 ]; then
                    echo "Unidad organizativa '$user_ou' creada exitosamente."
                    echo " "
                else
                    echo "Error al crear la unidad organizativa '$user_ou'."
                    echo " "
                    exit 1
                fi
            fi
        fi
    fi

    # Obtener el uidNumber más alto y generar el siguiente
    max_uid=$(ldapsearch -x -H ldap://${ldap_server} -D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" -w "${admin_pass}" -b "dc=${domain_name},dc=${domain_ext}" "(uid=*)" uidNumber | awk '/^uidNumber: / {print $2}' | sort -n | tail -n1)
    new_uid=$((max_uid + 1))

    # Crear el archivo .ldif del usuario
    echo "Creando el usuario en LDAP..."
    {
        echo "dn: uid=${new_user},${user_ou:+ou=${user_ou},}dc=${domain_name},dc=${domain_ext}"
        echo "objectClass: inetOrgPerson"
        echo "objectClass: posixAccount"
        echo "objectClass: shadowAccount"
        echo "uid: ${new_user}"
        echo "sn: ${new_user}"
        echo "givenName: ${new_user}"
        echo "cn: ${new_user}"
        echo "displayName: ${new_user}"
        echo "uidNumber: ${new_uid}"
        echo "gidNumber: 10000"
        echo "userPassword: $(slappasswd -s ${user_password})"
        echo "loginShell: /bin/bash"
        echo "homeDirectory: /home/${new_user}"
        [[ -n "$user_email" ]] && echo "mail: ${user_email}"
        [[ -n "$user_phone" ]] && echo "telephoneNumber: ${user_phone}"
    } > /tmp/new_user.ldif

    # Añadir el usuario
    ldapadd -x -H ldap://${ldap_server} -D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" -w "${admin_pass}" -f /tmp/new_user.ldif >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "Usuario '${new_user}' creado correctamente."
        echo " "
    else
        echo "Error: No se pudo crear el usuario '${new_user}'."
        echo " "
    fi
    ;;

grupo)
read -p "Ingrese el nombre del nuevo grupo: " new_group

            # Preguntar si se desea introducir en una unidad organizativa específica
            read -p "¿Desea introducir el grupo en una unidad organizativa específica? (s/n): " ou_choice

            if [[ "$ou_choice" == "s" || "$ou_choice" == "S" ]]; then
                read -p "Ingrese el nombre de la unidad organizativa: " ou_name
                echo " "
                # Comprobar si la unidad organizativa existe
                ou_exists=$(ldapsearch -x -H "ldap://${ldap_server}" -D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" -w "${admin_pass}" -b "ou=${ou_name},dc=${domain_name},dc=${domain_ext}" "(objectClass=organizationalUnit)" | grep -c "dn: ou=${ou_name}")

                if [ "$ou_exists" -eq 0 ]; then
                    read -p "La unidad organizativa ${ou_name} no existe. ¿Desea crearla? (s/n): " create_ou
                    if [[ "$create_ou" == "s" || "$create_ou" == "S" ]]; then
                        # Crear archivo LDIF para la unidad organizativa
                        {
                            echo "dn: ou=${ou_name},dc=${domain_name},dc=${domain_ext}"
                            echo "objectClass: organizationalUnit"
                            echo "ou: ${ou_name}"
                        } > /tmp/new_ou.ldif

                        # Añadir la unidad organizativa al servidor LDAP
                        ldapadd -x -H "ldap://${ldap_server}" -D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" -w "${admin_pass}" -f /tmp/new_ou.ldif >/dev/null 2>&1

                        if [ $? -ne 0 ]; then
                            echo "Error: No se pudo crear la unidad organizativa ${ou_name}."
                            exit 1
                        else
                            echo "La unidad organizativa ${ou_name} se ha creado correctamente."
                            echo " "
                            sleep 2
                        fi
                    else
                        echo "No se ha creado la unidad organizativa. Saliendo."
                        exit 1
                    fi
                fi
            else
                ou_name="" # No se establece ninguna OU
            fi

            # Consultar el último gidNumber asignado
            last_gid=$(ldapsearch -x -H "ldap://${ldap_server}" -D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" -w "${admin_pass}" -b "dc=${domain_name},dc=${domain_ext}" "(gidNumber=*)" gidNumber | grep '^gidNumber' | sort -n -k2 | tail -n1 | awk '{print $2}')

            if [[ -z "$last_gid" ]]; then
                echo "No se encontró ningún gidNumber. Se asignará gidNumber 1000 por defecto."
                new_gid=1000
            else
                new_gid=$((last_gid + 1))
            fi
            # Crear archivo LDIF para el grupo
            {
                echo "dn: cn=${new_group},${ou_name:+ou=${ou_name},}dc=${domain_name},dc=${domain_ext}"
                echo "objectClass: posixGroup"
                echo "cn: ${new_group}"
                echo "gidNumber: ${new_gid}"
            } > /tmp/new_group.ldif

            # Añadir el nuevo grupo al servidor LDAP
            ldapadd -x -H "ldap://${ldap_server}" -D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" -w "${admin_pass}" -f /tmp/new_group.ldif >/dev/null 2>&1

            # Comprobar si la creación fue exitosa
            if [ $? -ne 0 ]; then
                echo "Error: No se pudo crear el grupo ${new_group}."
            else
                echo "Grupo '${new_group}' creado exitosamente."
                echo " "
            fi
            ;;

            OU)
read -p "Ingrese el nombre de la nueva unidad organizativa (OU): " new_ou
            # Crear archivo LDIF para la unidad organizativa
            {
                echo "dn: ou=${new_ou},dc=${domain_name},dc=${domain_ext}"
                echo "objectClass: organizationalUnit"
                echo "ou: ${new_ou}"
            } > /tmp/new_ou.ldif

            # Añadir la nueva unidad organizativa al servidor LDAP
            ldapadd -x -H "ldap://${ldap_server}" -D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" -w "${admin_pass}" -f /tmp/new_ou.ldif >/dev/null 2>&1

            # Comprobar si la creación fue exitosa
            if [ $? -ne 0 ]; then
                echo "Error: No se pudo crear la unidad organizativa '${new_ou}'."
            else
                echo "Unidad organizativa '${new_ou}' creada exitosamente."
                echo " "
            fi
            ;;
            *)
echo "Tipo de objeto no reconocido. Por favor, intenta nuevamente."
;;
esac
fi

if repeat_action; then
    create_entry
fi

}

modify_entry() {
    clear
# Preguntar si se desea importar un archivo LDIF
read -p "¿Deseas importar un archivo LDIF con los cambios? (s/n): " import_option

if [[ "$import_option" =~ ^[sS]$ ]]; then
    read -p "Introduce la ruta del archivo LDIF: " ldif_file
    ldapmodify -x -H "ldap://${ldap_server}" \
    -D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" \
    -w "${admin_pass}" -f "${ldif_file}"

    if [ $? -eq 0 ]; then
        echo "Archivo LDIF importado correctamente."
        echo " "
    else
        echo "Error al importar el archivo LDIF. Verifique el contenido del archivo y/o la ubicación."
        echo " "
    fi
    echo " "
fi

# Seleccionar el tipo de objeto a modificar
read -p "Selecciona el tipo de objeto que desea modificar:( usuario, OU, grupo ): " option
echo " "

case $option in
    usuario)
        # Modificar usuario
        read -p "Introduce el UID del usuario que deseas modificar: " user
        read -p "Introduce el nombre de la OU a la que pertenece el usuario. Déjalo en blanco si no pertenece a ninguna OU. (Consulte esta información si la desconoce) " user_ou

        if [ -z "$user_ou" ]; then
            user_dn="uid=${user},dc=${domain_name},dc=${domain_ext}"
        else
            user_dn="uid=${user},ou=${user_ou},dc=${domain_name},dc=${domain_ext}"
        fi

        # Elegir atributo a modificar
        echo "¿Qué atributo deseas modificar para el usuario ${user}?"
        echo "1. Teléfono"
        echo "2. Email"
        echo "3. Contraseña"
        echo "4. Reubicar"
        read -p "Opción: " user_option
        echo " "

        case $user_option in
            1)  # Modificar Teléfono
read -p "Introduce el nuevo número de teléfono: " new_phone
ldapmodify -x -H "ldap://${ldap_server}" \
-D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" \
-w "${admin_pass}" <<EOF
dn: ${user_dn}
changetype: modify
replace: telephoneNumber
telephoneNumber: ${new_phone}
EOF
echo "Teléfono actualizado."
echo " "
;;

            2)  # Modificar Email
read -p "Introduce el nuevo email: " new_email
ldapmodify -x -H "ldap://${ldap_server}" \
-D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" \
-w "${admin_pass}" <<EOF
dn: ${user_dn}
changetype: modify
replace: mail
mail: ${new_email}
EOF
echo "Email actualizado."
echo " "
;;

            3)  # Modificar Contraseña
read -sp "Introduce la nueva contraseña: " new_password
echo
hashed_password=$(slappasswd -s "$new_password")
ldapmodify -x -H "ldap://${ldap_server}" \
-D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" \
-w "${admin_pass}" <<EOF
dn: ${user_dn}
changetype: modify
replace: userPassword
userPassword: ${hashed_password}
EOF
echo "Contraseña actualizada."
echo " "
;;

          4) #Reubicar Usuario
          
          move_user

          ;;  

*)
echo "Opción no válida."
echo " "
;;
esac
;;

    OU)  # Modificar OU
        read -p "Introduce el nombre de la OU que deseas modificar: " ou_name
            ou_dn="ou=${ou_name},dc=${domain_name},dc=${domain_ext}"

            read -p "Introduce la nueva descripción: " new_description
            ldapmodify -x -H "ldap://${ldap_server}" \
            -D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" \
            -w "${admin_pass}" <<EOF
dn: ${ou_dn}
changetype: modify
replace: description
description: ${new_description}
EOF
            echo "Descripción de la OU actualizada."
            echo " "
            ;;

    grupo)  # Modificar Grupo
read -p "Introduce el nombre del grupo que deseas modificar: " group_name
group_dn="cn=${group_name},dc=${domain_name},dc=${domain_ext}"
read -p "Introduce la nueva descripción: " new_description
ldapmodify -x -H "ldap://${ldap_server}" \
-D "cn=${admin_cn},dc=${domain_name},dc=${domain_ext}" \
-w "${admin_pass}" <<EOF
dn: ${group_dn}
changetype: modify
replace: description
description: ${new_description}
EOF
echo "Descripción del grupo actualizada."
echo " "
;;

*)
echo "Opción no válida."
echo " "
;;
esac

if repeat_action; then
    modify_entry
fi
}


delete_entry() {
    clear
    read -p "Ingrese el tipo de objeto a borrar (usuario, grupo, OU): " entry_type
    read -p "Ingrese el nombre del objeto a borrar: " entry_name
    echo " "

# Verificación de la existencia del objeto
case $entry_type in

    usuario)
        # Comprobar si el usuario existe en una OU o en el directorio raíz
        user_dn=$(ldapsearch -x -H "ldap://$ldap_server" -D "cn=$admin_cn,dc=$domain_name,dc=$domain_ext" \
            -w "$admin_pass" -b "dc=$domain_name,dc=$domain_ext" "(uid=$entry_name)" | grep "^dn: " | awk '{print $2}')

        if [[ -n "$user_dn" ]]; then
            # Si el usuario existe, confirmar borrado
            echo -e "\nUsuario encontrado: $user_dn"
            read -p "¿Está seguro de que desea borrar el usuario '$entry_name'? (s/n): " confirm
            if [[ $confirm =~ ^[sS]$ ]]; then
                ldapdelete -x -H "ldap://$ldap_server" -D "cn=$admin_cn,dc=$domain_name,dc=$domain_ext" \
                -w "$admin_pass" "$user_dn"
                echo -e "\nUsuario '$entry_name' borrado exitosamente.\n"
            else
                echo -e "\nOperación cancelada.\n"
            fi
        else
            echo -e "\nEl usuario '$entry_name' no existe en el directorio.\n"
        fi
        ;;

        grupo)
        # Comprobar si el grupo existe
        group_dn=$(ldapsearch -x -H "ldap://$ldap_server" -D "cn=$admin_cn,dc=$domain_name,dc=$domain_ext" \
            -w "$admin_pass" -b "dc=$domain_name,dc=$domain_ext" "(cn=$entry_name)" | grep "^dn: " | awk '{print $2}')

        if [[ -n "$group_dn" ]]; then
            # Comprobar si el grupo tiene hijos
            child_count=$(ldapsearch -x -H "ldap://$ldap_server" -D "cn=$admin_cn,dc=$domain_name,dc=$domain_ext" \
                -w "$admin_pass" -b "$group_dn" "(objectClass=*)" | grep "^dn: " | wc -l)

            if (( child_count > 0 )); then
                echo -e "\n=== El grupo '$entry_name' tiene $child_count objeto(s) contenido(s): ==="
                ldapsearch -x -H "ldap://$ldap_server" -D "cn=$admin_cn,dc=$domain_name,dc=$domain_ext" \
                -w "$admin_pass" -b "$group_dn" "(objectClass=*)" dn | grep "^dn: " | sed 's/^dn: / • /'
                echo -e "===========================================\n"
            fi

            # Confirmar borrado
            read -p "¿Está seguro de que desea borrar el grupo '$entry_name'? (s/n): " confirm
            if [[ $confirm =~ ^[sS]$ ]]; then
                ldapdelete -x -H "ldap://$ldap_server" -D "cn=$admin_cn,dc=$domain_name,dc=$domain_ext" \
                -w "$admin_pass" "$group_dn"
                echo -e "\nGrupo '$entry_name' borrado exitosamente.\n"
            else
                echo -e "\nOperación cancelada.\n"
            fi
        else
            echo -e "\nEl grupo '$entry_name' no existe.\n"
        fi
        ;;

        OU)
                delete_reubicar

                ;;

                *)
echo -e "\nTipo de objeto no reconocido.\n"
;;
esac

if repeat_action; then
    delete_entry
fi

}

search_entry() {
    clear
    read -p "Ingrese el tipo de entrada a buscar (usuario, grupo, OU): " entry_type
    echo " "
    case "$entry_type" in
        usuario)
read -p "Ingrese el UID del usuario o presione Enter para buscar todos: " user_uid
echo " "
if [ -z "$user_uid" ]; then
    ldapsearch -x -H "ldap://$ldap_server" -D "cn=$admin_cn,dc=$domain_name,dc=$domain_ext" -w "$admin_pass" -b "dc=$domain_name,dc=$domain_ext" "(objectClass=inetOrgPerson)" |
    grep -E "(dn:|uid:|cn:|sn:|mail:|telephoneNumber:)" | \
    sed -e 's/^dn:/\n\tDN (Nombre Distinguido):/' \
    -e 's/^uid:/\tUID (Identificador de Usuario):/' \
    -e 's/^cn:/\tCN (Nombre Común):/' \
    -e 's/^sn:/\tSN (Apellido):/' \
    -e 's/^mail:/\tEmail:/' \
    -e 's/^telephoneNumber:/\tTeléfono:/'
    echo " "
else
    ldapsearch -x -H "ldap://$ldap_server" -D "cn=$admin_cn,dc=$domain_name,dc=$domain_ext" -w "$admin_pass" -b "dc=$domain_name,dc=$domain_ext" "(uid=$user_uid)" |
    grep -E "(dn:|uid:|cn:|sn:|mail:|telephoneNumber:)" | \
    sed -e 's/^dn:/\n\tDN (Nombre Distinguido):/' \
    -e 's/^uid:/\tUID (Identificador de Usuario):/' \
    -e 's/^cn:/\tCN (Nombre Común):/' \
    -e 's/^sn:/\tSN (Apellido):/' \
    -e 's/^mail:/\tEmail:/' \
    -e 's/^telephoneNumber:/\tTeléfono:/'
    echo " "
fi
;;

grupo)
read -p "Ingrese el nombre del grupo o presione Enter para buscar todos: " group_name
echo " "
if [ -z "$group_name" ]; then
    ldapsearch -x -H "ldap://$ldap_server" -D "cn=$admin_cn,dc=$domain_name,dc=$domain_ext" -w "$admin_pass" -b "dc=$domain_name,dc=$domain_ext" "(objectClass=posixGroup)" |
    grep -E "(dn:|cn:|gidNumber:)" | \
    sed -e 's/^dn:/\n\tDN (Nombre Distinguido):/' \
    -e 's/^cn:/\tCN (Nombre del Grupo):/' \
    -e 's/^gidNumber:/\tGID (Identificador de Grupo):/'
    echo " "
else
    ldapsearch -x -H "ldap://$ldap_server" -D "cn=$admin_cn,dc=$domain_name,dc=$domain_ext" -w "$admin_pass" -b "dc=$domain_name,dc=$domain_ext" "(cn=$group_name)" |
    grep -E "(dn:|cn:|gidNumber:)" | \
    sed -e 's/^dn:/\n\tDN (Nombre Distinguido):/' \
    -e 's/^cn:/\tCN (Nombre del Grupo):/' \
    -e 's/^gidNumber:/\tGID (Identificador de Grupo):/'
    echo " "
fi
;;

OU)
read -p "Ingrese el nombre de la unidad organizativa o presione Enter para buscar todas: " ou_name
echo " "
if [ -z "$ou_name" ]; then
    ldapsearch -x -H "ldap://$ldap_server" -D "cn=$admin_cn,dc=$domain_name,dc=$domain_ext" -w "$admin_pass" -b "dc=$domain_name,dc=$domain_ext" "(objectClass=organizationalUnit)" |
    grep -E "(dn:|ou:)" | \
    sed -e 's/^dn:/\n\tDN (Nombre Distinguido):/' \
    -e 's/^ou:/\tOU (Unidad Organizativa):/'
    echo " "
else
    ldapsearch -x -H "ldap://$ldap_server" -D "cn=$admin_cn,dc=$domain_name,dc=$domain_ext" -w "$admin_pass" -b "dc=$domain_name,dc=$domain_ext" "(ou=$ou_name)" |
    grep -E "(dn:|ou:)" | \
    sed -e 's/^dn:/\n\tDN (Nombre Distinguido):/' \
    -e 's/^ou:/\tOU (Unidad Organizativa):/'
    echo " "
fi
;;

*)
echo "Tipo de entrada no reconocido."
;;
esac

if repeat_action; then
    search_entry
fi
}

help_info() {
    clear
    echo "Ayuda para las opciones disponibles:"
    echo
    echo "1) Crear una entrada:"
    echo "   - Esta opción permite crear un nuevo usuario, grupo o unidad organizativa (OU) en el directorio LDAP."
    echo "   - Al crear un usuario, se puede especificar información detallada como nombre, apellido, dirección de correo electrónico, número de teléfono y otros atributos relevantes."
    echo "   - Los grupos y OUs también pueden ser creados, lo que facilita la organización de los usuarios dentro del directorio."

    echo
    echo "2) Modificar una entrada existente:"
    echo "   - Con esta opción, se pueden realizar cambios en la información de un usuario ya existente."
    echo "   - Los atributos que se pueden modificar incluyen el correo electrónico, número de teléfono y contraseña."
    echo "   - Además, es posible reubicar al usuario en diferentes OUs o moverlo al directorio raíz y viceversa."
    echo "   - Para grupos y OUs, solo se puede modificar la descripción, lo que ayuda a mantener la claridad en la estructura del directorio."

    echo
    echo "3) Eliminar una entrada:"
    echo "   - Esta opción permite eliminar usuarios, grupos o unidades organizativas (OUs) del directorio LDAP."
    echo "   - Al eliminar una entrada, se puede elegir reubicar objetos subordinados (hijos) a otra OU o grupo, o borrarlos completamente."
    echo "   - Se debe tener cuidado al eliminar OUs, ya que puede que contengan otros objetos que también deben ser gestionados."

    echo
    echo "4) Realizar una consulta:"
    echo "   - Con esta opción, se pueden realizar búsquedas en el servidor LDAP."
    echo "   - Las consultas pueden hacerse utilizando un filtro de nombre específico o mostrando todos los objetos en el directorio."
    echo "   - Se pueden ver detalles sobre usuarios, grupos y OUs, lo que permite obtener información útil y necesaria para la gestión del directorio."

    echo " "
    if repeat_action; then
        help_info
    fi

}

repeat_action() {
    read -p "¿Repetir acción? (s/n): " repeat_choice
    if [[ "$repeat_choice" == "s" || "$repeat_choice" == "S" ]]; then
        return 0 # Indica que se debe repetir la acción
    else
        return 1 # Indica que no se debe repetir
    fi
}

# Bucle principal del menú
while true; do
    menu
    case $option in
        1) create_entry ;;
2) modify_entry ;;
3) delete_entry ;;
4) search_entry;;
5) help_info;;
6) echo "Saliendo..."; exit 0 ;;
*) echo "Opción no válida." ;;
esac
done