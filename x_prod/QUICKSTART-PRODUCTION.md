# Quick Start - Production Deployment

Deploy your microservices system to a VPS.

## Prerequisites

- Debian/Ubuntu VPS with 4+ CPU cores, 8GB+ RAM
- SSH access to your VPS
- (Optional) Domain name pointing to your VPS IP

## 1: Fork and Prepare

On your **local machine**:

```bash
# Fork the repository on GitHub
# Then clone your fork
git clone https://github.com/YOUR_USERNAME/msvc.git
cd msvc
```

## 2: Setup VPS

Connect to your VPS:

```bash
ssh root@YOUR_VPS_IP
```

Install Docker:

```bash
# Update system
apt update && apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Verify installation
docker --version
docker compose version
```

Configure firewall:

```bash
apt install -y ufw
ufw allow 22/tcp   # SSH
ufw allow 80/tcp   # HTTP
ufw allow 443/tcp  # HTTPS
ufw allow 8080/tcp # Development port
ufw enable
```

## 3: Deploy Application

Clone your repository on the VPS:

```bash
cd ~
git clone https://github.com/YOUR_USERNAME/msvc.git
cd msvc
```

Run setup:

```bash
./deploy.sh setup
```

This creates `.env.staging` from the template. Now edit it:

```bash
nano .env.staging
```

**Generate secure passwords:**

```bash
# Generate passwords (run these on your VPS)
echo "LIVEBOOK_PASSWORD=$(openssl rand -base64 32)"
echo "LIVEBOOK_SECRET_KEY_BASE=$(openssl rand -base64 64)"
echo "ERL_COOKIE=$(openssl rand -base64 32)"
echo "MINIO_ROOT_PASSWORD=$(openssl rand -base64 32)"
echo "GF_SECURITY_ADMIN_PASSWORD=$(openssl rand -base64 32)"
```

Copy the output and paste into `.env.staging`, replacing all `CHANGE_ME` values.

**Important security settings to change:**

```bash
# In .env.staging, change these:
LIVEBOOK_PASSWORD=your_generated_password_here
LIVEBOOK_SECRET_KEY_BASE=your_generated_secret_key_here
ERL_COOKIE=your_generated_cookie_here
RELEASE_COOKIE=your_generated_cookie_here

MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=your_generated_password_here

# Disable anonymous Grafana access
GF_AUTH_ANONYMOUS_ENABLED=false
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=your_generated_password_here
```

Save and exit (Ctrl+X, Y, Enter).

## 4: Start Services

```bash
./deploy.sh build   # Build images (takes 5-10 minutes)
./deploy.sh start   # Start all services
```

Check status:

```bash
./deploy.sh status
```

## 5: Access Your Services

**Without domain (using IP):**

- **Livebook**: `http://YOUR_VPS_IP:8080`
- **Grafana**: `http://YOUR_VPS_IP:3000`
- **Jaeger**: `http://YOUR_VPS_IP:16686`
- **MinIO Console**: `http://YOUR_VPS_IP:9001`

**With domain (optional):**

1. Create DNS A records pointing to your VPS:
   - `myapp.example.com` → YOUR_VPS_IP
   - `grafana.example.com` → YOUR_VPS_IP
   - `jaeger.example.com` → YOUR_VPS_IP

2. Update Caddyfile:

```bash
cp Caddyfile.prod Caddyfile
nano Caddyfile
```

Replace `example.com` with your actual domain, then restart:

```bash
./deploy.sh restart caddy
```

Caddy will automatically obtain Let's Encrypt SSL certificates!

## 6: Test the System

Access Livebook at `http://YOUR_VPS_IP:8080` and run:

```elixir
# Send test email
Email.create(1, :welcome)

# Convert test image
Image.convert_png("priv/test.png", "user@com")
```

Check traces in Jaeger: `http://YOUR_VPS_IP:16686`

Check metrics in Grafana: `http://YOUR_VPS_IP:3000`

## Common Commands

```bash
# View logs
./deploy.sh logs

# View logs for specific service
./deploy.sh logs user_svc
./deploy.sh logs image_svc_1

# Check health
./deploy.sh health

# Restart services
./deploy.sh restart

# Stop services
./deploy.sh stop

# Update to latest version
git pull
./deploy.sh update

# Create backups
./deploy.sh backup
```

## Troubleshooting

**Services won't start:**

```bash
# Check logs
./deploy.sh logs

# Check disk space
df -h

# Check memory
free -h

# Restart specific service
docker compose -f docker-compose-prod.yml restart user_svc
```

**Can't access services:**

```bash
# Check firewall
ufw status

# Check if ports are open
netstat -tulpn | grep LISTEN

# Check Docker networks
docker network ls
```

**Out of memory:**

```bash
# Check resource usage
docker stats

# Edit resource limits in docker-compose-prod.yml
nano docker-compose-prod.yml

# Restart
./deploy.sh restart
```

## Load balancing

The system automatically load balances image processing across 2 instances:

```bash
# Monitor both instances
docker compose -f docker-compose-prod.yml logs -f image_svc_1 image_svc_2
```

You'll see messages distributed between `image_svc_1` and `image_svc_2`.
