#!/bin/bash
# Mensaje de bienvenida
echo "============================================================"
echo "      Bienvenido al gestor de su dominio OpenLDAP"
echo "============================================================"
echo "Este script le permitirá insertar, modificar y eliminar objetos en OpenLDAP-"
echo " "
sleep 2

echo "Proporcione los siguientes parámetros para poder acceder al dominio:"
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
    exit 1
else
    echo "Conexión exitosa al servidor LDAP."
fi

# Función para mostrar el menú principal
menu() {
    echo "============================================================"
    echo "            Gestor de su dominio OpenLDAP"
    echo "============================================================"
    echo " "
    echo "Menú de opciones:"
    echo "1) Crear una entrada (usuario, grupo, OU)"
    echo "2) Modificar una entrada existente"
    echo "3) Eliminar una entrada"
    echo "4) Ayuda"
    echo "5) Salir"
    echo " "
    read -p "Seleccione una opción: " option
}

# Función para crear una entrada
create_entry() { 
    read -p "¿Tienes un archivo .ldif con los datos? (s/n): " has_ldif
    echo " "
    if [[ "$has_ldif" == "s" ]]; then
        read -p "Ingrese la ruta del archivo .ldif: " ldif_file
        
        # Verificar si el archivo existe
        if [ -f "$ldif_file" ]; then
            # Intentar agregar la entrada desde el archivo .ldif
            ldapadd -x -H "ldap://$ldap_server" -D "cn=$admin_cn,dc=$domain_name,dc=$domain_ext" -w "$admin_pass" -f "$ldif_file" >/dev/null 2>&1
            
            # Comprobar el resultado del comando ldapadd
            if [ $? -eq 0 ]; then
                echo "Entrada creada exitosamente desde el archivo $ldif_file."
                echo " "
            else
                # Imprimir un mensaje de error más detallado
                echo "Error al crear la entrada desde el archivo $ldif_file. Revisa el formato del archivo."
                echo "Recuerda que el archivo debe estar en formato LDIF correcto."
                echo " "
            fi
        else
            echo "El archivo especificado no existe. Por favor, verifica la ruta e intenta nuevamente."
            echo " "
        fi

    else
        read -p "Ingrese el DN de la nueva entrada (ejemplo: uid=usuario,dc=$domain_name,dc=$domain_ext): " dn

        # Verificar que el DN no esté vacío
        if [[ -z "$dn" ]]; then
            echo "Error: El DN no puede estar vacío."
            return
        fi

        read -p "Ingrese el tipo de objeto (usuario, grupo, OU): " entry_type
        case $entry_type in
            usuario)
                read -p "Nombre común (cn): " cn
                read -p "Apellido (sn): " sn
                read -sp "Contraseña: " user_pass
                echo
                # Crear archivo LDIF para usuario
                {
                    echo "dn: $dn"
                    echo "objectClass: inetOrgPerson"
                    echo "cn: $cn"
                    echo "sn: $sn"
                    echo "userPassword: $(slappasswd -s "$user_pass")"
                } > temp.ldif
                ;;
            grupo)
                read -p "Nombre del grupo (cn): " cn
                # Crear archivo LDIF para grupo
                {
                    echo "dn: $dn"
                    echo "objectClass: groupOfNames"
                    echo "cn: $cn"
                    echo "member: $dn"
                } > temp.ldif
                ;;
            OU)
                read -p "Nombre de la unidad organizativa (ou): " ou
                # Crear archivo LDIF para unidad organizativa
                {
                    echo "dn: $dn"
                    echo "objectClass: organizationalUnit"
                    echo "ou: $ou"
                } > temp.ldif
                ;;
            *)
                echo "Tipo de objeto no válido."
                return
                ;;
        esac

        # Verificar y agregar la entrada
        ldapadd -x -H "ldap://$ldap_server" -D "cn=$admin_cn,dc=$domain_name,dc=$domain_ext" -w "$admin_pass" -f temp.ldif >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "Entrada creada exitosamente."
            echo " "
        else
            echo "Error al crear la entrada. Verifique el formato LDIF."
            echo " "
        fi
        rm -f temp.ldif
    fi
}

# Función para modificar una entrada
modify_entry() {
    read -p "¿Tienes un archivo .ldif con los cambios? (s/n): " has_ldif
    echo " "
    if [[ "$has_ldif" == "s" ]]; then
        read -p "Ingrese la ruta del archivo .ldif: " ldif_file
        ldapmodify -x -H "ldap://$ldap_server" -D "cn=$admin_cn,dc=$domain_name,dc=$domain_ext" -w "$admin_pass" -f "$ldif_file" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "Entrada modificada exitosamente desde el archivo $ldif_file."
            echo " "
        else
            echo "Error al modificar la entrada desde el archivo $ldif_file."
            echo " "
        fi
    else
        read -p "Ingrese el DN de la entrada a modificar (ejemplo: uid=usuario,dc=$domain_name,dc=$domain_ext): " dn
        if [[ -z "$dn" ]]; then
            echo "Error: El DN no puede estar vacío."
            return
        fi

        read -p "Ingrese el atributo a modificar (ejemplo: sn): " attribute
        read -p "Ingrese el nuevo valor para $attribute: " value

        # Crear contenido LDIF de modificación
        {
            echo "dn: $dn"
            echo "changetype: modify"
            echo "replace: $attribute"
            echo "$attribute: $value"
        } > temp.ldif

        ldapmodify -x -H "ldap://$ldap_server" -D "cn=$admin_cn,dc=$domain_name,dc=$domain_ext" -w "$admin_pass" -f temp.ldif >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "Entrada modificada exitosamente."
            echo " "
        else
            echo "Error al modificar la entrada."
            echo " "
        fi
        rm -f temp.ldif
    fi
}

# Función para eliminar una entrada
delete_entry() {
    read -p "Ingrese el DN de la entrada a eliminar (ejemplo: uid=usuario,dc=$domain_name,dc=$domain_ext): " dn
    if [[ -z "$dn" ]]; then
        echo "Error: El DN no puede estar vacío."
        return
    fi

    ldapdelete -x -H "ldap://$ldap_server" -D "cn=$admin_cn,dc=$domain_name,dc=$domain_ext" -w "$admin_pass" "$dn" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "Entrada eliminada exitosamente."
        echo " "
    else
        echo "Error al eliminar la entrada."
        echo " "
    fi
}

# Función para mostrar información de ayuda
help_info() {
    echo "Ayuda sobre OpenLDAP:"
    echo ""
    echo "Este script permite realizar operaciones de inserción, modificación y eliminación"
    echo "de entradas en un directorio OpenLDAP."
    echo ""
    echo "Atributos Comunes para Usuarios:"
    echo "--------------------------------"
    echo "1. Atributos Básicos:"
    echo "   - cn: Nombre común (Common Name)."
    echo "   - sn: Apellido (Surname)."
    echo "   - uid: Identificador de usuario (User ID)."
    echo "   - userPassword: Contraseña del usuario."
    echo ""
    echo "2. Atributos de Contacto:"
    echo "   - mail: Dirección de correo electrónico."
    echo "   - telephoneNumber: Número de teléfono."
    echo "   - mobile: Número de teléfono móvil."
    echo "   - postalAddress: Dirección postal."
    echo ""
    echo "3. Atributos Adicionales:"
    echo "   - description: Descripción del usuario."
    echo "   - homeDirectory: Directorio home del usuario."
    echo "   - gidNumber: ID de grupo."
    echo "   - uidNumber: ID de usuario."
    echo ""
    echo "Atributos Comunes para Unidades Organizativas:"
    echo "----------------------------------------------"
    echo "1. Atributos Básicos:"
    echo "   - ou: Nombre de la unidad organizativa."
    echo "   - description: Descripción de la unidad organizativa."
    echo ""
    echo "Atributos que se pueden modificar:"
    echo "------------------------------------"
    echo "Para usuarios: La mayoría de los atributos mencionados son modificables."
    echo "Para unidades organizativas: Puedes modificar 'ou' y 'description'."
    echo ""
}

# Bucle principal del menú
while true; do
    menu
    case $option in
        1) create_entry ;;
        2) modify_entry ;;
        3) delete_entry ;;
        4) help_info ;;
        5) echo "Saliendo..."; exit 0 ;;
        *) echo "Opción no válida." ;;
    esac
done