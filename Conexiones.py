import tkinter as tk
from tkinter import ttk, messagebox
import json
import subprocess
import threading
import os

CONFIG_FILE = "config.json"

# Cargar configuraciones previas
def cargar_configuracion():
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, "r") as file:
            return json.load(file)
    return {}

# Guardar configuraciones
def guardar_configuracion():
    config = {
        "host": entry_host.get(),
        "usuario": entry_usuario.get(),
        "puerto": entry_puerto.get(),
        "clave_ssh": entry_clave.get(),
        "usar_clave": clave_var.get(),
        "usar_credenciales_rdp": credenciales_var.get(),
        "pantalla_completa": pantalla_completa_var.get(),
    }
    with open(CONFIG_FILE, "w") as file:
        json.dump(config, file)

# Conectar a RDP
def conectar_rdp():
    host = entry_host.get()
    if not host:
        messagebox.showerror("Error", "Por favor, ingresa la IP o el nombre del host.")
        return

    comando = f"mstsc /v:{host}"
    if pantalla_completa_var.get():
        comando += " /f"

    guardar_configuracion()
    threading.Thread(target=lambda: subprocess.run(comando, shell=True)).start()
    messagebox.showinfo("Conexión", f"Conectando a {host} vía RDP...")

# Conectar a SSH
def conectar_ssh():
    host = entry_host.get()
    usuario = entry_usuario.get()
    puerto = entry_puerto.get()
    if not host or not usuario:
        messagebox.showerror("Error", "Debes ingresar la IP y el usuario.")
        return

    comando = f"ssh -p {puerto} {usuario}@{host}"

    if clave_var.get():
        clave_ssh = entry_clave.get()
        if not clave_ssh:
            messagebox.showerror("Error", "Debes especificar la ruta de la clave SSH.")
            return
        comando = f"ssh -p {puerto} -i {clave_ssh} {usuario}@{host}"
    else:
        contrasena = entry_contrasena.get()
        if not contrasena:
            messagebox.showerror("Error", "Debes ingresar la contraseña.")
            return

    guardar_configuracion()
    threading.Thread(target=lambda: subprocess.run(comando, shell=True)).start()
    messagebox.showinfo("Conexión", f"Conectando a {host} vía SSH...")

# Crear ventana
ventana = tk.Tk()
ventana.title("Gestor de Conexiones Remotas")
ventana.geometry("450x400")
ventana.resizable(False, False)

# Cargar configuraciones previas
config = cargar_configuracion()

# Tema visual
style = ttk.Style()
style.theme_use("clam")

# Título
ttk.Label(ventana, text="Seleccione el tipo de conexión:", font=("Arial", 12)).pack(pady=5)

# Selección del tipo de conexión
tipo_conexion = tk.StringVar(value="RDP")

frame_conexion = ttk.Frame(ventana)
frame_conexion.pack(pady=5)

ttk.Radiobutton(frame_conexion, text="Windows (RDP)", variable=tipo_conexion, value="RDP").pack(side=tk.LEFT, padx=10)
ttk.Radiobutton(frame_conexion, text="Ubuntu (SSH)", variable=tipo_conexion, value="SSH").pack(side=tk.LEFT, padx=10)

# Campos de entrada
ttk.Label(ventana, text="Dirección IP / Host:").pack()
entry_host = ttk.Entry(ventana, width=35)
entry_host.pack()
entry_host.insert(0, config.get("host", ""))

ttk.Label(ventana, text="Usuario (Solo SSH):").pack()
entry_usuario = ttk.Entry(ventana, width=35)
entry_usuario.pack()
entry_usuario.insert(0, config.get("usuario", ""))

ttk.Label(ventana, text="Puerto SSH (Por defecto 22):").pack()
entry_puerto = ttk.Entry(ventana, width=10)
entry_puerto.pack()
entry_puerto.insert(0, config.get("puerto", "22"))

# Contraseña o Clave SSH
clave_var = tk.BooleanVar(value=config.get("usar_clave", False))
frame_credenciales = ttk.Frame(ventana)
frame_credenciales.pack()

ttk.Checkbutton(frame_credenciales, text="Usar clave SSH", variable=clave_var).pack(side=tk.LEFT)
entry_clave = ttk.Entry(frame_credenciales, width=25)
entry_clave.pack(side=tk.LEFT)
entry_clave.insert(0, config.get("clave_ssh", ""))

ttk.Label(ventana, text="Contraseña (Solo SSH sin clave):").pack()
entry_contrasena = ttk.Entry(ventana, show="*", width=35)
entry_contrasena.pack()

# Opción de credenciales guardadas en RDP
credenciales_var = tk.BooleanVar(value=config.get("usar_credenciales_rdp", True))
ttk.Checkbutton(ventana, text="Usar credenciales guardadas (Solo RDP)", variable=credenciales_var).pack()

# Opción de pantalla completa en RDP
pantalla_completa_var = tk.BooleanVar(value=config.get("pantalla_completa", False))
ttk.Checkbutton(ventana, text="Abrir RDP en pantalla completa", variable=pantalla_completa_var).pack()

# Botón de conexión
btn_conectar = ttk.Button(
    ventana, text="Conectar",
    command=lambda: conectar_rdp() if tipo_conexion.get() == "RDP" else conectar_ssh()
)
btn_conectar.pack(pady=10)

# Iniciar la interfaz
ventana.mainloop()