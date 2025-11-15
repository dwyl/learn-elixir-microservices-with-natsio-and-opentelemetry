# Docker Clustering Lessons Learned

## Docker Networks Are NOT Automatic

Services MUST explicitly declare `networks:` to communicate.

```yaml
# RIGHT - can resolve each other
services:
  client_svc:
    networks:
      - msvc_default
  minio:
    networks:
      - msvc_default
```

**Errors examples**:

- `:nxdomain` errors
- `OTLP grpc export failed with error: {:shutdown, :nxdomain}`
- `ExAws: HTTP ERROR: :nxdomain for URL: "http://minio:9000/..."`

**Fix**: Add `networks: - msvc_default` to ALL services in docker-compose.

## Erlang Clustering Is NOT Transitive

`Node.connect/1` must be called from BOTH sides (or at least one side from each pair).

```elixir
# On client_svc
Node.connect(:"user_svc@user_svc.msvc")
Node.list()  # => [:"user_svc@user_svc.msvc"] ✓

# On user_svc (without calling Node.connect)
Node.list()  # => [] ✗  ← user_svc doesn't know about client!
```

While the underlying TCP connection is bidirectional once established, the initial connection must be initiated by at least one node.

**Solution**: Have each service connect to all others on startup:

```elixir
# In EVERY service's application.ex
defp connect_to_cluster do
  nodes = [
    :"client_svc@client_svc.msvc",
    :"user_svc@user_svc.msvc",
    :"job_svc@job_svc.msvc",
    # ... all services
  ]

  nodes
  |> Enum.reject(&(&1 == Node.self()))
  |> Enum.each(&Node.connect/1)
end
```

This ensures a full mesh topology where every node knows about every other node.

## Docker hostname and Erlang hostname

Docker's default hostname is a random container ID.

Erlang distribution requires a resolvable hostname after the `@` in node names.

Docker's internal DNS resolves these hostnames within the network.

All nodes must share the same Erlang cookie. You can generate one with:

```bash
# Generate a secure cookie
openssl rand -base64 32
```

Use `name` (long names) with "." in the middle:

```yaml
environment:
  RELEASE_DISTRIBUTION: "name"
  RELEASE_NODE: "service_name@service_name.msvc"
  RELEASE_COOKIE: ${ERL_COOKIE}
```

The release environment file [apps/*/rel/env.sh.eex](apps/client_svc/rel/env.sh.eex) allows Docker env vars to override defaults:

```bash
# apps/*/rel/env.sh.eex
export RELEASE_COOKIE="${RELEASE_COOKIE}"
export RELEASE_DISTRIBUTION="${RELEASE_DISTRIBUTION:-name}"
export RELEASE_NODE="${RELEASE_NODE:-<%= @release.name %>@${HOSTNAME}}"
```

### References

- [Distributed Erlang](https://www.erlang.org/doc/reference_manual/distributed.html)
- [Elixir Releases](https://hexdocs.pm/mix/Mix.Tasks.Release.html)
- [libcluster](https://github.com/bitwalker/libcluster) - For automatic cluster formation

## About DNSCluster in Docker Compose

When you configure:

```elixir
{DNSCluster, query: {"user_svc", "user_svc.msvc"}}
```

- DNSCluster queries `user_svc.msvc` with a `nslookup user_svc.msvc`.
- This returns `192.168.107.9`.
- DNSCluster tries to connect using the IP: `Node.connect(:"user_svc@192.168.107.9")`
- But the node is actually named as FQDN, not IP: `:"user_svc@user_svc.msvc"`

- so the names don't match, so `Node.connect/1` returns `false`, but DNSCluster doesn't log this clearly.

## About `Node.list()` returning `[]` 

Docker Compose DNS returns **IP addresses** when queried, but your Erlang nodes are named with **hostnames** (FQDNs).

In Kubernetes, nodes are often named with IPs (e.g., `app@10.42.0.5`), so DNSCluster works.

In Docker Compose with explicit hostnames, it breaks.

## Solution: `libcluster`

Use `epmd`-strategy for this simple cluster.

```elixir
# config/runtime.exs
config :libcluster,
  topologies: [
    msvc_cluster: [
      strategy: Cluster.Strategy.Epmd,
      config: [
        hosts: [
          :"client_svc@client_svc.msvc",
          :"user_svc@user_svc.msvc",
          :"job_svc@job_svc.msvc",
          :"image_svc@image_svc.msvc",
          :"email_svc@email_svc.msvc"
        ]
      ]
    ]
  ]
```

The _docker-compose.yml_ file:

```yaml
services:
  user_svc:
    hostname: user_svc.msvc  # ← Explicit hostname
    environment:
      RELEASE_NODE: "user_svc@user_svc.msvc"
      RELEASE_COOKIE: ${ERL_COOKIE}
      RELEASE_DISTRIBUTION: "name"
    networks:
      - msvc_default  # ← Explicit network

  client_svc:
    hostname: client_svc.msvc
    environment:
      RELEASE_NODE: "client_svc@client_svc.msvc"
      RELEASE_COOKIE: ${ERL_COOKIE}
      RELEASE_DISTRIBUTION: "name"
    networks:
      - msvc_default

  # ... repeat for all services

  # Infrastructure services also need the network!
  minio:
    networks:
      - msvc_default

  jaeger:
    networks:
      - msvc_default

networks:
  msvc_default:
```
