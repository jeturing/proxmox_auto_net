#!/bin/bash

# CONFIGURACIÓN GENERAL
BRIDGE="vmbr0"
GATEWAY="10.0.0.1"
NETPREFIX="10.0.0"
STATIC_START=2
STATIC_END=99
DHCP_START=100
DHCP_END=150
DNS="1.1.1.1"
LOG_FILE="/var/log/proxmox_ip_assignments.log"
DNSMASQ_CONF="/etc/dnsmasq.d/$BRIDGE.conf"
SERVICE_NAME="proxmox-auto-net"

ID="$1"

[[ $EUID -ne 0 ]] && echo "[X] Ejecuta como root." && exit 1

echo "[+] Inicializando entorno de red Proxmox..."
# AUTOACTUALIZACIÓN DESDE GITHUB
REPO_RAW="https://raw.githubusercontent.com/jeturing/proxmox_auto_net/main/proxmox_auto_net.sh"
LOCAL_SCRIPT="/usr/local/bin/proxmox_auto_net.sh"
TMP_SCRIPT="/tmp/proxmox_auto_net_latest.sh"

echo "[~] Verificando actualizaciones del script en GitHub..."

if curl --output /dev/null --silent --head --fail "$REPO_RAW"; then
  curl -s -o "$TMP_SCRIPT" "$REPO_RAW"
  chmod +x "$TMP_SCRIPT"
  
  LOCAL_HASH=$(sha256sum "$LOCAL_SCRIPT" | cut -d ' ' -f1)
  REMOTE_HASH=$(sha256sum "$TMP_SCRIPT" | cut -d ' ' -f1)

  if [[ "$LOCAL_HASH" != "$REMOTE_HASH" ]]; then
    echo "[↑] Se detectó una nueva versión. Actualizando script..."
    cp "$TMP_SCRIPT" "$LOCAL_SCRIPT"
    chmod +x "$LOCAL_SCRIPT"
    echo "[✔] Script actualizado. Reiniciando ejecución..."
    exec "$LOCAL_SCRIPT" "$@"
  else
    echo "[✓] El script ya está actualizado."
  fi
else
  echo "[!] No se pudo verificar actualizaciones (sin acceso a GitHub o conexión limitada)."
fi

# 1. Instalar dnsmasq si falta
# Validar resolución DNS antes de instalar paquetes
if ! getent hosts deb.debian.org &>/dev/null; then
  echo "[!] El sistema no puede resolver dominios DNS (ej. deb.debian.org)"
  echo "[+] Agregando temporalmente nameserver 1.1.1.1 a /etc/resolv.conf..."
  echo "nameserver 1.1.1.1" > /etc/resolv.conf
  sleep 2
  if ! getent hosts deb.debian.org &>/dev/null; then
    echo "[X] Aún no hay resolución DNS. Aborta instalación de dnsmasq."
    echo "    Verifica tu conectividad antes de continuar."
    exit 1
  fi
fi

# Instalar dnsmasq si no está
if ! command -v dnsmasq &>/dev/null; then
  echo "[+] Instalando dnsmasq..."
  apt update && apt install -y dnsmasq
else
  echo "[✓] dnsmasq ya instalado."
fi


# 2. Configurar dnsmasq para vmbr0 si no está
if [[ ! -f "$DNSMASQ_CONF" ]] || ! grep -q "$BRIDGE" "$DNSMASQ_CONF"; then
  echo "[+] Configurando DHCP para $BRIDGE..."
  cat <<EOF > "$DNSMASQ_CONF"
interface=$BRIDGE
bind-interfaces
dhcp-range=$NETPREFIX.$DHCP_START,$NETPREFIX.$DHCP_END,255.255.255.0,12h
dhcp-option=option:router,$GATEWAY
dhcp-option=option:dns-server,$DNS
EOF
  systemctl restart dnsmasq
  echo "[✓] DHCP habilitado en $BRIDGE"
else
  echo "[✓] DHCP ya configurado para $BRIDGE"
fi

# 3. Agregar NAT si no existe
if iptables -t nat -C POSTROUTING -s "$NETPREFIX.0/24" -o eth0 -j MASQUERADE 2>/dev/null; then
  echo "[✓] NAT ya configurado para $NETPREFIX.0/24"
else
  iptables -t nat -A POSTROUTING -s "$NETPREFIX.0/24" -o eth0 -j MASQUERADE
  echo "[+] NAT agregado para salida a internet"
fi

# 4. Crear systemd service si no existe
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME.service"
if [[ ! -f "$SERVICE_PATH" ]]; then
  echo "[+] Instalando servicio systemd para ejecución automática..."

  cat <<EOF > "$SERVICE_PATH"
[Unit]
Description=Proxmox Auto Network Bootstrap
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/proxmox_auto_net.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  echo "[✓] Servicio $SERVICE_NAME instalado y habilitado al inicio."
else
  echo "[✓] Servicio $SERVICE_NAME ya está presente."
fi

# FUNCIONALIDAD: Asignación automática de IP
assign_static_ip() {
  local ID="$1"
  local TYPE SET_CMD START_CMD GET_HOSTNAME

  if [[ -z "$ID" ]]; then
    echo "Uso: $0 <CT_ID o VM_ID>"
    return 1
  fi

  if pct status "$ID" &>/dev/null; then
    TYPE="ct"
    SET_CMD="pct set"
    START_CMD="pct restart $ID"
    GET_HOSTNAME="pct exec $ID -- hostname"
  elif qm status "$ID" &>/dev/null; then
    TYPE="vm"
    SET_CMD="qm set"
    START_CMD="qm reset $ID"
    GET_HOSTNAME="echo VM_$ID"
  else
    echo "[X] ID $ID no válido"
    return 1
  fi

  echo "[+] Buscando IP libre para $TYPE $ID..."

  for i in $(seq $STATIC_START $STATIC_END); do
    IP="$NETPREFIX.$i"

    grep -q "$IP" "$LOG_FILE" 2>/dev/null && continue
    ping -c1 -W1 "$IP" &>/dev/null && continue

    # Verificar si ya tiene red configurada
    if [[ "$TYPE" == "ct" && $(pct config "$ID" | grep -c net0:) -gt 0 ]]; then
      echo "[!] $TYPE $ID ya tiene red asignada. Saltando."
      return
    fi

    if [[ "$TYPE" == "vm" && $(qm config "$ID" | grep -c net0:) -gt 0 ]]; then
      echo "[!] $TYPE $ID ya tiene red asignada. Saltando."
      return
    fi

    # Asignar
    if [[ "$TYPE" == "ct" ]]; then
      $SET_CMD "$ID" -net0 name=eth0,bridge=$BRIDGE,ip="$IP/24",gw=$GATEWAY
    else
      $SET_CMD "$ID" -net0 model=virtio,bridge=$BRIDGE
      echo "[!] Asigna IP $IP manualmente dentro del sistema operativo de la VM."
    fi

    eval "$START_CMD"
    sleep 5

    HOSTNAME=$(eval "$GET_HOSTNAME")
    echo "$(date '+%Y-%m-%d %H:%M:%S') TYPE=$TYPE ID=$ID NAME=$HOSTNAME IP=$IP" >> "$LOG_FILE"
    echo "[✔] IP $IP asignada a $TYPE $ID ($HOSTNAME)"
    return
  done

  echo "[X] Sin IPs libres disponibles en $NETPREFIX.$STATIC_START-$STATIC_END"
}

# Ejecutar asignación si se pasa un ID
[[ -n "$ID" ]] && assign_static_ip "$ID"
