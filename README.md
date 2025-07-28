# 🔧 Proxmox Auto Network

Automatización de red en Proxmox VE para contenedores (LXC) y máquinas virtuales (KVM/QEMU), con asignación de IP estática o dinámica, NAT y registro de red persistente.

## 🚀 Características

- ✅ Instalación y configuración automática de `dnsmasq` como servidor DHCP para `vmbr0`.
- ✅ Aplicación de reglas de `iptables` (NAT/MASQUERADE) para salida a internet.
- ✅ Asignación automática de IPs estáticas a CTs y VMs desde un rango (`10.0.0.2` a `10.0.0.99`).
- ✅ Detección de conflictos de IPs (usadas o registradas).
- ✅ Registro persistente de asignaciones en `/var/log/proxmox_ip_assignments.log`.
- ✅ Servicio `systemd` (`proxmox-auto-net.service`) habilitado en el arranque del host.
- ✅ Evita duplicación de configuraciones ya aplicadas.

---

## 📦 Requisitos

- Proxmox VE 7.x o 8.x (probado en 6.8.12-13-pve)
- Shell con permisos de root
- Acceso a contenedores LXC (`pct`) y/o VMs (`qm`)
- Red puenteada (`vmbr0`) ya configurada

---

## ⚙️ Instalación

### 1. Copia el script

```bash
sudo curl -o /usr/local/bin/proxmox_auto_net.sh https://raw.githubusercontent.com/<usuario>/<repo>/main/proxmox_auto_net.sh
sudo chmod +x /usr/local/bin/proxmox_auto_net.sh
