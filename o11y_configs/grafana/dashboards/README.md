# PromEx Grafana Dashboards

This directory contains exported PromEx dashboards for your microservices.

## Quick Start: Import Dashboards into Grafana

### Option 1: Manual Import via Grafana UI (Easiest)

1. Open Grafana: http://localhost:3000
2. Click **"+"** → **"Import dashboard"** (left sidebar)
3. Click **"Upload JSON file"**
4. Select a dashboard file from this directory (e.g., `user_svc_application.json`)
5. Click **"Load"**
6. Verify the datasource is set to **"Prometheus"**
7. Click **"Import"**

**Available Dashboards:**

**Custom Plugin Dashboards (shared across all services):**

- `os_metrics.json` - OS-level metrics (CPU, memory, load) with service selector
- `nats_metrics.json` - NATS messaging metrics (pub/sub latency, throughput) with service and topic selectors

**Service-Specific Dashboards (from built-in PromEx plugins):**

- `user_svc_application.json` - Application metrics (uptime, memory, etc.)
- `user_svc_beam.json` - BEAM VM metrics (processes, schedulers, etc.)
- `image_svc_broadway.json` - Broadway pipeline metrics (message processing, concurrency, throughput)

### Option 2: Auto-Provisioning (Automatic on Container Start)

Update `grafana/provisioning/dashboards/dashboards.yml` to auto-load dashboards:

```yaml
apiVersion: 1

providers:
  - name: 'PromEx Dashboards'
    orgId: 1
    folder: 'PromEx'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
```

Then mount this directory in `docker-compose.yml`:

```yaml
grafana:
  volumes:
    - ./grafana/dashboards:/etc/grafana/provisioning/dashboards:ro
```

Restart Grafana:

```bash
docker-compose restart grafana
```

Dashboards will appear automatically in the "PromEx" folder.

### Option 3: Enable Automatic Dashboard Upload (Advanced)

**NOTE:** This requires Grafana API credentials and network access from your services to Grafana.

1. Enable Grafana upload in each service's `config/config.exs`:

```elixir
config :user_svc, UserSvc.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: [
    host: System.get_env("GRAFANA_HOST", "http://grafana:3000"),
    auth_token: System.get_env("GRAFANA_TOKEN"),
    upload_dashboards_on_start: true,
    folder_name: "PromEx Dashboards",
    annotate_app_lifecycle: true
  ],
  metrics_server: :disabled
```

2. Generate a Grafana API token:
   - Go to Grafana → Configuration → API Keys
   - Click "New API Key"
   - Name: "PromEx"
   - Role: "Editor"
   - Copy the token

3. Add token to docker-compose environment:

```yaml
user_svc:
  environment:
    GRAFANA_HOST: "http://grafana:3000"
    GRAFANA_TOKEN: "your-api-token-here"
```

4. Restart services:
```bash
docker-compose restart user_svc
```

Dashboards will be uploaded automatically on service start!

## Exporting New Dashboards

To export dashboards for other services:

```bash
# User Service
cd apps/user_svc
mix prom_ex.dashboard.export --dashboard application.json --module UserSvc.PromEx --stdout > ../../grafana/dashboards/user_svc_application.json
mix prom_ex.dashboard.export --dashboard beam.json --module UserSvc.PromEx --stdout > ../../grafana/dashboards/user_svc_beam.json

# Job Service
cd apps/job_svc
mix prom_ex.dashboard.export --dashboard application.json --module JobSvc.PromEx --stdout > ../../grafana/dashboards/job_svc_application.json
mix prom_ex.dashboard.export --dashboard beam.json --module JobSvc.PromEx --stdout > ../../grafana/dashboards/job_svc_beam.json

# Image Service
cd apps/image_svc
mix prom_ex.dashboard.export --dashboard application.json --module ImageSvc.PromEx --stdout > ../../grafana/dashboards/image_svc_application.json
mix prom_ex.dashboard.export --dashboard beam.json --module ImageSvc.PromEx --stdout > ../../grafana/dashboards/image_svc_beam.json

# Email Service
cd apps/email_svc
mix prom_ex.dashboard.export --dashboard application.json --module EmailSvc.PromEx --stdout > ../../grafana/dashboards/email_svc_application.json
mix prom_ex.dashboard.export --dashboard beam.json --module EmailSvc.PromEx --stdout > ../../grafana/dashboards/email_svc_beam.json

# Client Service
cd apps/client_svc
mix prom_ex.dashboard.export --dashboard application.json --module ClientSvc.PromEx --stdout > ../../grafana/dashboards/client_svc_application.json
mix prom_ex.dashboard.export --dashboard beam.json --module ClientSvc.PromEx --stdout > ../../grafana/dashboards/client_svc_beam.json
```

## Available PromEx Dashboards

Uncomment the ones you want in each service's `prom_ex.ex` file:

```elixir
def dashboards do
  [
    {:prom_ex, "application.json"},  # ✓ Application metrics
    {:prom_ex, "beam.json"},         # ✓ BEAM VM metrics
    # {:prom_ex, "phoenix.json"},    # Phoenix endpoint metrics
    # {:prom_ex, "ecto.json"},       # Database query metrics
    # {:prom_ex, "oban.json"},       # Oban job metrics (job_svc)
  ]
end
```

## Dashboard Datasource

All dashboards use `datasource_id: "prometheus"` which matches the `uid: prometheus` in `grafana/provisioning/datasources/datasources.yml`.

If you rename the datasource, update all `prom_ex.ex` files:

```elixir
def dashboard_assigns do
  [
    datasource_id: "prometheus",  # Must match Grafana datasource uid
    default_selected_interval: "30s"
  ]
end
```

## Troubleshooting

**Dashboard shows "No data":**
- Check Prometheus is scraping metrics: http://localhost:9090/targets
- Verify your service exposes `/metrics` endpoint
- Check datasource connection in Grafana

**"Datasource not found" error:**
- Ensure `datasource_id` in `prom_ex.ex` matches `uid` in `datasources.yml`
- Default is `"prometheus"` (lowercase)

**Panels are empty:**
- Services need to be running and generating metrics
- Check Prometheus is configured to scrape your services in `prometheus/prometheus.yml`

## Custom Plugin Dashboards

**Important:** Custom PromEx plugins (`PromExPlugin.OsMetrics`, `PromExPlugin.NatsMetrics`) **cannot** export dashboards via `mix prom_ex.dashboard.export`. Only built-in PromEx plugins (Application, Beam, Phoenix, Ecto, Oban, Broadway) have pre-built dashboard templates.

For custom plugins:

1. **Create dashboards manually** in Grafana UI
2. **Export as JSON** (Share → Export → Save to file)
3. **Save to** `o11y_configs/grafana/dashboards/`

### Why Shared Dashboards Work

Because `OsMetrics` and `NatsMetrics` are in `libs/metrics/` (not per-service), all services expose **identical metric names**:

```promql
# Same metric name across all services
prom_ex_os_mon_cpu_util
gnat_message_received_total

# Prometheus adds 'job' label automatically
prom_ex_os_mon_cpu_util{job="user_svc"}
prom_ex_os_mon_cpu_util{job="image_svc"}
```

This allows **one dashboard** with service/topic selectors instead of duplicating dashboards per service.
