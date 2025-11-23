# Production Deployment - Summary


## Production Docker Compose File

- **2 Image Service instances** for load balancing (image_svc_1, image_svc_2)
- **Resource limits** for all services (CPU and memory)
- **Restart policies** (`unless-stopped` for all services)
- **Health checks** with proper start periods
- **Optimized resource allocation**:
  - Image services: 2 CPU cores, 2GB RAM (high CPU for image processing)
  - NATS: 1 CPU core, 2GB RAM (message broker)
  - Other services: 0.5-1 CPU cores, 512MB-1GB RAM
- **Persistent volumes** for data retention
   **Production-ready settings** (30-day Prometheus retention, proper timeouts)

## Environment Configuration

**File**: `.env.production` (template)

Contains:

- Secure password placeholders (all marked as `CHANGE_ME`)
- Production-optimized settings
- Detailed comments explaining each variable
- Security warnings for critical values
- Grafana authentication enabled (disabled anonymous access)

## Production Caddyfile

**File**: `Caddyfile.prod`

Features:

- HTTP and HTTPS support
- Automatic Let's Encrypt SSL certificates
- Subdomain routing for observability tools
- Both domain and localhost configurations
- Ready-to-use templates (just replace `example.com`)

## Deployment Script

**File**: `deploy.sh` (executable)

Commands:

- `setup` - Initial environment setup
- `build` - Build Docker images
- `start` - Start all services
- `stop` - Stop all services
- `restart` - Restart services
- `logs` - View logs (all or specific service)
- `status` - Show service status and URLs
- `update` - Pull latest code and rebuild
- `backup` - Backup volumes (MinIO, Grafana, NATS)
- `health` - Check health of all services

Safety features:

- Validates `.env.staging` exists
- Checks for default passwords (prevents deployment with CHANGE_ME)
- Color-coded output (errors in red, info in green)
- Confirmation prompts for destructive actions

## Deployment Workflow

### Initial Deployment

```bash
# On your VPS
git clone https://github.com/YOUR_USERNAME/msvc.git
cd msvc

# Setup environment
./deploy.sh setup

# Edit .env.staging (replace all CHANGE_ME values)
nano .env.staging

# Build and start
./deploy.sh build
./deploy.sh start
```

### Operations

```bash
# Check status
./deploy.sh status

# View logs
./deploy.sh logs
./deploy.sh logs image_svc_1

# Check health
./deploy.sh health

# Restart a service
docker compose -f docker-compose-prod.yml restart user_svc
```

### Updates

```bash
git pull
./deploy.sh update
```

### Backups

```bash
./deploy.sh backup
# Creates timestamped backups in ./backups/
```

## Security Considerations

### What is secured

1. **Passwords**: Template requires secure passwords (validated by deploy.sh)
2. **Grafana**: Anonymous access disabled, admin auth required
3. **MinIO**: Custom admin credentials required
4. **Livebook**: Password protection with secure key base
5. **Erlang cookies**: Unique per deployment
6. **Firewall**: UFW configuration documented
7. **HTTPS**: Automatic SSL via Caddy + Let's Encrypt
8. **Resource limits**: Prevents DoS via resource exhaustion

### What You Need to Configure

1. **Change all passwords** in `.env.staging`
2. **Configure firewall** on VPS (UFW commands in DEPLOYMENT.md)
3. **Set up HTTPS** (if using a domain)
4. **No SMTP setup**
5. **Enable NATS authentication** for production (currently disabled for simplicity)
6. **Set up monitoring alerts** in Grafana
7. **Configure log rotation** (logrotate recommended)
8. **Regular backups** (use `./deploy.sh backup` or set up cron)

## Load Balancing Verification

```bash
# Start load test in Livebook
Task.async_stream(1..100, fn i ->
  Image.convert_png("test.png", "user#{i}@example.com")
end) |> Stream.run()

# Monitor both instances
./deploy.sh logs image_svc_1
./deploy.sh logs image_svc_2
```

## Access URLs

### Without Domain (IP-based)

Replace `YOUR_VPS_IP` with your server's IP:

- Livebook: `http://YOUR_VPS_IP:8080`
- Grafana: `http://YOUR_VPS_IP:3000`
- Jaeger: `http://YOUR_VPS_IP:16686`
- Prometheus: `http://YOUR_VPS_IP:9090`
- MinIO: `http://YOUR_VPS_IP:9001`

### With Domain (DNS configured)

Example with `example.com`:

- Livebook: `https://myapp.example.com`
- Grafana: `https://grafana.example.com`
- Jaeger: `https://jaeger.example.com`
- MinIO: `https://minio.example.com`

## Resource Requirements

### Resource Allocation (from docker-compose-prod.yml)

| Service        | CPU Limit | Memory Limit | Notes                            |
| -------------- | --------- | ------------ | -------------------------------- |
| image_svc_1    | 2.0       | 2GB          | Image processing (CPU-intensive) |
| image_svc_2    | 2.0       | 2GB          | Image processing (CPU-intensive) |
| nats-server    | 1.0       | 2GB          | Message broker                   |
| minio          | 1.0       | 2GB          | Object storage                   |
| prometheus     | 1.0       | 2GB          | Metrics storage                  |
| grafana        | 1.0       | 1GB          | Dashboards                       |
| Other services | 0.5-1.0   | 512MB-1GB    | Standard services                |

**Total**: ~8 CPU cores, ~14GB RAM

## Observability Stack

All services include:

- **Distributed Tracing** → Jaeger (visual request flows)
- **Metrics** → Prometheus + PromEx (performance data)
- **Logs** → Loki + Promtail (centralized logging)
- **Dashboards** → Grafana (unified visualization)

### Pre-configured Dashboards

Access Grafana → Dashboards:

- Application metrics (uptime, dependencies)
- BEAM VM metrics (processes, memory)
- Broadway pipelines (throughput, latency)
- Phoenix (HTTP requests, response times)
- Custom metrics (OS, NATS, image conversion)

## Monitoring and Alerts

### Set Up Alerts in Grafana

1. Go to Grafana → Alerting → Alert Rules
2. Create alerts for:
   - Service down (health check failed)
   - High CPU (>80% for 5min)
   - High memory (>90%)
   - Disk space low (<10%)
   - NATS queue buildup (>1000 messages)

3. Configure notifications:
   - Email
   - Slack
   - PagerDuty

## Backup Strategy

### Automated Backups

Create a cron job:

```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM
0 2 * * * cd /path/to/msvc && ./deploy.sh backup
```

### What Gets Backed Up

- MinIO data (images, PDFs)
- Grafana dashboards and settings
- NATS JetStream data (message streams)
- Prometheus metrics (via retention settings)

### Restore from Backup

```bash
# Stop services
./deploy.sh stop

# Restore MinIO data
docker run --rm \
  -v msvc_minio-data:/data \
  -v $(pwd)/backups:/backup \
  alpine tar xzf /backup/minio-20250322_020000.tar.gz -C /

# Restart
./deploy.sh start
```
