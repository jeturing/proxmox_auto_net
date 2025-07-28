¡Claro! Aquí tienes el `README.md` profesional **en un solo bloque**, listo para copiar y pegar directamente en tu repositorio [`proxmox_auto_net`](https://github.com/jeturing/proxmox_auto_net).

---

### 📄 Contenido completo para `README.md`

````markdown
<h1 align="center">🔧 Proxmox Auto Network</h1>
<p align="center">
  Automatización inteligente de red para <strong>Proxmox VE</strong> con IP estática/dinámica, DHCP, NAT y persistencia.
</p>

<p align="center">
  <a href="https://jeturing.com" target="_blank"><strong>Desarrollado por Jeturing Inc.</strong></a>
  •
  <a href="#️-características">Características</a>
  •
  <a href="#-instalación">Instalación</a>
  •
  <a href="#-uso">Uso</a>
  •
  <a href="#-licencia">Licencia</a>
</p>

---

## 🚀 ¿Qué es?

`proxmox_auto_net.sh` es un script todo-en-uno para configurar la red de forma automática en hosts Proxmox VE. Proporciona:

- Configuración de servidor DHCP con `dnsmasq`
- NAT para salida a internet de las VMs/CTs
- Asignación automática de IPs estáticas disponibles
- Registro persistente de las asignaciones
- Servicio `systemd` para aplicar todo tras reinicio

---

## ⚙️ Requisitos

- ✅ Proxmox VE 7.x u 8.x
- ✅ Red `vmbr0` configurada en el host
- ✅ Interfaz de salida a internet (`eth0`)
- ✅ Acceso como `root`
- ✅ `pct` y `qm` disponibles

---

## 🧩 Instalación

### 1. Clona el repositorio

```bash
git clone https://github.com/jeturing/proxmox_auto_net.git
cd proxmox_auto_net
````

### 2. Instala el script

```bash
sudo cp proxmox_auto_net.sh /usr/local/bin/proxmox_auto_net.sh
sudo chmod +x /usr/local/bin/proxmox_auto_net.sh
```

---

## ✨ Características

| Funcionalidad                | Descripción                                                      |
| ---------------------------- | ---------------------------------------------------------------- |
| 🎛️ DHCP automático          | Configura `dnsmasq` para servir IPs en el rango `10.0.0.100–150` |
| 🌐 NAT                       | Aplica `iptables` MASQUERADE para salida a internet              |
| 📦 IPs estáticas automáticas | Rango reservado `10.0.0.2–99` para asignación a CTs y VMs        |
| 📒 Registro persistente      | Guarda asignaciones en `/var/log/proxmox_ip_assignments.log`     |
| 🧠 Detección inteligente     | Detecta si es CT o VM y evita duplicar configuraciones           |
| 🔁 Arranque automático       | Instala `systemd` service para persistencia tras reinicio        |

---

## 🧪 Uso

### Inicializar red (primera vez)

```bash
sudo /usr/local/bin/proxmox_auto_net.sh
```

> Instala `dnsmasq`, configura NAT, crea el servicio y aplica todo.

---

### Asignar IP automáticamente a una CT o VM

```bash
sudo /usr/local/bin/proxmox_auto_net.sh <ID>
# Ejemplo:
sudo /usr/local/bin/proxmox_auto_net.sh 101
```

* Detecta si es LXC o KVM
* Busca IP libre en `10.0.0.2–99`
* Evita IPs ocupadas o ya asignadas
* Reinicia la VM o CT tras configurar

---

## 📁 Ejemplo de log

Ruta: `/var/log/proxmox_ip_assignments.log`

```
2025-07-28 21:08:41 TYPE=ct ID=101 NAME=bk IP=10.0.0.2
2025-07-28 21:12:17 TYPE=vm ID=200 NAME=VM_200 IP=10.0.0.3
```

---

## 🛡️ Seguridad y validaciones

* ✅ Verifica si la IP responde a `ping`
* ✅ No reconfigura si `net0` ya está definido
* ✅ No sobrescribe configuraciones de red existentes
* ✅ Solo escribe reglas de NAT o DHCP si no existen

---

## 🖥️ Servicio `systemd`

El script crea:

```
/etc/systemd/system/proxmox-auto-net.service
```

Este servicio:

* Se habilita automáticamente (`WantedBy=multi-user.target`)
* Ejecuta el script en cada reinicio del nodo
* Garantiza que DHCP y NAT estén siempre activos

---

## 📖 Licencia

MIT License © 2025 [Jeturing Inc.](https://jeturing.com)

---

## 🤝 Contribuciones

¿Tienes sugerencias, mejoras o ideas?
¡Pull requests y forks son bienvenidos!

---

<p align="center"><strong>Desarrollado con ❤️ por Jeturing – Innovación Tecnológica para Empresas</strong></p>
```
 
 
