#!/bin/bash -e

echo "============================================================="
echo "HIGHLIGHT SETUP DEBUGGING AND DOCKER-COMPOSE GENERATOR"
echo "============================================================="

# Create a directory for our findings
mkdir -p /tmp/highlight-debug

# Function to print section headers
print_section() {
  echo ""
  echo "============================================================="
  echo "$1"
  echo "============================================================="
}

# Check for installed Docker images
print_section "CHECKING INSTALLED DOCKER IMAGES"
docker images | grep -E 'highlight|clickhouse|kafka|postgres|redis|zookeeper|otel|predictions' > /tmp/highlight-debug/docker-images.txt
cat /tmp/highlight-debug/docker-images.txt

# Check for running containers
print_section "CHECKING RUNNING CONTAINERS"
docker ps | grep -E 'highlight|clickhouse|kafka|postgres|redis|zookeeper|collector|predictions|backend|frontend' > /tmp/highlight-debug/docker-containers.txt
cat /tmp/highlight-debug/docker-containers.txt

# Check environment variables
print_section "ANALYZING ENVIRONMENT VARIABLES"
if [ -f .env ]; then
  echo "Found .env file. Analyzing content..."
  grep -v '^#' .env | grep -E '\S+' > /tmp/highlight-debug/env-vars.txt
  cat /tmp/highlight-debug/env-vars.txt
else
  echo "No .env file found in the current directory."
fi

# Source env.sh to get the actual environment
source env.sh || echo "Failed to source env.sh"

# Check volumes
print_section "CHECKING DOCKER VOLUMES"
docker volume ls | grep -E 'highlight|postgres|clickhouse|redis|kafka|zoo' > /tmp/highlight-debug/docker-volumes.txt
cat /tmp/highlight-debug/docker-volumes.txt

# Check networks
print_section "CHECKING DOCKER NETWORKS"
docker network ls | grep highlight > /tmp/highlight-debug/docker-networks.txt
cat /tmp/highlight-debug/docker-networks.txt

# Analyze compose files
print_section "ANALYZING COMPOSE FILES"
echo "compose.yml structure:"
grep "^  [a-z]" compose.yml | sort | uniq
echo ""
echo "compose.hobby.yml structure:"
grep "^  [a-z]" compose.hobby.yml | sort | uniq

# Create a comprehensive docker-compose.yaml file
print_section "CREATING COMPREHENSIVE DOCKER-COMPOSE.YAML"

cat > /tmp/highlight-debug/docker-compose.yaml << 'EOL'
version: '3.8'

x-local-logging: &local-logging
  driver: local

services:
  # Infrastructure services
  zookeeper:
    logging: *local-logging
    image: ${ZOOKEEPER_IMAGE_NAME:-confluentinc/cp-zookeeper:7.7.0}
    container_name: zookeeper
    restart: on-failure
    volumes:
      - zoo-data:/var/lib/zookeeper/data
      - zoo-log:/var/lib/zookeeper/log
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000

  kafka:
    logging: *local-logging
    image: ${KAFKA_IMAGE_NAME:-confluentinc/cp-kafka:7.7.0}
    container_name: kafka
    volumes:
      - kafka-data:/var/lib/kafka/data
    ports:
      - '0.0.0.0:9092:9092'
    restart: on-failure
    depends_on:
      - zookeeper
    environment:
      KAFKA_ADVERTISED_LISTENERS: ${KAFKA_ADVERTISED_LISTENERS:-PLAINTEXT://kafka:9092}
      KAFKA_BROKER_ID: 1
      KAFKA_CONSUMER_MAX_PARTITION_FETCH_BYTES: 268435456
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT
      KAFKA_LOG_RETENTION_HOURS: 1
      KAFKA_LOG_SEGMENT_BYTES: 268435456
      KAFKA_MESSAGE_MAX_BYTES: 268435456
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_PRODUCER_MAX_REQUEST_SIZE: 268435456
      KAFKA_REPLICA_FETCH_MAX_BYTES: 268435456
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_ZOOKEEPER_CONNECT: 'zookeeper:2181'

  redis:
    logging: *local-logging
    container_name: redis
    image: ${REDIS_IMAGE_NAME:-redis:7.4.0}
    restart: on-failure
    volumes:
      - redis-data:/data
    ports:
      - '0.0.0.0:6379:6379'
    command:
      - redis-server
      - --save 60 1
      - --loglevel warning

  postgres:
    logging: *local-logging
    container_name: postgres
    image: ${POSTGRES_IMAGE_NAME:-ankane/pgvector:v0.5.1}
    restart: on-failure
    ports:
      - '0.0.0.0:5432:5432'
    environment:
      POSTGRES_HOST_AUTH_METHOD: trust
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ../scripts/migrations/init.sql:/root/init.sql
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U postgres']
      interval: 5s
      timeout: 5s
      retries: 5

  clickhouse:
    logging: *local-logging
    container_name: clickhouse
    image: ${CLICKHOUSE_IMAGE_NAME:-clickhouse/clickhouse-server:24.3.15.72-alpine}
    restart: on-failure
    ports:
      - '0.0.0.0:8123:8123'
      - '0.0.0.0:9000:9000'
    volumes:
      - ./config.xml:/etc/clickhouse-server/config.d/highlight.xml
      - ./users.xml:/etc/clickhouse-server/users.d/highlight.xml
      - clickhouse-data:/var/lib/clickhouse
      - clickhouse-logs:/var/log/clickhouse-server

  collector:
    logging: *local-logging
    restart: on-failure
    build:
      dockerfile: ./docker/collector.Dockerfile
      context: .
      args:
        - IN_DOCKER_GO=${IN_DOCKER_GO:-true}
        - SSL=${SSL:-false}
    container_name: collector
    extra_hosts:
      - 'host.docker.internal:host-gateway'
    volumes:
      - ./backend/localhostssl/server.crt:/server.crt
      - ./backend/localhostssl/server.key:/server.key
    ports:
      - '0.0.0.0:24224:24224'
      - '0.0.0.0:34302:34302'
      - '0.0.0.0:4317:4317'
      - '0.0.0.0:4318:4318'
      - '0.0.0.0:4319:4319'
      - '0.0.0.0:4433:4433'
      - '0.0.0.0:4434:4434'
      - '0.0.0.0:4435:4435'
      - '0.0.0.0:6513:6513'
      - '0.0.0.0:6514:6514'
      - '0.0.0.0:8318:8318'
      - '0.0.0.0:8888:8888'

  predictions:
    logging: *local-logging
    restart: on-failure
    build:
      dockerfile: ./packages/predictions/predictions.Dockerfile
      context: .
    container_name: predictions
    ports:
      - '0.0.0.0:5001:5001'

  # Highlight application services
  backend:
    container_name: backend
    image: ${BACKEND_IMAGE_NAME:-ghcr.io/highlight/highlight-backend:latest}
    restart: on-failure
    ports:
      - '0.0.0.0:8082:8082'
    volumes:
      - highlight-data:/highlight-data
      - ./backend/env.enc:/build/env.enc
      - ./backend/env.enc.dgst:/build/env.enc.dgst
      - ./backend/localhostssl/server.key:/build/localhostssl/server.key
      - ./backend/localhostssl/server.crt:/build/localhostssl/server.crt
    env_file: .env
    depends_on:
      - clickhouse
      - kafka
      - postgres
      - redis
      - zookeeper
      - collector
      - predictions

  frontend:
    container_name: frontend
    image: ${FRONTEND_IMAGE_NAME:-ghcr.io/highlight/highlight-frontend:latest}
    restart: on-failure
    volumes:
      - ./backend/localhostssl/server.key:/etc/ssl/private/ssl-cert.key
      - ./backend/localhostssl/server.pem:/etc/ssl/certs/ssl-cert.pem
    ports:
      - '0.0.0.0:3000:3000'
      - '0.0.0.0:6006:6006'
      - '0.0.0.0:8080:8080'
    env_file: .env
    depends_on:
      - backend

volumes:
  postgres-data:
  clickhouse-data:
  clickhouse-logs:
  redis-data:
  kafka-data:
  zoo-log:
  zoo-data:
  highlight-data:
EOL

# Create a .env file with all required variables
print_section "CREATING COMPREHENSIVE .ENV FILE"

cat > /tmp/highlight-debug/.env << 'EOL'
# Docker compose config
COMPOSE_PATH_SEPARATOR=:
COMPOSE_PROJECT_NAME=highlight

# Docker images for highlight app
BACKEND_IMAGE_NAME=ghcr.io/highlight/highlight-backend:docker-v0.5.2
FRONTEND_IMAGE_NAME=ghcr.io/highlight/highlight-frontend:docker-v0.5.2

# Docker images for dependencies
CLICKHOUSE_IMAGE_NAME=clickhouse/clickhouse-server:24.3.15.72-alpine
KAFKA_IMAGE_NAME=confluentinc/cp-kafka:7.7.0
OTEL_COLLECTOR_BUILD_IMAGE_NAME=alpine:3.21.3
OTEL_COLLECTOR_IMAGE_NAME=otel/opentelemetry-collector-contrib:0.120.0
POSTGRES_IMAGE_NAME=ankane/pgvector:v0.5.1
REDIS_IMAGE_NAME=redis:7.4.0
ZOOKEEPER_IMAGE_NAME=confluentinc/cp-zookeeper:7.7.0

# Environment variables
CLICKHOUSE_ADDRESS=clickhouse:9000
CLICKHOUSE_DATABASE=default
CLICKHOUSE_PASSWORD=
CLICKHOUSE_USERNAME=default
CONSUMER_SPAN_SAMPLING_FRACTION=1
DOPPLER_CONFIG=docker
EMAIL_OPT_OUT_SALT=salt
ENVIRONMENT=dev
GOMEMLIMIT=16GiB
IN_DOCKER=true
IN_DOCKER_GO=true
KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://kafka:9092
KAFKA_SERVERS=kafka:9092
KAFKA_TOPIC=dev
OAUTH_REDIRECT_URL=https://localhost:8082/private/oauth/callback
OBJECT_STORAGE_FS=/highlight-data
ON_PREM=true
OTLP_DOGFOOD_ENDPOINT=https://otel.highlight.io:4318
OTLP_ENDPOINT=http://collector:4318
PSQL_DB=postgres
PSQL_DOCKER_HOST=postgres
PSQL_HOST=postgres
PSQL_PASSWORD=
PSQL_PORT=5432
PSQL_USER=postgres
REACT_APP_DISABLE_ANALYTICS=false
REACT_APP_FRONTEND_ORG=1
REACT_APP_FRONTEND_URI=http://localhost:3000
REACT_APP_IN_DOCKER=true
REACT_APP_PRIVATE_GRAPH_URI=http://localhost:8082/private
REACT_APP_PUBLIC_GRAPH_URI=http://localhost:8082/public
REACT_APP_OTLP_ENDPOINT=http://localhost:4318
REDIS_EVENTS_STAGING_ENDPOINT=redis:6379
RENDER_PREVIEW=true
SESSION_FILE_PATH_PREFIX=/tmp/
SESSION_RETENTION_DAYS=30
TZ=America/Los_Angeles

# Note: turning on SSL requires updating otel-collector.yaml / otel-collector.hobby.yaml to use https
SSL=false
DISABLE_CORS=false
REACT_APP_AUTH_MODE=password
ADMIN_PASSWORD=password
EOL

echo "Debugging complete! Here are the generated files:"
echo "- Docker Compose file: /tmp/highlight-debug/docker-compose.yaml"
echo "- Environment file: /tmp/highlight-debug/.env"
echo ""
echo "To use these files, run:"
echo "cp /tmp/highlight-debug/docker-compose.yaml /tmp/highlight-debug/.env ."
echo "docker compose up -d" 