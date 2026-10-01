# Lab connection details, exposed two ways:
# - ~/.config/lab/env, rewritten on every start and loaded by login shells
#   (/etc/profile.d/coder-lab-env.sh): the single place tests and agents look.
# - Agent env for the values Terraform knows (MOCO's password is generated at
#   runtime, so MySQL is env-file only).

locals {
  lab_env = merge(
    local.lab_pg ? {
      DATABASE_URL = "postgres://app:${random_password.pg[0].result}@lab-pg-rw.${local.ns}.svc:5432/app"
    } : {},
    local.lab_minio ? {
      AWS_ENDPOINT_URL_S3   = "http://minio.${local.ns}.svc"
      AWS_ACCESS_KEY_ID     = "lab"
      AWS_SECRET_ACCESS_KEY = random_password.minio.result
    } : {},
  )
  # Keys built from the flags alone, so for_each never sees a sensitive value.
  lab_env_keys = concat(
    local.lab_pg ? ["DATABASE_URL"] : [],
    local.lab_minio ? ["AWS_ENDPOINT_URL_S3", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"] : [],
  )
}

resource "coder_env" "lab" {
  for_each = toset(local.start == 1 ? local.lab_env_keys : [])
  agent_id = coder_agent.main.id
  name     = each.key
  value    = local.lab_env[each.key]
}

# Always runs, so disabling every lab also clears a stale env file. Each wait
# logs and gives up after 15 minutes without failing the workspace.
resource "coder_script" "labs" {
  count              = local.start
  agent_id           = coder_agent.main.id
  display_name       = "Lab services"
  icon               = "/icon/database.svg"
  run_on_start       = true
  start_blocks_login = false
  script             = <<-EOT
    #!/usr/bin/env bash
    set -u
    NS="${local.ns}"
    ENV_FILE="$HOME/.config/lab/env"
    OUT=$(mktemp -d)
    mkdir -p "$(dirname "$ENV_FILE")"
    log() { echo "[labs] $*"; }

    # wait_ready <resource> <kubectl wait --for condition>
    wait_ready() {
      local res=$1 cond=$2 deadline=$((SECONDS + 900))
      until kubectl -n "$NS" get "$res" >/dev/null 2>&1; do
        if [ "$SECONDS" -ge "$deadline" ]; then log "WARN: $res never appeared"; return 1; fi
        sleep 5
      done
      if kubectl -n "$NS" wait "$res" "--for=$cond" "--timeout=$((deadline - SECONDS))s" >/dev/null 2>&1; then
        log "$res ready after $${SECONDS}s"
        return 0
      fi
      log "WARN: $res not ready after 15m; continuing without it"
      return 1
    }

    secret_key() { kubectl -n "$NS" get secret "$1" -o "jsonpath={.data.$2}" | base64 -d; }

    lab_pg() {
      wait_ready clusters.postgresql.cnpg.io/lab-pg condition=Ready || return 0
      local pw; pw=$(secret_key lab-pg-app password)
      cat > "$OUT/postgres" <<EOF
    DATABASE_URL=postgres://app:$pw@lab-pg-rw.$NS.svc:5432/app
    PGHOST=lab-pg-rw.$NS.svc
    PGPORT=5432
    PGUSER=app
    PGPASSWORD=$pw
    PGDATABASE=app
    EOF
    }

    lab_minio() {
      wait_ready tenants.minio.min.io/lab-minio jsonpath='{.status.currentState}'=Initialized || return 0
      local user pw endpoint="http://minio.$NS.svc"
      user=$(secret_key lab-minio user); pw=$(secret_key lab-minio password)
      cat > "$OUT/minio" <<EOF
    MINIO_ENDPOINT=$endpoint
    AWS_ENDPOINT_URL_S3=$endpoint
    AWS_ACCESS_KEY_ID=$user
    AWS_SECRET_ACCESS_KEY=$pw
    AWS_REGION=us-east-1
    EOF
      mc alias set lab "$endpoint" "$user" "$pw" >/dev/null \
        && mc mb --ignore-existing lab/test >/dev/null \
        || log "WARN: could not configure the lab alias or the test bucket"
    }

    lab_mysql() {
      wait_ready mysqlclusters.moco.cybozu.com/lab-mysql condition=Healthy || return 0
      local pw; pw=$(secret_key moco-lab-mysql WRITABLE_PASSWORD)
      kubectl -n "$NS" exec moco-lab-mysql-0 -c mysqld -- \
        env MYSQL_PWD="$pw" mysql -h127.0.0.1 -umoco-writable -e 'CREATE DATABASE IF NOT EXISTS app' >/dev/null \
        || log "WARN: could not create database app"
      cat > "$OUT/mysql" <<EOF
    MYSQL_URL=mysql://moco-writable:$pw@moco-lab-mysql-primary.$NS.svc:3306/app
    MYSQL_HOST=moco-lab-mysql-primary.$NS.svc
    MYSQL_TCP_PORT=3306
    MYSQL_USER=moco-writable
    MYSQL_PWD=$pw
    MYSQL_DATABASE=app
    EOF
    }

    %{if local.lab_pg~}
    lab_pg &
    %{endif~}
    %{if local.lab_minio~}
    lab_minio &
    %{endif~}
    %{if local.lab_mysql~}
    lab_mysql &
    %{endif~}
    wait

    cat "$OUT"/* > "$ENV_FILE.new" 2>/dev/null || : > "$ENV_FILE.new"
    chmod 600 "$ENV_FILE.new" && mv "$ENV_FILE.new" "$ENV_FILE"
    rm -rf "$OUT"
    log "wrote $ENV_FILE ($(wc -l < "$ENV_FILE") lines)"
  EOT
}
