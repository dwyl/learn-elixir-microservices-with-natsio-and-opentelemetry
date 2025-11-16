# Multi-stage Dockerfile for image_svc (Monorepo)
# Build context MUST be the repo root: docker build -f apps/image_svc/Dockerfile .
# Stage 1: Build the release
ARG PORT=8084
ARG SERVICE=image_svc
ARG OS=alpine:3.22.2
ARG ELIXIR_IMAGE=hexpm/elixir:1.19.2-erlang-28.1-alpine-3.22.2
FROM ${ELIXIR_IMAGE} AS builder

ARG PORT
ENV PORT=${PORT}
ARG SERVICE
ENV SERVICE=${SERVICE}

# Install build dependencies + protoc for proto compilation
RUN apk add --no-cache \
    build-base \
    git \
    openssl-dev \
    protobuf-dev \
    # for escript because alpine is not glibc
    bash libc6-compat

# Set working directory
WORKDIR /app

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy shared protos library first (for better caching)
COPY libs/protos libs/protos/
COPY libs/otel_nats libs/otel_nats/
COPY libs/jetstream_setup libs/jetstream_setup/
COPY libs/storage libs/storage/

# Copy image_svc dependency files
COPY apps/${SERVICE}/mix.exs apps/${SERVICE}/mix.lock apps/${SERVICE}/
COPY apps/${SERVICE}/config/config.exs apps/${SERVICE}/config/prod.exs apps/${SERVICE}/config/

# Set working directory to image_svc
WORKDIR /app/apps/${SERVICE}

# Install dependencies (will compile protos lib automatically)
ENV MIX_ENV=prod
RUN mix deps.get --only prod

# Install protoc-gen-elixir escript (required for proto compilation)
RUN mix escript.install --force hex protobuf
ENV PATH="/root/.mix/escripts:${PATH}"

# Copy application code
COPY apps/${SERVICE}/lib ./lib
COPY apps/${SERVICE}/priv ./priv
COPY apps/${SERVICE}/config/runtime.exs config/

# Compile application (protos will be compiled as dependency)
RUN mix compile

# Build release
COPY apps/${SERVICE}/rel ./rel
RUN mix release

# Stage 2: Create minimal runtime image
FROM ${OS} AS app

ARG PORT
ENV PORT=${PORT}
ARG SERVICE
ENV SERVICE=${SERVICE}

# Install runtime dependencies for image processing
# - ImageMagick: For image format detection, metadata extraction, and image-to-PDF conversion
# - Ghostscript: Required by ImageMagick for PDF rendering (used internally)
RUN apk add --no-cache \
    bash \
    openssl \
    ncurses-libs \
    libstdc++ \
    wget \
    imagemagick \
    ghostscript

# Create app user
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser

WORKDIR /app

# Copy release from builder (built in /app/apps/image_svc)
COPY --from=builder --chown=appuser:appuser /app/apps/${SERVICE}/_build/prod/rel/${SERVICE} ./

# Create database directory with proper permissions before USER switch
RUN mkdir -p /app/db && chown -R appuser:appuser /app/db
# Switch to non-root user
USER appuser

# Expose port (can be overridden with PORT env var)
EXPOSE ${PORT}

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/bin/sh", "-c", "wget -q --spider http://localhost:${PORT}/health || exit 1"]

# Start the application
# CMD ["bin/image_svc", "start"]
CMD ["/bin/sh", "-c", "bin/${SERVICE} start"]
