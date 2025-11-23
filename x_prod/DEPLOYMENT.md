# Production Deployment Guide

This guide covers deploying the microservices system to a Debian-based VPS.

## Initial Server Setup

### 1. Connect to Your VPS

```bash
ssh root@YOUR_VPS_IP
```

### 2. Update System Packages

```bash
apt update && apt upgrade -y
```

### 3. Install Docker and Docker Compose

```bash
# Install dependencies
apt install -y ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up the repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Verify installation
docker --version
docker compose version
```

### 4. Enable and Start Docker

```bash
systemctl enable docker
systemctl start docker
systemctl status docker
```

### 5. Create a Deployment User (Optional but Recommended)

```bash
# Create user
useradd -m -s /bin/bash deploy
usermod -aG docker deploy

# Set password
passwd deploy

# Add sudo privileges (optional)
usermod -aG sudo deploy
```

---

## Security Configuration

### 1. Configure Firewall (UFW)

```bash
# Install UFW if not present
apt install -y ufw

# Allow SSH (IMPORTANT: Do this first!)
ufw allow 22/tcp

# Allow HTTP/HTTPS
ufw allow 80/tcp
ufw allow 443/tcp

# Allow development port (optional, for testing)
ufw allow 8080/tcp

# Enable firewall
ufw enable

# Check status
ufw status
```

### 2. Generate Secure Secrets

```bash
# Generate passwords and secrets
openssl rand -base64 32  # For LIVEBOOK_PASSWORD
openssl rand -base64 64  # For LIVEBOOK_SECRET_KEY_BASE
openssl rand -base64 32  # For ERL_COOKIE
openssl rand -base64 32  # For MINIO_ROOT_PASSWORD
openssl rand -base64 32  # For Grafana admin password
```

**Save these secrets securely!** You'll need them for the `.env.staging` file.

---

## Deployment Steps

### 1. Clone Your Repository

```bash
# Switch to deploy user (if created)
su - deploy

# Clone the repository
cd ~
git clone https://github.com/YOUR_USERNAME/msvc.git
cd msvc
```

### 2. Configure Environment Variables

```bash
# Copy production environment template
cp .env.production .env.staging

# Edit with your secure values
nano .env.staging
```

**Replace these values in `.env.staging`:**

```bash
# CRITICAL: Change these!
LIVEBOOK_PASSWORD=your_secure_password_here
LIVEBOOK_SECRET_KEY_BASE=your_secret_key_base_here
ERL_COOKIE=your_erlang_cookie_here
RELEASE_COOKIE=your_erlang_cookie_here

MINIO_ROOT_USER=minio_admin
MINIO_ROOT_PASSWORD=your_minio_password_here

GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=your_grafana_password_here

# Security: Disable anonymous access
GF_AUTH_ANONYMOUS_ENABLED=false
GF_AUTH_DISABLE_LOGIN_FORM=false
```

### 3. Configure Caddyfile (Optional: For Custom Domain)

If you have a domain, update the Caddyfile:

```bash
# Option 1: Use production Caddyfile template
cp Caddyfile.prod Caddyfile

# Option 2: Edit existing Caddyfile
nano Caddyfile
```

Replace `:8080` with your domain:

```caddy
# Before
:8080 {
    reverse_proxy livebook:8090
}

# After (with your domain)
myapp.example.com {
    reverse_proxy livebook:8090
}
```

**If you don't have a domain yet**, keep the default `:8080` and access via:
```
http://YOUR_VPS_IP:8080
```

### 4. Build and Start Services

```bash
# Build images (first time only)
docker compose -f docker-compose-prod.yml build

# Start all services
docker compose -f docker-compose-prod.yml up -d

# Check service status
docker compose -f docker-compose-prod.yml ps

# View logs
docker compose -f docker-compose-prod.yml logs -f
```

### 5. Verify Services Are Running

```bash
# Check all containers are healthy
docker ps

# You should see containers like:
# - msvc-caddy
# - msvc-nats-server
# - msvc-user-svc
# - msvc-client-svc
# - msvc-image-svc-1
# - msvc-image-svc-2
# - msvc-email-svc
# - msvc-minio
# - msvc-jaeger
# - msvc-grafana
# - msvc-prometheus
# - msvc-loki
```

---

## Domain Configuration

### Option A: Using IP Address (No Domain)

Access your services via:
- **Livebook**: `http://YOUR_VPS_IP:8080`
- **Grafana**: `http://grafana.localhost:8080` (won't work remotely, port forward or use IP)
- **Jaeger**: `http://YOUR_VPS_IP:16686`
- **MinIO Console**: `http://YOUR_VPS_IP:9001`

### Option B: Using a Domain Name

#### 1. DNS Configuration

Create these DNS A records pointing to your VPS IP:

```txt
A     myapp.example.com      → YOUR_VPS_IP
A     grafana.example.com    → YOUR_VPS_IP
A     jaeger.example.com     → YOUR_VPS_IP
A     minio.example.com      → YOUR_VPS_IP
```

#### 2. Update Caddyfile

Edit `Caddyfile`:

```caddy
# Main app
myapp.example.com {
    reverse_proxy livebook:8090
    header {
        -X-Frame-Options
        Content-Security-Policy "frame-ancestors *"
    }
}

# Grafana
grafana.example.com {
    reverse_proxy grafana:3000
}

# Jaeger
jaeger.example.com {
    reverse_proxy jaeger:16686
}

# MinIO Console
minio.example.com {
    reverse_proxy minio:9001
}
```

#### 3. Restart Caddy

```bash
docker compose -f docker-compose-prod.yml restart caddy
```

#### 4. Verify SSL Certificates

Caddy will automatically obtain Let's Encrypt certificates. Check logs:

```bash
docker compose -f docker-compose-prod.yml logs caddy
```

You should see: `certificate obtained successfully`

---

## Post-Deployment

### 1. Test the System

Access Livebook and run test code:

```elixir
# Send a test email
Email.create(1, :welcome)

# Convert a test image
Image.convert_png("test.png", "user@example.com")
```

### 2. Monitor Services

Access observability dashboards:

- **Grafana**: `http://grafana.example.com` (or `http://YOUR_VPS_IP:3000`)
- **Jaeger**: `http://jaeger.example.com` (or `http://YOUR_VPS_IP:16686`)
- **Prometheus**: `http://prometheus.example.com` (or `http://YOUR_VPS_IP:9090`)

### 3. Verify Load Balancing

Check that both image service instances are running:

```bash
docker compose -f docker-compose-prod.yml logs -f image_svc_1
docker compose -f docker-compose-prod.yml logs -f image_svc_2
```

You should see messages distributed between both instances.

### 4. Check MinIO Storage

Access MinIO Console:
- URL: `http://minio.example.com` or `http://YOUR_VPS_IP:9001`
- Login with credentials from `.env.staging`

Verify buckets exist:
- `msvc-images`
- `loki-chunks`
- `tempo-traces`

---

## Maintenance

### Update the Application

```bash
cd ~/msvc

# Pull latest changes
git pull origin main

# Rebuild and restart
docker compose -f docker-compose-prod.yml build
docker compose -f docker-compose-prod.yml up -d

# Check logs for errors
docker compose -f docker-compose-prod.yml logs -f
```

### View Logs

```bash
# All services
docker compose -f docker-compose-prod.yml logs -f

# Specific service
docker compose -f docker-compose-prod.yml logs -f user_svc
docker compose -f docker-compose-prod.yml logs -f image_svc_1

# Last 100 lines
docker compose -f docker-compose-prod.yml logs --tail=100 -f
```

### Backup Data

```bash
# Backup volumes
docker run --rm \
  -v msvc_minio-data:/data \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/minio-backup-$(date +%Y%m%d).tar.gz /data

docker run --rm \
  -v msvc_grafana-data:/data \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/grafana-backup-$(date +%Y%m%d).tar.gz /data
```

### Restart Services

```bash
# Restart all
docker compose -f docker-compose-prod.yml restart

# Restart specific service
docker compose -f docker-compose-prod.yml restart user_svc

# Stop all
docker compose -f docker-compose-prod.yml stop

# Start all
docker compose -f docker-compose-prod.yml start
```

### Scale Image Service

To add more image processing capacity:

```bash
# Edit docker-compose-prod.yml and add image_svc_3
# Then restart
docker compose -f docker-compose-prod.yml up -d
```

---

## Troubleshooting

### Services Not Starting

```bash
# Check service status
docker compose -f docker-compose-prod.yml ps

# View logs for failed service
docker compose -f docker-compose-prod.yml logs <service-name>

# Common issues:
# 1. Port already in use - check with: lsof -i :8080
# 2. Memory limit - check: docker stats
# 3. Disk full - check: df -h
```

### Cannot Connect to Services

```bash
# Check firewall
ufw status

# Check if ports are listening
netstat -tulpn | grep LISTEN

# Check Docker networks
docker network ls
docker network inspect msvc_msvc
```

### SSL Certificate Issues (Caddy)

```bash
# Check Caddy logs
docker compose -f docker-compose-prod.yml logs caddy

# Verify DNS points to your server
dig myapp.example.com

# Force certificate renewal
docker compose -f docker-compose-prod.yml exec caddy caddy reload --config /etc/caddy/Caddyfile
```

### High Memory Usage

```bash
# Check resource usage
docker stats

# Restart heavy services
docker compose -f docker-compose-prod.yml restart image_svc_1 image_svc_2

# Adjust resource limits in docker-compose-prod.yml
```

### Database/Storage Issues

```bash
# Check MinIO health
docker compose -f docker-compose-prod.yml exec minio curl http://localhost:9000/minio/health/live

# List volumes
docker volume ls

# Inspect volume
docker volume inspect msvc_minio-data
```

### NATS Connection Issues

```bash
# Check NATS server
docker compose -f docker-compose-prod.yml logs nats-server

# Access NATS monitoring
curl http://localhost:8222/varz

# Restart NATS
docker compose -f docker-compose-prod.yml restart nats-server
```

---

## Performance Optimization

### Adjust Resource Limits

Edit `docker-compose-prod.yml` and modify resource limits based on your server:

```yaml
deploy:
  resources:
    limits:
      cpus: '2.0'      # Increase for more CPU
      memory: 4G       # Increase for more RAM
```

### Enable Trace Sampling

For high-traffic systems, enable sampling in `.env.staging`:

```bash
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1  # Sample 10% of traces
```

### Configure Log Rotation

```bash
# Create logrotate config
sudo nano /etc/logrotate.d/docker-containers

# Add:
/var/lib/docker/containers/*/*.log {
  daily
  rotate 7
  compress
  delaycompress
  missingok
  notifempty
}
```
