#!/bin/bash

# ============================================================
# Homelab Complete Deployment Script
# Deployment automático com monitoramento + correções integradas
# Autor: Alex Marques
# Versão: 6.0 Unified - GitHub Safe Edition
# Compatível: Ubuntu Server 22.04+
# ============================================================

set -e

BASE_DIR="/docker/homelab"
NETWORK_NAME="homelab_net"
INFLUX_ORG="homelab"
INFLUX_BUCKET="default"

# Gerar senhas seguras
INFLUX_TOKEN=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
GRAFANA_PASS=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
INFLUXDB_PASS=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)

log() { echo -e "\n\033[1;32m==> $1\033[0m"; }
warn() { echo -e "\033[1;33m[AVISO]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERRO]\033[0m $1"; exit 1; }
success() { echo -e "\033[1;32m[✓]\033[0m $1"; }
info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }

if [ "$EUID" -ne 0 ]; then
    error "Execute este script como root (sudo)."
fi

# ============================================================
# DETECTAR IP DO SERVIDOR
# ============================================================
detect_server_ip() {
    local detected_ip
    detected_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
    
    if [ -z "$detected_ip" ]; then
        error "Não foi possível detectar o IP automaticamente"
    fi
    
    echo ""
    echo "================================================"
    echo "  IP DETECTADO: $detected_ip"
    echo "================================================"
    echo ""
    read -p "Este IP está correto? (s/n): " confirm
    
    if [[ $confirm =~ ^[Ss]$ ]]; then
        SERVER_IP="$detected_ip"
    else
        read -p "Digite o IP correto do servidor: " SERVER_IP
    fi
    
    success "IP do servidor: $SERVER_IP"
}

log "INICIANDO DEPLOYMENT COMPLETO DO HOMELAB..."
detect_server_ip

# ============================================================
# PASSO 1: Instalando Docker
# ============================================================
log "PASSO 1: Instalando Docker e Docker Compose..."
apt-get update -y > /dev/null 2>&1
apt-get install -y ca-certificates curl gnupg lsb-release jq > /dev/null 2>&1

if ! command -v docker &>/dev/null; then
    info "Instalando Docker..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -y > /dev/null 2>&1
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin > /dev/null 2>&1
    systemctl enable docker --now > /dev/null 2>&1
    success "Docker instalado"
else
    success "Docker já está instalado"
fi

# ============================================================
# PASSO 2: Criando estrutura
# ============================================================
log "PASSO 2: Criando estrutura de diretórios..."
mkdir -p $BASE_DIR/{homepage/config,grafana/{provisioning/{datasources,dashboards},data},influxdb/data,prometheus/{data,rules},telegraf,portainer,speedtest-tracker,nebula-sync,node-exporter,alertmanager,cadvisor}

info "Aplicando permissões corretas..."
chown -R 65534:65534 "$BASE_DIR/prometheus/data"
chmod -R 755 "$BASE_DIR/prometheus/data"
chown -R 472:472 "$BASE_DIR/grafana/data"
chmod -R 755 "$BASE_DIR/grafana"

success "Estrutura criada com permissões corretas"

# ============================================================
# PASSO 3: Rede Docker
# ============================================================
log "PASSO 3: Configurando rede Docker..."
docker network inspect $NETWORK_NAME >/dev/null 2>&1 || docker network create $NETWORK_NAME > /dev/null 2>&1
success "Rede configurada"

# ============================================================
# PASSO 4: InfluxDB
# ============================================================
log "PASSO 4: Configurando InfluxDB..."
cat > "$BASE_DIR/influxdb/.env" <<EOF
DOCKER_INFLUXDB_INIT_MODE=setup
DOCKER_INFLUXDB_INIT_USERNAME=admin
DOCKER_INFLUXDB_INIT_PASSWORD=$INFLUXDB_PASS
DOCKER_INFLUXDB_INIT_ORG=$INFLUX_ORG
DOCKER_INFLUXDB_INIT_BUCKET=$INFLUX_BUCKET
DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=$INFLUX_TOKEN
EOF

cat > "$BASE_DIR/influxdb/docker-compose.yaml" <<EOF
services:
  influxdb:
    image: influxdb:2.7
    container_name: influxdb
    restart: unless-stopped
    env_file: [.env]
    volumes: ["./data:/var/lib/influxdb2"]
    ports: ["8086:8086"]
    networks: [$NETWORK_NAME]
    healthcheck:
      test: ["CMD", "influx", "ping"]
      interval: 30s
      timeout: 10s
      retries: 3
networks:
  $NETWORK_NAME:
    external: true
EOF
success "InfluxDB configurado"

# ============================================================
# PASSO 5: Node Exporter
# ============================================================
log "PASSO 5: Configurando Node Exporter..."
cat > "$BASE_DIR/node-exporter/docker-compose.yaml" <<EOF
services:
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    command:
      - '--path.rootfs=/host'
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)(\$\$|/)'
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    ports: ["9101:9100"]
    networks: [$NETWORK_NAME]
networks:
  $NETWORK_NAME:
    external: true
EOF
success "Node Exporter configurado"

# ============================================================
# PASSO 6: Telegraf
# ============================================================
log "PASSO 6: Configurando Telegraf..."
DOCKER_GID=$(getent group docker | cut -d: -f3)

cat > "$BASE_DIR/telegraf/docker-compose.yaml" <<EOF
services:
  telegraf:
    image: telegraf:1.29
    container_name: telegraf
    restart: unless-stopped
    user: "root:${DOCKER_GID}"
    volumes:
      - ./telegraf.conf:/etc/telegraf/telegraf.conf:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    ports: ["9100:9100"]
    networks: [$NETWORK_NAME]
networks:
  $NETWORK_NAME:
    external: true
EOF

cat > "$BASE_DIR/telegraf/telegraf.conf" <<EOF
[agent]
  interval = "10s"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  flush_interval = "10s"
  hostname = "homelab-server"

[[outputs.influxdb_v2]]
  urls = ["http://influxdb:8086"]
  token = "$INFLUX_TOKEN"
  organization = "$INFLUX_ORG"
  bucket = "$INFLUX_BUCKET"

[[outputs.prometheus_client]]
  listen = ":9100"
  path = "/metrics"

[[inputs.cpu]]
  percpu = true
  totalcpu = true
[[inputs.disk]]
  ignore_fs = ["tmpfs", "devtmpfs", "devfs", "overlay", "squashfs"]
[[inputs.diskio]]
[[inputs.mem]]
[[inputs.processes]]
[[inputs.swap]]
[[inputs.system]]
[[inputs.net]]
[[inputs.netstat]]
[[inputs.docker]]
  endpoint = "unix:///var/run/docker.sock"
  timeout = "5s"
  perdevice = true
  total = true
EOF
success "Telegraf configurado"

# ============================================================
# PASSO 7: Alertmanager
# ============================================================
log "PASSO 7: Configurando Alertmanager..."
cat > "$BASE_DIR/alertmanager/docker-compose.yaml" <<EOF
services:
  alertmanager:
    image: prom/alertmanager:latest
    container_name: alertmanager
    restart: unless-stopped
    volumes:
      - ./alertmanager.yml:/etc/alertmanager/alertmanager.yml
      - alertmanager_data:/alertmanager
    ports: ["9093:9093"]
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'
    networks: [$NETWORK_NAME]
volumes:
  alertmanager_data:
networks:
  $NETWORK_NAME:
    external: true
EOF

cat > "$BASE_DIR/alertmanager/alertmanager.yml" <<'EOF'
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'severity']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default'

receivers:
  - name: 'default'
    # Configure notificações aqui (email, slack, discord, telegram, webhook)

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname']
EOF
success "Alertmanager configurado"

# ============================================================
# PASSO 8: cAdvisor
# ============================================================
log "PASSO 8: Configurando cAdvisor..."
cat > "$BASE_DIR/cadvisor/docker-compose.yaml" <<EOF
services:
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.47.0
    container_name: cadvisor
    restart: unless-stopped
    privileged: true
    devices:
      - /dev/kmsg
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
      - /dev/disk:/dev/disk:ro
    ports: ["8080:8080"]
    networks: [$NETWORK_NAME]
networks:
  $NETWORK_NAME:
    external: true
EOF
success "cAdvisor configurado"

# ============================================================
# PASSO 9: Prometheus
# ============================================================
log "PASSO 9: Configurando Prometheus..."
cat > "$BASE_DIR/prometheus/docker-compose.yaml" <<EOF
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    user: "65534:65534"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - ./rules:/etc/prometheus/rules
      - ./data:/prometheus
    ports: ["9090:9090"]
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
      - '--web.enable-lifecycle'
    networks: [$NETWORK_NAME]
networks:
  $NETWORK_NAME:
    external: true
EOF

cat > "$BASE_DIR/prometheus/prometheus.yml" <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'homelab'

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

rule_files:
  - '/etc/prometheus/rules/*.yml'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'telegraf'
    static_configs:
      - targets: ['telegraf:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
EOF

cat > "$BASE_DIR/prometheus/rules/alerts.yml" <<'EOF'
groups:
  - name: homelab_system_alerts
    interval: 30s
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "CPU alto: {{ $value | humanizePercentage }}"
          
      - alert: CriticalCPUUsage
        expr: 100 - (avg(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 95
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "CPU CRÍTICO: {{ $value | humanizePercentage }}"
      
      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Memória alta: {{ $value | humanizePercentage }}"
          
      - alert: CriticalMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 95
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "MEMÓRIA CRÍTICA: {{ $value | humanizePercentage }}"
      
      - alert: LowDiskSpace
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 15
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Disco com pouco espaço: {{ $value | humanizePercentage }} livre"
          
      - alert: CriticalDiskSpace
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 5
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "DISCO CRÍTICO: {{ $value | humanizePercentage }} livre"
      
      - alert: HighLoadAverage
        expr: node_load5 > 4
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Load average alto: {{ $value }}"
      
      - alert: HighSwapUsage
        expr: (1 - (node_memory_SwapFree_bytes / node_memory_SwapTotal_bytes)) * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Swap alto: {{ $value | humanizePercentage }}"
EOF
success "Prometheus configurado"

# ============================================================
# PASSO 10: Grafana
# ============================================================
log "PASSO 10: Configurando Grafana..."
cat > "$BASE_DIR/grafana/docker-compose.yaml" <<EOF
services:
  grafana:
    image: grafana/grafana:10.4.0
    container_name: grafana
    restart: unless-stopped
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=$GRAFANA_PASS
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-piechart-panel
      - GF_SERVER_ROOT_URL=http://${SERVER_IP}:3001
      - GF_AUTH_ANONYMOUS_ENABLED=false
    volumes:
      - ./data:/var/lib/grafana
      - ./provisioning:/etc/grafana/provisioning
    ports: ["3001:3000"]
    networks: [$NETWORK_NAME]
    user: "472"
networks:
  $NETWORK_NAME:
    external: true
EOF

mkdir -p "$BASE_DIR/grafana/provisioning/datasources"
mkdir -p "$BASE_DIR/grafana/provisioning/dashboards"

cat > "$BASE_DIR/grafana/provisioning/datasources/datasources.yml" <<EOF
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
    jsonData:
      httpMethod: POST
      timeInterval: 15s
      
  - name: InfluxDB
    type: influxdb
    access: proxy
    url: http://influxdb:8086
    editable: true
    jsonData:
      version: Flux
      organization: $INFLUX_ORG
      defaultBucket: $INFLUX_BUCKET
    secureJsonData:
      token: $INFLUX_TOKEN
EOF

cat > "$BASE_DIR/grafana/provisioning/dashboards/dashboards.yml" <<'EOF'
apiVersion: 1
providers:
  - name: 'Homelab Dashboards'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
EOF
success "Grafana configurado"

# ============================================================
# PASSO 11: Homepage
# ============================================================
log "PASSO 11: Configurando Homepage..."
cat > "$BASE_DIR/homepage/docker-compose.yaml" <<EOF
services:
  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    container_name: homepage
    restart: unless-stopped
    ports: ["3000:3000"]
    volumes:
      - ./config:/app/config
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment: 
      - PUID=0
      - PGID=0
    networks: [$NETWORK_NAME]
networks:
  $NETWORK_NAME:
    external: true
EOF

cat > "$BASE_DIR/homepage/config/settings.yaml" <<EOF
title: Homelab Complete
theme: dark
color: slate
EOF

cat > "$BASE_DIR/homepage/config/services.yaml" <<EOF
- Monitoramento:
    - Grafana:
        href: http://${SERVER_IP}:3001
    - Prometheus:
        href: http://${SERVER_IP}:9090
    - Alertmanager:
        href: http://${SERVER_IP}:9093
EOF

cat > "$BASE_DIR/homepage/config/widgets.yaml" <<EOF
- resources:
    cpu: true
    memory: true
    disk: /
EOF

chmod -R 755 "$BASE_DIR/homepage/config"
success "Homepage configurado"

# ============================================================
# OUTROS SERVIÇOS
# ============================================================
log "PASSO 12: Configurando outros serviços..."

cat > "$BASE_DIR/speedtest-tracker/docker-compose.yaml" <<EOF
services:
  speedtest:
    image: lscr.io/linuxserver/speedtest-tracker:latest
    container_name: speedtest-tracker
    restart: unless-stopped
    environment:
      - PUID=1000
      - PGID=1000
      - APP_KEY=base64:$(openssl rand -base64 32)
      - DB_CONNECTION=sqlite
    volumes: [speedtest_data:/config]
    ports: ["8765:80"]
    networks: [$NETWORK_NAME]
volumes:
  speedtest_data:
networks:
  $NETWORK_NAME:
    external: true
EOF

cat > "$BASE_DIR/nebula-sync/.env.example" <<'EOF'
# Configure para sincronizar Pi-hole (opcional)
# PRIMARY=http://IP_PIHOLE|SENHA
# REPLICAS=http://IP_REPLICA|SENHA
EOF

cat > "$BASE_DIR/portainer/docker-compose.yaml" <<EOF
services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    ports: ["9000:9000"]
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks: [$NETWORK_NAME]
volumes:
  portainer_data:
networks:
  $NETWORK_NAME:
    external: true
EOF
success "Outros serviços configurados"

# ============================================================
# INICIANDO CONTAINERS
# ============================================================
log "PASSO 13: Iniciando todos os containers..."

cd "$BASE_DIR/influxdb" && docker compose up -d && sleep 8
cd "$BASE_DIR/node-exporter" && docker compose up -d && sleep 2
cd "$BASE_DIR/telegraf" && docker compose up -d && sleep 3
cd "$BASE_DIR/alertmanager" && docker compose up -d && sleep 2
cd "$BASE_DIR/cadvisor" && docker compose up -d && sleep 2
cd "$BASE_DIR/prometheus" && docker compose up -d && sleep 8
cd "$BASE_DIR/grafana" && docker compose up -d && sleep 10
cd "$BASE_DIR/speedtest-tracker" && docker compose up -d && sleep 3
cd "$BASE_DIR/homepage" && docker compose up -d && sleep 2
cd "$BASE_DIR/portainer" && docker compose up -d && sleep 2

success "Todos os containers iniciados!"

# ============================================================
# AGUARDANDO SERVIÇOS
# ============================================================
log "Aguardando serviços ficarem prontos..."

for i in {1..15}; do
    curl -s http://localhost:8086/health | grep -q "pass" && break
    sleep 2
done

for i in {1..15}; do
    curl -s http://localhost:9090/-/healthy > /dev/null 2>&1 && break
    sleep 2
done

for i in {1..20}; do
    curl -s http://localhost:3001/api/health > /dev/null 2>&1 && break
    sleep 2
done

success "Serviços prontos!"

# ============================================================
# SALVANDO CREDENCIAIS
# ============================================================
cat > "$BASE_DIR/CREDENTIALS.txt" <<EOF
================================================================================
                    CREDENCIAIS DO HOMELAB
================================================================================

🔐 GRAFANA:
   URL: http://${SERVER_IP}:3001
   Usuário: admin
   Senha: $GRAFANA_PASS

🔐 INFLUXDB:
   URL: http://${SERVER_IP}:8086
   Usuário: admin
   Senha: $INFLUXDB_PASS
   Token: $INFLUX_TOKEN

🔐 PORTAINER:
   URL: http://${SERVER_IP}:9000
   (Configure no primeiro acesso)

⚠️  Guarde este arquivo em local seguro!
================================================================================
EOF

chmod 600 "$BASE_DIR/CREDENTIALS.txt"

cat > "$BASE_DIR/.homelab.conf" <<EOF
SERVER_IP="$SERVER_IP"
BASE_DIR="$BASE_DIR"
NETWORK_NAME="$NETWORK_NAME"
EOF

# ============================================================
# MENSAGEM FINAL
# ============================================================
clear
echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           ✅ HOMELAB INSTALADO COM SUCESSO! 🎉               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "📊 SERVIÇOS DISPONÍVEIS:"
echo "   🏠 Homepage:      http://${SERVER_IP}:3000"
echo "   📈 Grafana:       http://${SERVER_IP}:3001 (admin/$GRAFANA_PASS)"
echo "   🔥 Prometheus:    http://${SERVER_IP}:9090"
echo "   🚨 Alertmanager:  http://${SERVER_IP}:9093"
echo "   💾 InfluxDB:      http://${SERVER_IP}:8086"
echo "   🐋 Portainer:     http://${SERVER_IP}:9000"
echo ""
echo "🔐 CREDENCIAIS: $BASE_DIR/CREDENTIALS.txt"
echo ""
echo "✨ Aproveite seu Homelab!"
echo ""
