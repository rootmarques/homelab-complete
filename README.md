# 🏠 Homelab Complete
<img width="1787" height="842" alt="Homelab_Docker" src="https://github.com/user-attachments/assets/85c5d928-b7f5-4ac2-8492-878215dc014c" />

Stack completa de monitoramento para homelab com Prometheus, Grafana, InfluxDB e mais.

## 📊 Serviços Incluídos

### Monitoramento
- **Prometheus** - Coleta de métricas
- **Grafana** - Visualização de dashboards
- **InfluxDB** - Banco de dados de séries temporais
- **Alertmanager** - Gerenciamento de alertas
- **Node Exporter** - Métricas do servidor
- **Telegraf** - Agente de coleta de métricas
- **cAdvisor** - Métricas de containers

### Gerenciamento
- **Homepage** - Dashboard unificado
- **Portainer** - Gerenciamento de containers
- **Speedtest Tracker** - Monitor de velocidade de internet

## 🚀 Instalação Rápida
```bash
# Download do script
wget https://raw.githubusercontent.com/SEU_USUARIO/homelab-complete/main/install.sh

# Dar permissão de execução
chmod +x install.sh

# Executar (requer sudo)
sudo ./install.sh
```

## 📋 Requisitos

- **Sistema Operacional:** Ubuntu Server 22.04+
- **RAM:** Mínimo 4GB (recomendado 8GB)
- **Disco:** Mínimo 20GB livres
- **Acesso:** Root/sudo

## 🔧 Configuração

### Detecção Automática de IP
O script detecta automaticamente o IP do servidor e solicita confirmação.

### Nebula Sync (Opcional)
Para sincronizar múltiplas instâncias do Pi-hole:

1. Navegue até `/docker/homelab/nebula-sync/`
2. Copie o arquivo exemplo: `cp .env.example .env`
3. Edite o `.env` com seus IPs e senhas
4. Descomente o serviço no `docker-compose.yaml`
5. Inicie: `docker compose up -d`

## 📍 Acesso aos Serviços

Após a instalação, acesse:

| Serviço | Porta | URL |
|---------|-------|-----|
| Homepage | 3000 | http://SEU_IP:3000 |
| Grafana | 3001 | http://SEU_IP:3001 |
| Prometheus | 9090 | http://SEU_IP:9090 |
| Alertmanager | 9093 | http://SEU_IP:9093 |
| InfluxDB | 8086 | http://SEU_IP:8086 |
| Portainer | 9000 | http://SEU_IP:9000 |
| Speedtest | 8765 | http://SEU_IP:8765 |
| cAdvisor | 8080 | http://SEU_IP:8080 |

## 🔐 Credenciais

As credenciais são geradas automaticamente e salvas em:
```
/docker/homelab/CREDENTIALS.txt
```

**⚠️ Guarde este arquivo em local seguro!**

## 📖 Estrutura do Projeto
```
/docker/homelab/
├── influxdb/
├── prometheus/
├── grafana/
├── alertmanager/
├── telegraf/
├── node-exporter/
├── cadvisor/
├── homepage/
├── portainer/
├── speedtest-tracker/
├── nebula-sync/
└── CREDENTIALS.txt
```

## 🛠️ Comandos Úteis

O script cria vários comandos auxiliares em `/docker/homelab/`:
```bash
# Ver status de todos os containers
docker ps

# Ver logs de um serviço específico
docker logs -f nome-do-container

# Reiniciar um serviço
cd /docker/homelab/grafana && docker compose restart

# Parar tudo
cd /docker/homelab && docker compose down
```

## 🔄 Atualizações

Para atualizar os containers:
```bash
cd /docker/homelab/SERVICO
docker compose pull
docker compose up -d
```

## 🐛 Troubleshooting

### Prometheus com erro de permissão
```bash
sudo chown -R 65534:65534 /docker/homelab/prometheus/data
cd /docker/homelab/prometheus && docker compose restart
```

### Grafana com erro de permissão
```bash
sudo chown -R 472:472 /docker/homelab/grafana/data
cd /docker/homelab/grafana && docker compose restart
```

### Ver logs de um serviço
```bash
docker logs -f nome-do-container
```

## 📊 Dashboards do Grafana

Um dashboard básico é criado automaticamente com:
- Uso de CPU
- Uso de Memória
- Uso de Disco
- Load Average

Você pode importar mais dashboards da comunidade em https://grafana.com/grafana/dashboards/

## 🤝 Contribuindo

Contribuições são bem-vindas! Sinta-se livre para:
- Reportar bugs
- Sugerir melhorias
- Enviar pull requests

## 📄 Licença

MIT License - veja LICENSE para detalhes

## ⭐ Suporte

Se este projeto foi útil, considere dar uma estrela! ⭐

---

**Autor:** Alex Marques
**Versão:** 6.0
