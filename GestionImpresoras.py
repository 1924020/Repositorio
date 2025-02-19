import os
import platform
import tkinter as tk
from tkinter import filedialog, simpledialog, messagebox

# Verifica el sistema operativo para importar las bibliotecas adecuadas
if platform.system() == "Windows":
    import win32print
    import win32api
elif platform.system() in ["Linux", "Darwin"]:  # Linux/macOS
    import cups

class PrintManager:
    def __init__(self):
        """Inicializa el gestor de impresión detectando el sistema operativo."""
        self.system = platform.system()
        if self.system == "Windows":
            self.conn = None
            self.printers = [printer[2] for printer in win32print.EnumPrinters(2)]
            self.default_printer = win32print.GetDefaultPrinter()
        elif self.system in ["Linux", "Darwin"]:
            self.conn = cups.Connection()
            self.printers = list(self.conn.getPrinters().keys())
            self.default_printer = self.conn.getDefault()
        else:
            raise Exception("Sistema operativo no compatible")

    def listar_impresoras(self):
        """Retorna la lista de impresoras disponibles."""
        return self.printers

    def imprimir_archivo(self, archivo, impresora):
        """Envía un archivo a imprimir."""
        if not archivo or not os.path.exists(archivo):
            messagebox.showerror("Error", "El archivo seleccionado no es válido.")
            return

        if impresora not in self.printers:
            messagebox.showerror("Error", "Seleccione una impresora válida.")
            return

        try:
            if self.system == "Windows":
                win32print.SetDefaultPrinter(impresora)
                win32api.ShellExecute(0, "print", archivo, None, ".", 0)
            else:
                self.conn.printFile(impresora, archivo, "Trabajo de impresión", {})
            messagebox.showinfo("Éxito", f"Archivo enviado a imprimir en {impresora}")
        except Exception as e:
            messagebox.showerror("Error", f"No se pudo imprimir: {e}")

    def obtener_trabajos(self):
        """Retorna la lista de trabajos en cola (solo Linux/macOS)."""
        if self.system == "Windows":
            return ["Función no disponible en Windows."]

        jobs = self.conn.getJobs()
        if not jobs:
            return ["No hay trabajos en la cola."]

        trabajos = []
        for job_id, job in jobs.items():
            estado = job.get('job-state', 'Desconocido')
            documento = job.get('document-name', 'Sin nombre')
            trabajos.append(f"ID: {job_id}, Estado: {estado}, Documento: {documento}")

        return trabajos

    def cancelar_trabajo(self, job_id=None):
        """Cancela un trabajo de impresión por su ID o toda la cola."""
        if self.system == "Windows":
            messagebox.showwarning("No Disponible", "No es posible cancelar trabajos en Windows desde Python.")
            return

        if job_id is None:
            messagebox.showerror("Error", "Debe proporcionar un ID de trabajo válido.")
            return

        try:
            self.conn.cancelJob(int(job_id))
            messagebox.showinfo("Éxito", f"Trabajo {job_id} cancelado correctamente.")
        except Exception as e:
            messagebox.showerror("Error", f"No se pudo cancelar el trabajo: {e}")

class PrintGUI:
    def __init__(self, root):
        """Inicializa la interfaz gráfica."""
        self.gestor = PrintManager()
        self.root = root
        self.root.title("Gestión de Impresión")
        self.root.geometry("500x400")

        # Lista de impresoras
        tk.Label(root, text="Selecciona una impresora:").pack()
        self.impresora_var = tk.StringVar(value=self.gestor.default_printer)
        self.impresoras_menu = tk.OptionMenu(root, self.impresora_var, self.impresora_var.get(),
                                             *self.gestor.listar_impresoras())
        self.impresoras_menu.pack(pady=5)

        # Botón para seleccionar archivo
        tk.Button(root, text="Seleccionar archivo", command=self.seleccionar_archivo).pack(pady=5)

        # Botón para imprimir
        tk.Button(root, text="Imprimir", command=self.imprimir).pack(pady=5)

        # Botón para mostrar trabajos
        tk.Button(root, text="Mostrar trabajos en cola", command=self.mostrar_trabajos).pack(pady=5)

        # Botón para cancelar un trabajo
        tk.Button(root, text="Cancelar trabajo", command=self.cancelar_trabajo).pack(pady=5)

        # Área de texto para mostrar trabajos
        self.texto_trabajos = tk.Text(root, height=10, width=50)
        self.texto_trabajos.pack(pady=5)

        self.archivo_seleccionado = None

    def seleccionar_archivo(self):
        """Permite seleccionar un archivo a imprimir."""
        archivo = filedialog.askopenfilename(title="Seleccionar archivo para imprimir")
        if archivo:
            self.archivo_seleccionado = archivo
            messagebox.showinfo("Archivo seleccionado", f"Archivo: {archivo}")

    def imprimir(self):
        """Envía un archivo a la impresora seleccionada."""
        if not self.archivo_seleccionado:
            messagebox.showerror("Error", "Seleccione un archivo primero.")
            return
        impresora = self.impresora_var.get()
        self.gestor.imprimir_archivo(self.archivo_seleccionado, impresora)

    def mostrar_trabajos(self):
        """Muestra los trabajos en la cola de impresión."""
        trabajos = self.gestor.obtener_trabajos()
        self.texto_trabajos.delete("1.0", tk.END)
        if trabajos:
            self.texto_trabajos.insert(tk.END, "\n".join(trabajos))
        else:
            self.texto_trabajos.insert(tk.END, "No hay trabajos en cola.")

    def cancelar_trabajo(self):
        """Permite cancelar un trabajo específico o vaciar toda la cola de impresión."""
        if self.gestor.system == "Windows":
            messagebox.showwarning("No Disponible", "No es posible cancelar trabajos en Windows desde Python.")
            return

        opcion = simpledialog.askstring("Cancelar Trabajo", "¿Quieres borrar un trabajo específico (ID) o TODOS?\n"
                                                            "Escribe 'ID' para uno solo o 'TODOS' para vaciar la cola:")

        if opcion is None:
            return

        if opcion.lower() == "todos":
            self.borrar_toda_cola()
        elif opcion.lower() == "id":
            job_id = simpledialog.askstring("Cancelar Trabajo", "Ingrese el ID del trabajo a cancelar:")
            if job_id:
                self.gestor.cancelar_trabajo(job_id)
        else:
            messagebox.showerror("Error", "Opción no válida. Escribe 'ID' o 'TODOS'.")

    def borrar_toda_cola(self):
        """Cancela todos los trabajos en la cola de impresión."""
        if self.gestor.system == "Windows":
            messagebox.showwarning("No Disponible", "No es posible cancelar trabajos en Windows desde Python.")
            return

        try:
            jobs = self.gestor.conn.getJobs()
            if not jobs:
                messagebox.showinfo("Cola Vacía", "No hay trabajos en la cola de impresión.")
                return

            for job_id in jobs.keys():
                self.gestor.conn.cancelJob(job_id)
            messagebox.showinfo("Éxito", "Todos los trabajos han sido cancelados.")
        except Exception as e:
            messagebox.showerror("Error", f"No se pudo borrar la cola: {e}")

# Ejecutar la interfaz gráfica
if __name__ == "__main__":
    root = tk.Tk()
    app = PrintGUI(root)
    root.mainloop()