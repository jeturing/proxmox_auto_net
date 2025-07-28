#!/bin/bash

# ===============================================
# Proxmox Auto Net - Jeturing Inc.
# SCRIPT_VERSION: v1.0.0
# ===============================================

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
LOCAL_SCRIPT="/usr/local/bin/proxmox_auto_net.sh"
REPO_RAW="https://raw.githubusercontent.com/jeturing/proxmox_auto_net/main/proxmox_auto_net.sh"
TMP_SCRIPT="/tmp/proxmox_auto_net_latest.sh"

ID="$1"

# VALIDAR PERMISOS
[[ $EUID -ne 0 ]] && echo "[X] Ejecuta como root." && exit 1

# ===============================================
# AUTOACTUALIZACIÓN DESDE GITHUB
# ===============================================
echo "[~] Verificando versión del script..."
if curl -s --output /dev/null --head --fail "$REPO_RAW"; then
  curl -s -o "$TMP_SCRIPT" "$REPO_RAW" && chmod +x "$TMP_SCRIPT"
  LOCAL_VERSION=$(grep -E "^# SCRIPT_VERSION:" "$LOCAL_SCRIPT" | cut -d ':' -f2 | xargs)
  REMOTE_VERSION=$(grep -E "^# SCRIPT_VERSION:" "$TMP_SCRIPT" | cut -d ':' -f2 | xargs)
  if [[ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]]; then
    echo "[↑] Nueva versión disponible: $REMOTE_VERSION (actual: $LOCAL_VERSION)"
    cp "$TMP_SCRIPT" "$LOCAL_SCRIPT" && chmod +x "$LOCAL_SCRIPT"
    echo "[✔] Script actualizado. Reiniciando ejecución..."
    exec "$LOCAL_SCRIPT" "$@"
  else
    echo "[✓] El script está actualizado ($LOCAL_VERSION)"
  fi
else
  echo "[!] No se pudo verificar actualizaciones (GitHub inaccesible)."
fi

echo "[+] Inicializando entorno de red Proxmox..."

# ===============================================
# VALIDAR DNS PARA INSTALACIÓN
# ===============================================
if ! getent hosts deb.debian.org &>/dev/null; then
  echo "[!] DNS no resuelve, aplicando nameserver temporal..."
  echo "nameserver $DNS" > /etc/resolv.conf
  sleep 2
  if ! getent hosts deb.debian.org &>/dev/null; then
    echo "[X] Sin resolución DNS. Abortando."
    exit 1
  fi
fi

# ===============================================
# INSTALAR DNSMASQ SI NO EXISTE
# ===============================================
if ! command -v dnsmasq &>/dev/null; then
  echo "[+] Instalando dnsmasq..."
  apt update && apt install -y dnsmasq
else
  echo "[✓] dnsmasq ya instalado."
fi

# ===============================================
# CONFIGURAR DHCP PARA VMBR0
# ===============================================
if [[ ! -f "$DNSMASQ_CONF" ]] || ! grep -q "$BRIDGE" "$DNSMASQ_CONF" ]]; then
  echo "[+] Configurando DHCP en $BRIDGE..."
  mkdir -p /etc/dnsmasq.d
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
  echo "[✓] DHCP ya configurado en $BRIDGE"
fi

# ===============================================
# CONFIGURAR NAT SI NO EXISTE
# ===============================================
if iptables -t nat -C POSTROUTING -s "$NETPREFIX.0/24" -o eth0 -j MASQUERADE 2>/dev/null; then
  echo "[✓] NAT ya configurado para $NETPREFIX.0/24"
else
  iptables -t nat -A POSTROUTING -s "$NETPREFIX.0/24" -o eth0 -j MASQUERADE
  echo "[+] NAT agregado para salida a internet"
fi

# ===============================================
# CREAR SERVICIO SYSTEMD SI NO EXISTE
# ===============================================
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME.service"
if [[ ! -f "$SERVICE_PATH" ]]; then
  echo "[+] Instalando servicio systemd..."
  cat <<EOF > "$SERVICE_PATH"
[Unit]
Description=Proxmox Auto Network Bootstrap
After=network.target

[Service]
Type=oneshot
ExecStart=$LOCAL_SCRIPT
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  echo "[✓] Servicio $SERVICE_NAME habilitado al inicio."
else
  echo "[✓] Servicio $SERVICE_NAME ya existe."
fi

# ===============================================
# ASIGNACIÓN AUTOMÁTICA DE IP
# ===============================================
assign_static_ip() {
  local ID="$1"; local TYPE SET_CMD START_CMD GET_HOSTNAME
  [[ -z "$ID" ]] && { echo "Uso: $0 <CT_ID|VM_ID>"; return 1; }

  if pct status "$ID" &>/dev/null; then
    TYPE="ct"; SET_CMD="pct set"; START_CMD="pct restart $ID"; GET_HOSTNAME="pct exec $ID -- hostname"
  elif qm status "$ID" &>/dev/null; then
    TYPE="vm"; SET_CMD="qm set"; START_CMD="qm reset $ID"; GET_HOSTNAME="echo VM_$ID"
  else
    echo "[X] ID $ID no válido"; return 1
  fi

  echo "[+] Buscando IP libre para $TYPE $ID..."
  for i in $(seq $STATIC_START $STATIC_END); do
    IP="$NETPREFIX.$i"
    grep -q "$IP" "$LOG_FILE" && continue
    ping -c1 -W1 "$IP" &>/dev/null && continue

    # Saltar si ya tiene net0
    if [[ "$TYPE" == "ct" && $(pct config "$ID" | grep -c net0:) -gt 0 ]] || \
       [[ "$TYPE" == "vm" && $(qm config "$ID" | grep -c net0:) -gt 0 ]]; then
      echo "[!] $TYPE $ID ya tiene red. Saltando."; return
    fi

    # Asignar red
    if [[ "$TYPE" == "ct" ]]; then
      $SET_CMD "$ID" -net0 name=eth0,bridge=$BRIDGE,ip="$IP/24",gw=$GATEWAY
    else
      $SET_CMD "$ID" -net0 model=virtio,bridge=$BRIDGE
      echo "[!] Configura IP $IP dentro de la VM."
    fi

    $START_CMD; sleep 5
    HOSTNAME=$($GET_HOSTNAME)
    echo "$(date '+%F %T') TYPE=$TYPE ID=$ID NAME=$HOSTNAME IP=$IP" >> "$LOG_FILE"
    echo "[✔] IP $IP asignada a $TYPE $ID ($HOSTNAME)"
    return
  done
  echo "[X] Sin IPs libres en rango $NETPREFIX.$STATIC_START-$STATIC_END"
}

# Ejecutar asignación si se pasa ID
[[ -n "$ID" ]] && assign_static_ip "$ID"

# ===============================================
# MOSTRAR IPs ASIGNADAS (LOG)
# ===============================================
echo -e "\n📄 Lista de IPs asignadas (últimas):"
printf "%-19s | %-4s | %-3s | %-15s | %-13s\n" "FECHA" "TIPO" "ID" "NOMBRE" "IP"
echo "--------------------+------+-----+-----------------+-------------"
if [[ -f "$LOG_FILE" ]]; then
  tail -n 10 "$LOG_FILE" | while read -r line; do
    FECHA=$(echo "$line" | cut -d' ' -f1-2)
    TYPE=$(echo "$line" | grep -oP 'TYPE=\K\w+')
    IDL=$(echo "$line" | grep -oP 'ID=\K\d+')
    NAME=$(echo "$line" | grep -oP 'NAME=\K[^ ]+')
    IPA=$(echo "$line" | grep -oP 'IP=\K[\d\.]+')
    printf "%-19s | %-4s | %-3s | %-15s | %-13s\n" "$FECHA" "$TYPE" "$IDL" "$NAME" "$IPA"
  done
else
  echo "[!] No hay registros aún."
fi
