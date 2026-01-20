# WordPress Farm Implementation Guide

## Prerequisites

- Digital Ocean account with API token
- Cloudflare account with API token
- Domain name pointed to Cloudflare
- Local machine with Docker and `doctl` CLI installed
- SSH key pair generated

---

## Phase 1: Infrastructure Provisioning (Week 1)

### Step 1: Create Digital Ocean Droplets

```bash
# Set variables
export DO_REGION="nyc3"
export DO_SIZE="s-8vcpu-16gb"
export SSH_FINGERPRINT="your-ssh-key-fingerprint"

# Create Manager Nodes
for i in 1 2 3; do
  doctl compute droplet create wp-manager-$i \
    --region $DO_REGION \
    --size $DO_SIZE \
    --image ubuntu-22-04-x64 \
    --ssh-keys $SSH_FINGERPRINT \
    --tag-names swarm-manager \
    --enable-private-networking \
    --enable-monitoring \
    --wait
done

# Create Worker Nodes (start with 6, scale to 20+)
for i in {1..6}; do
  doctl compute droplet create wp-worker-$i \
    --region $DO_REGION \
    --size $DO_SIZE \
    --image ubuntu-22-04-x64 \
    --ssh-keys $SSH_FINGERPRINT \
    --tag-names swarm-worker \
    --enable-private-networking \
    --enable-monitoring \
    --wait
done

# Create Database Nodes
for i in 1 2 3; do
  doctl compute droplet create wp-db-$i \
    --region $DO_REGION \
    --size $DO_SIZE \
    --image ubuntu-22-04-x64 \
    --ssh-keys $SSH_FINGERPRINT \
    --tag-names swarm-database \
    --enable-private-networking \
    --enable-monitoring \
    --wait
done

# Create Storage Nodes
for i in 1 2; do
  doctl compute droplet create wp-storage-$i \
    --region $DO_REGION \
    --size $DO_SIZE \
    --image ubuntu-22-04-x64 \
    --ssh-keys $SSH_FINGERPRINT \
    --tag-names swarm-storage \
    --enable-private-networking \
    --enable-monitoring \
    --wait
  
  # Attach block storage for NFS
  doctl compute volume create wp-storage-vol-$i \
    --region $DO_REGION \
    --size 500GiB \
    --fs-type ext4
done

# Create Floating IP for Load Balancer
doctl compute floating-ip create --region $DO_REGION
```

### Step 2: Configure Firewall

```bash
# Create firewall rules
doctl compute firewall create \
  --name wp-farm-firewall \
  --inbound-rules "protocol:tcp,ports:22,sources:addresses:YOUR_IP/32 protocol:tcp,ports:80,sources:addresses:0.0.0.0/0,::/0 protocol:tcp,ports:443,sources:addresses:0.0.0.0/0,::/0" \
  --outbound-rules "protocol:tcp,ports:all,destinations:addresses:0.0.0.0/0,::/0 protocol:udp,ports:all,destinations:addresses:0.0.0.0/0,::/0" \
  --tag-names swarm-manager,swarm-worker,swarm-database,swarm-storage

# Create internal firewall for Swarm
doctl compute firewall create \
  --name swarm-internal \
  --inbound-rules "protocol:tcp,ports:2377,sources:tags:swarm-manager protocol:tcp,ports:7946,sources:tags:swarm-manager,swarm-worker,swarm-database,swarm-storage protocol:udp,ports:7946,sources:tags:swarm-manager,swarm-worker,swarm-database,swarm-storage protocol:udp,ports:4789,sources:tags:swarm-manager,swarm-worker,swarm-database,swarm-storage" \
  --tag-names swarm-manager,swarm-worker,swarm-database,swarm-storage
```

### Step 3: Initialize Nodes

Create an Ansible playbook or bash script to initialize all nodes:

```bash
#!/bin/bash
# init-node.sh - Run on each node

set -e

# Update system
apt-get update && apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh

# Configure Docker daemon
cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "metrics-addr": "0.0.0.0:9323",
  "experimental": true
}
EOF

systemctl restart docker

# Install additional tools
apt-get install -y \
  htop \
  iotop \
  nfs-common \
  glusterfs-client \
  vim \
  curl \
  wget \
  git \
  ufw

# Configure UFW (Ubuntu Firewall)
ufw default deny incoming
ufw default allow outgoing
ufw allow from any to any port 22 proto tcp
ufw allow from any to any port 80 proto tcp
ufw allow from any to any port 443 proto tcp
# Swarm ports
ufw allow from 10.0.0.0/8 to any port 2377 proto tcp
ufw allow from 10.0.0.0/8 to any port 7946 proto tcp
ufw allow from 10.0.0.0/8 to any port 7946 proto udp
ufw allow from 10.0.0.0/8 to any port 4789 proto udp
ufw --force enable

# System tuning for high performance
cat >> /etc/sysctl.conf <<EOF
# Network tuning
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.ip_local_port_range = 1024 65535

# File system tuning
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288

# Memory management
vm.swappiness = 10
vm.dirty_ratio = 60
vm.dirty_background_ratio = 2
EOF

sysctl -p

echo "Node initialization complete!"
```

### Step 4: Initialize Docker Swarm

```bash
# On first manager node (wp-manager-1)
MANAGER_IP=$(hostname -I | awk '{print $1}')
docker swarm init --advertise-addr $MANAGER_IP

# Save the join tokens
MANAGER_TOKEN=$(docker swarm join-token manager -q)
WORKER_TOKEN=$(docker swarm join-token worker -q)

echo "Manager Token: $MANAGER_TOKEN"
echo "Worker Token: $WORKER_TOKEN"

# On other manager nodes (wp-manager-2, wp-manager-3)
docker swarm join --token $MANAGER_TOKEN $MANAGER_IP:2377

# On worker nodes
docker swarm join --token $WORKER_TOKEN $MANAGER_IP:2377

# Label nodes for placement
docker node update --label-add database=node1 wp-db-1
docker node update --label-add database=node2 wp-db-2
docker node update --label-add database=node3 wp-db-3
docker node update --label-add storage=nfs wp-storage-1
docker node update --label-add storage=nfs wp-storage-2

# Verify cluster
docker node ls
```

---

## Phase 2: Network Setup (Week 1)

### Step 5: Create Overlay Networks

```bash
# On manager node
docker network create --driver overlay --attachable traefik-public
docker network create --driver overlay --attachable --opt encrypted=true shared-services
docker network create --driver overlay --opt encrypted=true database
docker network create --driver overlay --attachable monitoring
docker network create --driver overlay management

# Verify networks
docker network ls
```

### Step 6: Configure Storage Layer

```bash
# On storage nodes (wp-storage-1 and wp-storage-2)

# Format and mount block storage
mkfs.ext4 /dev/disk/by-id/scsi-0DO_Volume_wp-storage-vol-1
mkdir -p /mnt/storage
mount /dev/disk/by-id/scsi-0DO_Volume_wp-storage-vol-1 /mnt/storage
echo "/dev/disk/by-id/scsi-0DO_Volume_wp-storage-vol-1 /mnt/storage ext4 defaults,nofail 0 2" >> /etc/fstab

# Install and configure GlusterFS
apt-get install -y glusterfs-server
systemctl start glusterd
systemctl enable glusterd

# On storage-1, peer with storage-2
gluster peer probe wp-storage-2

# Create replicated volume
mkdir -p /mnt/storage/brick
gluster volume create wp-data replica 2 \
  wp-storage-1:/mnt/storage/brick \
  wp-storage-2:/mnt/storage/brick \
  force

gluster volume start wp-data

# Configure for optimal performance
gluster volume set wp-data performance.cache-size 256MB
gluster volume set wp-data performance.write-behind-window-size 1MB
gluster volume set wp-data network.ping-timeout 10
```

---

## Phase 3: Core Services Deployment (Week 2)

### Step 7: Create Secrets

```bash
# Generate strong passwords
export MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
export GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32)
export PORTAINER_ADMIN_PASSWORD=$(openssl rand -base64 32)
export REGISTRY_SECRET=$(openssl rand -hex 32)
export RESTIC_PASSWORD=$(openssl rand -base64 32)

# Create Docker secrets
echo "$MYSQL_ROOT_PASSWORD" | docker secret create mysql_root_password -
echo "$GRAFANA_ADMIN_PASSWORD" | docker secret create grafana_admin_password -
echo "$PORTAINER_ADMIN_PASSWORD" | docker secret create portainer_admin_password -
echo "$RESTIC_PASSWORD" | docker secret create restic_password -

# Digital Ocean Spaces credentials
echo "YOUR_SPACES_ACCESS_KEY" | docker secret create s3_access_key -
echo "YOUR_SPACES_SECRET_KEY" | docker secret create s3_secret_key -

# Save passwords securely
cat > ~/credentials.txt <<EOF
MySQL Root: $MYSQL_ROOT_PASSWORD
Grafana Admin: $GRAFANA_ADMIN_PASSWORD
Portainer Admin: $PORTAINER_ADMIN_PASSWORD
Restic: $RESTIC_PASSWORD
EOF

# Encrypt and backup
gpg -c ~/credentials.txt
rm ~/credentials.txt
```

### Step 8: Deploy Traefik Stack

```bash
cd /var/opt
mkdir -p stacks/traefik
cd stacks/traefik

# Download the stack file
wget https://your-repo/traefik-stack.yml

# Create necessary directories
mkdir -p varnish

# Create Varnish VCL configuration
cat > varnish/default.vcl <<'EOF'
vcl 4.1;

backend default {
    .host = "nginx";
    .port = "80";
}

sub vcl_recv {
    # Don't cache admin pages
    if (req.url ~ "^/wp-(admin|login)" || req.url ~ "preview=true") {
        return (pass);
    }
    
    # Don't cache cart/checkout
    if (req.url ~ "add-to-cart" || req.url ~ "cart" || req.url ~ "checkout") {
        return (pass);
    }
    
    # Don't cache logged-in users
    if (req.http.Cookie ~ "wordpress_logged_in") {
        return (pass);
    }
    
    # Remove cookies for static content
    if (req.url ~ "\.(jpg|jpeg|png|gif|css|js|ico|svg|woff|woff2|ttf)$") {
        unset req.http.Cookie;
    }
}

sub vcl_backend_response {
    # Cache static content for 1 hour
    if (bereq.url ~ "\.(jpg|jpeg|png|gif|css|js|ico|svg|woff|woff2|ttf)$") {
        set beresp.ttl = 1h;
    }
    
    # Cache HTML for 5 minutes
    if (beresp.http.Content-Type ~ "text/html") {
        set beresp.ttl = 5m;
    }
}
EOF

# Set environment variables
export DOMAIN=yourdomain.com

# Deploy stack
docker stack deploy -c traefik-stack.yml traefik

# Wait for services to be ready
sleep 30

# Check status
docker stack services traefik
```

### Step 9: Deploy Database Stack

```bash
cd /var/opt/stacks
mkdir -p database mariadb-config proxysql-config backup-scripts
cd database

# Download stack file
wget https://your-repo/database-stack.yml

# Create MariaDB configuration
cat > ../mariadb-config/galera.cnf <<EOF
[mysqld]
# Galera Cluster Configuration
wsrep_on=ON
wsrep_provider=/usr/lib/galera/libgalera_smm.so

# InnoDB Settings
innodb_flush_log_at_trx_commit=2
innodb_flush_method=O_DIRECT
innodb_file_per_table=ON
innodb_strict_mode=ON

# Binary Logging
log_bin=mysql-bin
expire_logs_days=7

# Character Set
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci

# Query Cache (disabled for Galera)
query_cache_size=0
query_cache_type=0

# Performance Schema
performance_schema=ON
EOF

# Create ProxySQL configuration
cat > ../proxysql-config/proxysql.cnf <<EOF
datadir="/var/lib/proxysql"

admin_variables=
{
    admin_credentials="admin:admin"
    mysql_ifaces="0.0.0.0:6032"
}

mysql_variables=
{
    threads=4
    max_connections=2048
    default_query_delay=0
    default_query_timeout=36000000
    monitor_username="monitor"
    monitor_password="monitor"
    monitor_history=600000
    monitor_connect_interval=60000
    monitor_ping_interval=10000
    monitor_read_only_interval=1500
    monitor_read_only_timeout=500
    ping_interval_server_msec=120000
    ping_timeout_server=500
    commands_stats=true
    sessions_sort=true
    connect_retries_on_failure=10
}

mysql_servers=
(
    { address="galera-1" , port=3306 , hostgroup=10, max_connections=200 },
    { address="galera-2" , port=3306 , hostgroup=10, max_connections=200 },
    { address="galera-3" , port=3306 , hostgroup=10, max_connections=200 }
)

mysql_query_rules=
(
    {
        rule_id=1
        active=1
        match_pattern="^SELECT .* FOR UPDATE$"
        destination_hostgroup=10
        apply=1
    },
    {
        rule_id=2
        active=1
        match_pattern="^SELECT"
        destination_hostgroup=10
        apply=1
    }
)

mysql_users=
(
    { username = "root" , password = "MYSQL_ROOT_PASSWORD" , default_hostgroup = 10 , max_connections=1000 , active = 1 }
)
EOF

# Create backup script
cat > ../backup-scripts/backup-entrypoint.sh <<'EOF'
#!/bin/bash
set -e

# Load credentials
export MYSQL_PASSWORD=$(cat $MYSQL_PASSWORD_FILE)
export S3_ACCESS_KEY=$(cat $S3_ACCESS_KEY_FILE)
export S3_SECRET_KEY=$(cat $S3_SECRET_KEY_FILE)

# Configure S3
export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$S3_SECRET_KEY

backup_full() {
    echo "[$(date)] Starting full backup..."
    BACKUP_DIR="/backup/full-$(date +%Y%m%d-%H%M%S)"
    mkdir -p $BACKUP_DIR
    
    xtrabackup --backup \
        --host=$MYSQL_HOST \
        --port=$MYSQL_PORT \
        --user=$MYSQL_USER \
        --password=$MYSQL_PASSWORD \
        --target-dir=$BACKUP_DIR \
        --parallel=4
    
    # Compress and encrypt
    tar -czf $BACKUP_DIR.tar.gz -C /backup $(basename $BACKUP_DIR)
    gpg --symmetric --cipher-algo AES256 --passphrase $MYSQL_PASSWORD $BACKUP_DIR.tar.gz
    
    # Upload to S3
    aws s3 cp $BACKUP_DIR.tar.gz.gpg s3://$S3_BUCKET/mysql/full/ --endpoint-url=$S3_ENDPOINT
    
    # Cleanup local
    rm -rf $BACKUP_DIR $BACKUP_DIR.tar.gz $BACKUP_DIR.tar.gz.gpg
    
    echo "[$(date)] Full backup complete"
}

backup_incremental() {
    echo "[$(date)] Starting incremental backup..."
    LATEST_FULL=$(find /backup -type d -name "full-*" | sort | tail -1)
    BACKUP_DIR="/backup/inc-$(date +%Y%m%d-%H%M%S)"
    
    xtrabackup --backup \
        --host=$MYSQL_HOST \
        --port=$MYSQL_PORT \
        --user=$MYSQL_USER \
        --password=$MYSQL_PASSWORD \
        --target-dir=$BACKUP_DIR \
        --incremental-basedir=$LATEST_FULL \
        --parallel=4
    
    tar -czf $BACKUP_DIR.tar.gz -C /backup $(basename $BACKUP_DIR)
    gpg --symmetric --cipher-algo AES256 --passphrase $MYSQL_PASSWORD $BACKUP_DIR.tar.gz
    aws s3 cp $BACKUP_DIR.tar.gz.gpg s3://$S3_BUCKET/mysql/incremental/ --endpoint-url=$S3_ENDPOINT
    
    rm -rf $BACKUP_DIR $BACKUP_DIR.tar.gz $BACKUP_DIR.tar.gz.gpg
    echo "[$(date)] Incremental backup complete"
}

# Schedule backups
while true; do
    HOUR=$(date +%H)
    if [ "$HOUR" == "02" ]; then
        backup_full
    else
        MINUTE=$(date +%M)
        if [ $((10#$MINUTE % 360)) -eq 0 ]; then  # Every 6 hours
            backup_incremental
        fi
    fi
    sleep 600  # Check every 10 minutes
done
EOF

chmod +x ../backup-scripts/backup-entrypoint.sh

# Deploy database stack
docker stack deploy -c database-stack.yml database

# Wait for Galera cluster to initialize
sleep 60

# Verify cluster status
docker exec $(docker ps -qf "name=database_galera-1") mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
```

### Step 10: Deploy Monitoring Stack

```bash
cd /var/opt/stacks
mkdir -p monitoring/{prometheus,loki,tempo,grafana,alertmanager,promtail,blackbox}
cd monitoring

# Download stack
wget https://your-repo/monitoring-stack.yml

# Create Prometheus configuration
cat > prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'wordpress-farm'
    environment: 'production'

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

rule_files:
  - '/etc/prometheus/alerts/*.yml'

scrape_configs:
  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Docker Swarm service discovery
  - job_name: 'dockerswarm'
    dockerswarm_sd_configs:
      - host: unix:///var/run/docker.sock
        role: tasks
    relabel_configs:
      - source_labels: [__meta_dockerswarm_service_name]
        target_label: service

  # Node Exporter
  - job_name: 'node-exporter'
    dns_sd_configs:
      - names: ['tasks.node-exporter']
        type: A
        port: 9100

  # cAdvisor
  - job_name: 'cadvisor'
    dns_sd_configs:
      - names: ['tasks.cadvisor']
        type: A
        port: 8080

  # MySQL Exporter
  - job_name: 'mysql'
    static_configs:
      - targets:
          - 'mysql-exporter-1:9104'
          - 'mysql-exporter-2:9104'
          - 'mysql-exporter-3:9104'

  # Traefik
  - job_name: 'traefik'
    dns_sd_configs:
      - names: ['tasks.traefik']
        type: A
        port: 8080

  # WordPress Sites (via custom exporter)
  - job_name: 'wordpress'
    static_configs:
      - targets: ['wordpress-exporter:9500']

  # Blackbox Exporter (Website monitoring)
  - job_name: 'blackbox'
    metrics_path: /probe
    params:
      module: [http_2xx]
    file_sd_configs:
      - files:
          - '/etc/prometheus/targets/websites.json'
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115

remote_write:
  - url: http://mimir:9009/api/v1/push
EOF

# Create alert rules
cat > prometheus/alerts/wordpress-alerts.yml <<EOF
groups:
  - name: wordpress_alerts
    interval: 30s
    rules:
      - alert: HighErrorRate
        expr: rate(traefik_service_requests_total{code=~"5.."}[5m]) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate detected"
          description: "Service {{ \$labels.service }} has error rate of {{ \$value }}"

      - alert: NodeDown
        expr: up{job="node-exporter"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Node is down"
          description: "Node {{ \$labels.instance }} has been down for more than 5 minutes"

      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 90
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage"
          description: "Node {{ \$labels.instance }} memory usage is {{ \$value }}%"

      - alert: DiskSpacelow
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 15
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Low disk space"
          description: "Node {{ \$labels.instance }} has only {{ \$value }}% disk space remaining"

      - alert: MySQLReplicationLag
        expr: mysql_slave_status_seconds_behind_master > 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "MySQL replication lag detected"
          description: "MySQL replication lag is {{ \$value }} seconds"

      - alert: CertificateExpiringSoon
        expr: (traefik_certificate_expiry_timestamp - time()) / 86400 < 7
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "SSL certificate expiring soon"
          description: "Certificate for {{ \$labels.domain }} expires in {{ \$value }} days"
EOF

# Create Loki configuration
cat > loki/loki-config.yaml <<EOF
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2023-01-01
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/boltdb-shipper-active
    cache_location: /loki/boltdb-shipper-cache
    cache_ttl: 24h
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks

limits_config:
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  retention_period: 720h

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: true
  retention_period: 720h

compactor:
  working_directory: /loki/compactor
  shared_store: filesystem
  compaction_interval: 10m
EOF

# Create Promtail configuration
cat > promtail/promtail-config.yaml <<EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  # Docker containers
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        regex: '/(.*)'
        target_label: 'container'
      - source_labels: ['__meta_docker_container_log_stream']
        target_label: 'logstream'
      - source_labels: ['__meta_docker_container_label_com_docker_swarm_service_name']
        target_label: 'service'
      - source_labels: ['__meta_docker_container_label_com_docker_swarm_task_name']
        target_label: 'task'

  # System logs
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          __path__: /var/log/*.log
EOF

# Create Tempo configuration
cat > tempo/tempo-config.yaml <<EOF
server:
  http_listen_port: 3200

distributor:
  receivers:
    otlp:
      protocols:
        http:
        grpc:

ingester:
  trace_idle_period: 10s
  max_block_bytes: 1_000_000
  max_block_duration: 5m

compactor:
  compaction:
    compaction_window: 1h
    max_block_bytes: 100_000_000
    block_retention: 720h
    compacted_block_retention: 1h

storage:
  trace:
    backend: local
    wal:
      path: /tmp/tempo/wal
    local:
      path: /tmp/tempo/blocks

querier:
  frontend_worker:
    frontend_address: tempo:9095

metrics_generator:
  registry:
    external_labels:
      source: tempo
      cluster: wordpress-farm
  storage:
    path: /tmp/tempo/generator/wal
    remote_write:
      - url: http://prometheus:9090/api/v1/write
        send_exemplars: true
EOF

# Create Grafana provisioning
mkdir -p grafana/provisioning/{datasources,dashboards}

cat > grafana/provisioning/datasources/datasources.yaml <<EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false

  - name: Mimir
    type: prometheus
    access: proxy
    url: http://mimir:8080/prometheus
    editable: false

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    editable: false

  - name: Tempo
    type: tempo
    access: proxy
    url: http://tempo:3200
    editable: false
    jsonData:
      tracesToLogs:
        datasourceUid: 'Loki'
      serviceMap:
        datasourceUid: 'Prometheus'
EOF

cat > grafana/provisioning/dashboards/dashboards.yaml <<EOF
apiVersion: 1

providers:
  - name: 'WordPress Farm'
    orgId: 1
    folder: 'WordPress'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF

# Create AlertManager configuration
cat > alertmanager/alertmanager.yml <<EOF
global:
  resolve_timeout: 5m
  slack_api_url: '${SLACK_WEBHOOK_URL}'

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default'
  routes:
    - match:
        severity: critical
      receiver: 'critical'
    - match:
        severity: warning
      receiver: 'warning'

receivers:
  - name: 'default'
    email_configs:
      - to: 'alerts@yourdomain.com'
        from: 'alertmanager@yourdomain.com'
        smarthost: 'smtp.yourdomain.com:587'
        auth_username: 'alertmanager@yourdomain.com'
        auth_password: '${SMTP_PASSWORD}'

  - name: 'critical'
    email_configs:
      - to: 'oncall@yourdomain.com'
        from: 'alertmanager@yourdomain.com'
        smarthost: 'smtp.yourdomain.com:587'
        auth_username: 'alertmanager@yourdomain.com'
        auth_password: '${SMTP_PASSWORD}'
    slack_configs:
      - channel: '#alerts-critical'
        title: 'Critical Alert'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}\n{{ .Annotations.description }}\n{{ end }}'

  - name: 'warning'
    slack_configs:
      - channel: '#alerts-warning'
        title: 'Warning Alert'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}\n{{ .Annotations.description }}\n{{ end }}'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
EOF

# Create Blackbox configuration
cat > blackbox/blackbox.yml <<EOF
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: []
      method: GET
      follow_redirects: true
      preferred_ip_protocol: "ip4"
EOF

# Deploy monitoring stack
docker stack deploy -c monitoring-stack.yml monitoring

# Wait for services
sleep 60

# Check status
docker stack services monitoring
```

### Step 11: Deploy Management Stack

```bash
cd /var/opt/stacks
mkdir -p management
cd management

# Download stack
wget https://your-repo/management-stack.yml

# Deploy
docker stack deploy -c management-stack.yml management

# Check status
docker stack services management
```

---

## Phase 4: WordPress Deployment (Week 3-4)

### Step 12: Build Custom Docker Images

Create a build repository:

```bash
mkdir -p ~/wordpress-images/{nginx,php-fpm,wordpress-exporter}
```

**Nginx Dockerfile:**

```dockerfile
# ~/wordpress-images/nginx/Dockerfile
FROM nginx:alpine

# Install additional tools
RUN apk add --no-cache \
    curl \
    wget

# Copy optimized nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf
COPY wordpress.conf /etc/nginx/conf.d/default.conf

# Health check script
COPY healthcheck.sh /healthcheck.sh
RUN chmod +x /healthcheck.sh

HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
    CMD /healthcheck.sh

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
```

**PHP-FPM Dockerfile:**

```dockerfile
# ~/wordpress-images/php-fpm/Dockerfile
FROM php:8.2-fpm-alpine

# Install dependencies
RUN apk add --no-cache \
    freetype-dev \
    libjpeg-turbo-dev \
    libpng-dev \
    libwebp-dev \
    libzip-dev \
    icu-dev \
    imagemagick-dev \
    $PHPIZE_DEPS

# Install PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j$(nproc) \
        gd \
        mysqli \
        pdo_mysql \
        zip \
        intl \
        opcache \
        exif \
        bcmath

# Install PECL extensions
RUN pecl install redis-5.3.7 imagick-3.7.0 apcu-5.1.22 \
    && docker-php-ext-enable redis imagick apcu

# Install WP-CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# Copy PHP configuration
COPY php.ini /usr/local/etc/php/conf.d/custom.ini
COPY php-fpm.conf /usr/local/etc/php-fpm.d/www.conf
COPY opcache.ini /usr/local/etc/php/conf.d/opcache.ini

# Copy WordPress
COPY --from=wordpress:latest /usr/src/wordpress /var/www/html

# Set permissions
RUN chown -R www-data:www-data /var/www/html

# Health check
COPY php-fpm-healthcheck /usr/local/bin/php-fpm-healthcheck
RUN chmod +x /usr/local/bin/php-fpm-healthcheck

HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 \
    CMD php-fpm-healthcheck

USER www-data

EXPOSE 9000

CMD ["php-fpm"]
```

**Build and push images:**

```bash
cd ~/wordpress-images

# Build
docker build -t registry.yourdomain.com/nginx-wordpress:latest nginx/
docker build -t registry.yourdomain.com/wordpress-fpm:8.2 php-fpm/

# Push to private registry
docker push registry.yourdomain.com/nginx-wordpress:latest
docker push registry.yourdomain.com/wordpress-fpm:8.2
```

### Step 13: Create Site Provisioning Script

```bash
cat > /usr/local/bin/provision-wordpress-site <<'EOF'
#!/bin/bash
# provision-wordpress-site - Automate WordPress site deployment

set -e

# Usage check
if [ $# -lt 2 ]; then
    echo "Usage: $0 <domain> <site-id>"
    echo "Example: $0 example.com 001"
    exit 1
fi

DOMAIN=$1
SITE_ID=$2
STACK_NAME="wp-site-$SITE_ID"

echo "Provisioning WordPress site: $DOMAIN (ID: $SITE_ID)"

# Generate database credentials
DB_NAME="wp_site_$SITE_ID"
DB_USER="wp_user_$SITE_ID"
DB_PASS=$(openssl rand -base64 24)

# Generate WordPress keys
WP_AUTH_KEY=$(openssl rand -base64 64)
WP_SECURE_AUTH_KEY=$(openssl rand -base64 64)
WP_LOGGED_IN_KEY=$(openssl rand -base64 64)
WP_NONCE_KEY=$(openssl rand -base64 64)
WP_AUTH_SALT=$(openssl rand -base64 64)
WP_SECURE_AUTH_SALT=$(openssl rand -base64 64)
WP_LOGGED_IN_SALT=$(openssl rand -base64 64)
WP_NONCE_SALT=$(openssl rand -base64 64)

# Create Docker secrets
echo "$DB_PASS" | docker secret create db_password_site_$SITE_ID -
echo "$WP_AUTH_KEY" | docker secret create wp_auth_key_$SITE_ID -
echo "$WP_SECURE_AUTH_KEY" | docker secret create wp_secure_auth_key_$SITE_ID -
echo "$WP_LOGGED_IN_KEY" | docker secret create wp_logged_in_key_$SITE_ID -
echo "$WP_NONCE_KEY" | docker secret create wp_nonce_key_$SITE_ID -
echo "$WP_AUTH_SALT" | docker secret create wp_auth_salt_$SITE_ID -
echo "$WP_SECURE_AUTH_SALT" | docker secret create wp_secure_auth_salt_$SITE_ID -
echo "$WP_LOGGED_IN_SALT" | docker secret create wp_logged_in_salt_$SITE_ID -
echo "$WP_NONCE_SALT" | docker secret create wp_nonce_salt_$SITE_ID -

# Create database
docker exec $(docker ps -qf "name=database_proxysql") mysql -h galera-1 -uroot -p$MYSQL_ROOT_PASSWORD <<EOSQL
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'%';
FLUSH PRIVILEGES;
EOSQL

# Create stack file from template
sed -e "s/{SITE_ID}/$SITE_ID/g" -e "s/{DOMAIN}/$DOMAIN/g" \
    /var/opt/stacks/wordpress-site-template.yml > /tmp/$STACK_NAME.yml

# Deploy stack
docker stack deploy -c /tmp/$STACK_NAME.yml $STACK_NAME
rm /tmp/$STACK_NAME.yml

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 30

# Configure DNS via Cloudflare
curl -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"$DOMAIN\",\"content\":\"$FLOATING_IP\",\"proxied\":true}"

# Wait for SSL certificate
echo "Waiting for SSL certificate..."
sleep 60

# Initialize WordPress
CONTAINER=$(docker ps -qf "name=${STACK_NAME}_php-fpm")
docker exec $CONTAINER wp core install \
    --url="https://$DOMAIN" \
    --title="$DOMAIN" \
    --admin_user="admin" \
    --admin_email="admin@$DOMAIN" \
    --skip-email \
    --allow-root

echo "✅ Site provisioned successfully!"
echo "Domain: https://$DOMAIN"
echo "Database: $DB_NAME"
echo "Admin: https://$DOMAIN/wp-admin"
echo "Credentials saved in Portainer secrets"
EOF

chmod +x /usr/local/bin/provision-wordpress-site
```

### Step 14: Deploy First WordPress Sites

```bash
# Provision test sites
provision-wordpress-site demo1.yourdomain.com 001
provision-wordpress-site demo2.yourdomain.com 002
provision-wordpress-site demo3.yourdomain.com 003

# Verify sites are running
docker stack ls
docker service ls | grep wp-site
```

---

## Phase 5: Monitoring & Testing (Week 5-6)

### Step 15: Configure Grafana Dashboards

1. Access Grafana at `https://grafana.yourdomain.com`
2. Login with admin credentials
3. Import community dashboards:
   - Node Exporter Full (ID: 1860)
   - Docker Swarm (ID: 3888)
   - Traefik (ID: 11462)
   - MySQL Overview (ID: 7362)
4. Create custom WordPress dashboard

### Step 16: Load Testing

```bash
# Install k6 for load testing
docker run --rm -i grafana/k6 run - <<EOF
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
    stages: [
        { duration: '2m', target: 100 },
        { duration: '5m', target: 100 },
        { duration: '2m', target: 200 },
        { duration: '5m', target: 200 },
        { duration: '2m', target: 0 },
    ],
    thresholds: {
        http_req_duration: ['p(99)<1500'],
        http_req_failed: ['rate<0.01'],
    },
};

export default function () {
    let response = http.get('https://demo1.yourdomain.com');
    check(response, { 'status was 200': (r) => r.status == 200 });
    sleep(1);
}
EOF
```

---

## Phase 6: Production Migration (Week 7-12)

### Step 17: Migrate Existing Sites

```bash
# For each existing WordPress site:

# 1. Backup current site
# 2. Provision new site on cluster
provision-wordpress-site existing-site.com 050

# 3. Import database
docker exec -i $(docker ps -qf "name=database_proxysql") \
    mysql -h galera-1 -uwp_user_050 -p wp_site_050 < backup.sql

# 4. Sync files
rsync -avz --progress /old-site/wp-content/uploads/ \
    /mnt/glusterfs/wp-050/uploads/

# 5. Update DNS to point to new cluster
# 6. Verify site functionality
# 7. Monitor for 24 hours before decommissioning old server
```

---

## Maintenance & Operations

### Daily Tasks (Automated)

- Backups run automatically
- Monitoring alerts sent to Slack/email
- Certificate renewal handled by Traefik

### Weekly Tasks

- Review Grafana dashboards
- Check for security updates
- Review error logs in Loki

### Monthly Tasks

- Review capacity planning
- Test disaster recovery procedures
- Review and update documentation
- Security audit

### Scaling Operations

**Add Worker Node:**

```bash
# Provision new DO droplet
doctl compute droplet create wp-worker-7 \
    --region $DO_REGION \
    --size $DO_SIZE \
    --image ubuntu-22-04-x64 \
    --ssh-keys $SSH_FINGERPRINT \
    --enable-private-networking

# Initialize node
ssh wp-worker-7 'bash -s' < init-node.sh

# Join swarm
ssh wp-worker-7 docker swarm join --token $WORKER_TOKEN $MANAGER_IP:2377

# Services will automatically rebalance
```

**Add Database Node (Galera):**

```bash
# Add node to cluster
ssh wp-db-4 docker swarm join --token $WORKER_TOKEN $MANAGER_IP:2377

# Deploy additional Galera node
# Update database-stack.yml with galera-4 configuration
docker stack deploy -c database-stack.yml database
```

---

## Disaster Recovery Procedures

### Scenario 1: Single Site Failure

```bash
# Identify failed site
SITE_ID=050

# Check service status
docker service ps wp-site-${SITE_ID}_php-fpm

# Restart service
docker service update --force wp-site-${SITE_ID}_php-fpm

# If persistent issues, restore from backup
./restore-site.sh $SITE_ID
```

### Scenario 2: Database Cluster Failure

```bash
# Bootstrap Galera cluster from most recent node
docker exec -it database_galera-1 /bin/bash
mysqld --wsrep-new-cluster

# Restart other nodes
docker service update --force database_galera-2
docker service update --force database_galera-3
```

### Scenario 3: Complete Region Outage

```bash
# Restore from backups in different region
# 1. Provision new cluster in different region
# 2. Restore database backups from S3
# 3. Restore file backups from S3
# 4. Update DNS to point to new cluster
# 5. Verify all sites operational
```

---

## Conclusion

This implementation guide provides a complete roadmap for deploying a production-ready WordPress hosting farm. Follow each phase systematically, testing thoroughly at each step before proceeding to the next.

**Key Success Metrics:**
- 99.9% uptime
- Page load times < 2 seconds
- Zero data loss
- Automated recovery from failures
- Scalable to 1000+ sites

**Next Steps:**
1. Complete Phase 1-3 for core infrastructure
2. Deploy pilot sites in Phase 4
3. Monitor and optimize in Phase 5
4. Migrate production sites in Phase 6
5. Establish operational procedures

Good luck building your WordPress empire! 🚀


