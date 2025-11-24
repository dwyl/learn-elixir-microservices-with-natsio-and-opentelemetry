# Services Quick Reference

## Microservices (from host)

All services accessible at `http://localhost:<port>`:

| Service        | Port | Health Check | Description        |
| -------------- | ---- | ------------ | ------------------ |
| **user_svc**   | 8081 | `/health`    | User management    |
| **email_svc**  | 8083 | `/health`    | Email service      |
| **image_svc**  | 8084 | `/health`    | Image processing   |
| **client_svc** | 8085 | `/health`    | Client API gateway |

### Test from Terminal

```bash
# Health checks
curl http://localhost:8081/health  # user_svc
curl http://localhost:8083/health  # email_svc
curl http://localhost:8084/health  # image_svc
curl http://localhost:8085/health  # client_svc
```

### Test from Livebook

```elixir
# Set cookie first
Node.set_cookie(:msvc_dev_cookie_change_in_production)

# Connect to services
services = [
  :"client_svc@client_svc.msvc",
  :"user_svc@user_svc.msvc",
  :"image_svc@image_svc.msvc",
  :"email_svc@email_svc.msvc"
]

Enum.each(services, &Node.connect/1)
Node.list()
```

---

## Infrastructure Services

### Storage

| Service           | Port | URL                   | Description                  |
| ----------------- | ---- | --------------------- | ---------------------------- |
| **MinIO API**     | 9000 | http://localhost:9000 | S3-compatible object storage |
| **MinIO Console** | 9001 | http://localhost:9001 | MinIO web UI                 |

**MinIO Credentials** (from `.env.staging`):

- Username: `minioadmin`
- Password: `minioadmin`

### Observability

| Service        | Port  | URL                    | Description                        |
| -------------- | ----- | ---------------------- | ---------------------------------- |
| **Grafana**    | 3000  | http://localhost:3000  | Dashboards (logs, metrics, traces) |
| **Jaeger**     | 16686 | http://localhost:16686 | Distributed tracing UI             |
| **Prometheus** | 9090  | http://localhost:9090  | Metrics and time-series DB         |
| **Loki**       | 3100  | http://localhost:3100  | Log aggregation API                |
| **Promtail**   | 9080  | http://localhost:9080  | Log shipper                        |
| **Tempo**      | 3200  | http://localhost:3200  | Trace storage backend              |

**Grafana**: Anonymous access enabled (no login required)

### Development

| Service        | Port | URL                   | Description           |
| -------------- | ---- | --------------------- | --------------------- |
| **Livebook**   | 8090 | http://localhost:8090 | Interactive notebooks |
| **Swagger UI** | 8087 | http://localhost:8087 | API documentation     |

**Livebook Password** (from `.env.staging`): `msvc_dev_secret_pwd`

**Available Notebooks**:

- `cluster_test.livemd` - Test BEAM cluster connections + embedded dashboards
- `monitoring_dashboard.livemd` - Interactive monitoring with health checks
- `dns_debug.livemd` - DNS and cluster debugging tools

See [LIVEBOOK_KINO_GUIDE.md](LIVEBOOK_KINO_GUIDE.md) for Kino usage examples.

---

## Docker Compose Commands

### Start all services

```bash
docker-compose -f docker-compose-all.yml up
```

### Start specific services

```bash
docker-compose -f docker-compose-all.yml up user_svc client_svc
```

### Stop all services

```bash
docker-compose -f docker-compose-all.yml down
```

### View logs

```bash
docker-compose -f docker-compose-all.yml logs -f user_svc
```

### Rebuild after code changes

```bash
docker-compose -f docker-compose-all.yml build user_svc
docker-compose -f docker-compose-all.yml up user_svc
```

### Check cluster status

```bash
docker logs msvc-user-svc | grep Cluster
docker logs msvc-client-svc | grep Cluster
```

---

## Service-to-Service Communication

### From Host (localhost)

```bash
# Services use their container ports
curl http://localhost:8081/api/users
```

### Inside Docker Network

```bash
# Services use service names as hostnames
docker exec msvc-client-svc curl http://user_svc:8081/health
```

### BEAM Cluster Node Names

```elixir
# Each service has a fully qualified node name
:"client_svc@client_svc.msvc"
:"user_svc@user_svc.msvc"
:"image_svc@image_svc.msvc"
:"email_svc@email_svc.msvc"
```

---

## Environment Configuration

All configuration in [.env.staging](.env.staging):

- Service ports
- Database paths
- MinIO credentials
- Observability endpoints
- Erlang cluster cookie

**Important**: Change `ERL_COOKIE` in production!

---

## Useful Dashboards

### Monitor Everything

```bash
# Open all dashboards at once
open http://localhost:3000    # Grafana
open http://localhost:16686   # Jaeger
open http://localhost:9090    # Prometheus
open http://localhost:8087    # API Docs
```

### Check Service Health

```bash
# All at once
for port in 8081 8082 8083 8084 8085; do
  echo -n "Port $port: "
  curl -s http://localhost:$port/health || echo "DOWN"
done
```

---

## Troubleshooting

### Service won't start

```bash
# Check logs
docker logs msvc-user-svc

# Check if port is already in use
lsof -i :8081

# Rebuild
docker-compose -f docker-compose-all.yml build user_svc
```

### Can't access from host

```bash
# Verify port mapping
docker-compose -f docker-compose-all.yml ps

# Check firewall (macOS)
sudo pfctl -s rules | grep 8081
```

### Cluster not forming

```bash
# Check node names
docker exec msvc-user-svc bin/user_svc rpc 'Node.self()'

# Check cookie
docker exec msvc-user-svc printenv RELEASE_COOKIE

# Check network
docker network inspect msvc_default
```

---

## Development Workflow

### 1. Make changes to code

```bash
vim apps/user_svc/lib/user_svc/endpoint.ex
```

### 2. Rebuild and restart

```bash
docker-compose -f docker-compose-all.yml build user_svc
docker-compose -f docker-compose-all.yml up -d user_svc
```

### 3. Watch logs

```bash
docker-compose -f docker-compose-all.yml logs -f user_svc
```

### 4. Test

```bash
curl http://localhost:8081/health
# Or use Livebook for interactive testing
```

---

## Production Checklist

Before deploying to production:

- [ ] Change `ERL_COOKIE` to secure random value
- [ ] Change `LIVEBOOK_PASSWORD`
- [ ] Change MinIO credentials (`MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`)
- [ ] Update `LIVEBOOK_SECRET_KEY_BASE`
- [ ] Disable Grafana anonymous access
- [ ] Review and restrict exposed ports
- [ ] Set up proper SSL/TLS certificates
- [ ] Configure production logging format (JSON)
- [ ] Set up proper backup for databases and object storage

