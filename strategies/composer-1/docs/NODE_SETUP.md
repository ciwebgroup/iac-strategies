# Node Setup Guide

## Digital Ocean VPS Configuration

### Initial Server Setup

#### 1. Update System

```bash
apt update && apt upgrade -y
```

#### 2. Install Docker

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Install Docker Compose
apt install docker-compose-plugin -y

# Add user to docker group
usermod -aG docker $USER
```

#### 3. Configure Firewall

```bash
# Install UFW
apt install ufw -y

# Allow SSH
ufw allow 22/tcp

# Allow HTTP/HTTPS
ufw allow 80/tcp
ufw allow 443/tcp

# Allow Docker Swarm ports
ufw allow 2377/tcp
ufw allow 7946/tcp
ufw allow 7946/udp
ufw allow 4789/udp

# Enable firewall
ufw enable
```

#### 4. Configure Swap (if needed)

```bash
# Create swap file (8GB)
fallocate -l 8G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# Make permanent
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

#### 5. Optimize System Limits

```bash
# Edit /etc/security/limits.conf
cat >> /etc/security/limits.conf << EOF
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
EOF

# Edit /etc/sysctl.conf
cat >> /etc/sysctl.conf << EOF
# Network optimizations
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30

# Memory optimizations
vm.swappiness = 10
vm.dirty_ratio = 60
vm.dirty_background_ratio = 2

# File system optimizations
fs.file-max = 2097152
EOF

sysctl -p
```

#### 6. Install Monitoring Tools

```bash
# Install htop, iotop, netstat
apt install htop iotop net-tools -y
```

### Docker Swarm Setup

#### Initialize Swarm (First Node)

```bash
docker swarm init --advertise-addr $(hostname -I | awk '{print $1}')
```

#### Join Swarm (Other Nodes)

```bash
# Get join token from manager
docker swarm join-token worker

# On worker node, run the provided command
docker swarm join --token <TOKEN> <MANAGER_IP>:2377
```

#### Label Nodes

```bash
# Label database nodes
docker node update --label-add role=database <NODE_ID>

# Label application nodes
docker node update --label-add role=application <NODE_ID>

# Label monitoring nodes
docker node update --label-add role=monitoring <NODE_ID>
```

### Storage Setup

#### NFS Server (One Node)

```bash
# Install NFS server
apt install nfs-kernel-server -y

# Create export directory
mkdir -p /var/nfs/wordpress
chown nobody:nogroup /var/nfs/wordpress

# Configure exports
cat >> /etc/exports << EOF
/var/nfs/wordpress *(rw,sync,no_subtree_check,no_root_squash)
EOF

# Start NFS
systemctl enable nfs-kernel-server
systemctl start nfs-kernel-server
```

#### NFS Client (All Nodes)

```bash
# Install NFS client
apt install nfs-common -y

# Test mount
mount -t nfs <NFS_SERVER_IP>:/var/nfs/wordpress /mnt/test
umount /mnt/test
```

### Network Configuration

#### Create Docker Networks

```bash
docker network create --driver overlay --attachable web
docker network create --driver overlay --attachable wordpress
docker network create --driver overlay --attachable database
docker network create --driver overlay --attachable caching
docker network create --driver overlay --attachable monitoring
docker network create --driver overlay --attachable management
```

### SSL Certificate Setup

#### Let's Encrypt via Traefik

Traefik will automatically handle SSL certificates via Let's Encrypt. Ensure:
- Ports 80 and 443 are open
- DNS records point to your nodes
- Email configured in Traefik config

### Cloudflare Configuration

#### DNS Setup

1. Add A records pointing to Traefik nodes
2. Enable Proxy (orange cloud) for DDoS protection
3. Configure SSL/TLS mode: Full (strict)
4. Enable Always Use HTTPS
5. Configure Page Rules for caching

#### WAF Rules

1. Enable Cloudflare WAF
2. Configure custom rules:
   - Block XML-RPC attacks
   - Rate limit login attempts
   - Block known bad IPs

### Security Hardening

#### SSH Configuration

```bash
# Edit /etc/ssh/sshd_config
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
Port 2222  # Change default port

# Restart SSH
systemctl restart sshd
```

#### Fail2ban Setup

```bash
# Install Fail2ban
apt install fail2ban -y

# Copy configuration
cp security/fail2ban/jail.local /etc/fail2ban/jail.local
cp security/fail2ban/filter.d/*.conf /etc/fail2ban/filter.d/

# Start Fail2ban
systemctl enable fail2ban
systemctl start fail2ban
```

### Performance Tuning

#### Kernel Parameters

```bash
# Edit /etc/sysctl.conf (already done above)
# Apply changes
sysctl -p
```

#### Docker Daemon Configuration

```bash
# Edit /etc/docker/daemon.json
cat > /etc/docker/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "default-address-pools": [
    {
      "base": "172.17.0.0/16",
      "size": 24
    }
  ]
}
EOF

systemctl restart docker
```

### Monitoring Setup

#### Install node-exporter (if not using container)

```bash
# Download node-exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.6.1/node_exporter-1.6.1.linux-amd64.tar.gz
tar xvfz node_exporter-1.6.1.linux-amd64.tar.gz
sudo mv node_exporter-1.6.1.linux-amd64/node_exporter /usr/local/bin/

# Create systemd service
cat > /etc/systemd/system/node-exporter.service << EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=nobody
Group=nogroup
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

systemctl enable node-exporter
systemctl start node-exporter
```

### Backup Node Setup

#### Install Backup Tools

```bash
# Install MinIO client
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
mv mc /usr/local/bin/

# Install mysqldump (if not already installed)
apt install mysql-client -y
```

### Verification

#### Check Docker

```bash
docker info
docker node ls
```

#### Check Networks

```bash
docker network ls
```

#### Check Services

```bash
docker service ls
docker service ps <service-name>
```

#### Check Logs

```bash
docker service logs <service-name>
journalctl -u docker
```

### Troubleshooting

#### Common Issues

1. **Swarm join fails**: Check firewall rules and network connectivity
2. **Services not starting**: Check node labels and constraints
3. **Network issues**: Verify overlay networks are created
4. **Storage issues**: Check NFS mount and permissions

#### Useful Commands

```bash
# Check node status
docker node inspect <NODE_ID>

# Check service logs
docker service logs -f <SERVICE_NAME>

# Check network connectivity
docker exec <CONTAINER> ping <TARGET>

# Check resource usage
docker stats

# Check disk usage
df -h
du -sh /var/lib/docker/*
```


