# FreeRADIUS Adaptive Stack

FreeRADIUS 3.2.7 · PostgreSQL 16 · pgBouncer 1.23 · Redis 7.4 · HAProxy 3.0

A Docker Compose stack that scales from a laptop to 50 000 clients without redesign. One compose file, three optional profiles, ENV-driven config.

---

## Before you start

You need **Docker Desktop** installed and running.

- Windows: [https://docs.docker.com/desktop/install/windows-install/](https://docs.docker.com/desktop/install/windows-install/)
- Mac: [https://docs.docker.com/desktop/install/mac-install/](https://docs.docker.com/desktop/install/mac-install/)
- Linux: see [linux-server.md](#running-on-a-linux-server) below

Verify it works:

```
docker compose version
```

You should see `Docker Compose version v2.x.x`. If you see `command not found`, Docker Desktop is not installed or not running.

---

## Running locally on Windows or Mac

> **Why a separate step for Windows/Mac?**
> The main `docker-compose.yml` uses `mode: host` port bindings — a Linux kernel
> feature that Docker Desktop does not support. The local override file swaps
> those out for standard bindings that work everywhere.

### 1. Clone the repo

```
git clone <your-repo-url> radius
cd radius
```

### 2. Copy the override file

This is a one-time step. Docker Compose automatically picks up `docker-compose.override.yml` on every command, so you never have to type it again.

**Windows Command Prompt:**
```
copy docker-compose.local.yml docker-compose.override.yml
```

**PowerShell or bash (Git Bash / WSL):**
```
cp docker-compose.local.yml docker-compose.override.yml
```

### 3. Create your `.env` file

The project ships with two env templates:

| File | Purpose |
|------|---------|
| `.env.local` | Local dev — pre-filled safe defaults, copy and go |
| `.env.example` | Production template — all `CHANGE_ME` placeholders |

For local dev, copy `.env.local`:

**Windows CMD:**
```
copy .env.local .env
```

**PowerShell or bash:**
```
cp .env.local .env
```

That's it — no values to fill in. The defaults in `.env.local` are already consistent with `docker-compose.local.yml` and the load generator flags shown later in this README.

> `.env.local` is committed to the repo because it only contains throwaway
> local-only values. `.env` is never committed — `.gitignore` excludes it.

### 4. Start the stack

```
docker compose up -d
```

Docker will pull the images on first run (this takes a minute). After that:

```
docker compose ps
```

You should see something like:

```
NAME                    STATUS
radius-freeradius-1     Up (healthy)
radius-pgbouncer        Up (healthy)
radius-postgres         Up (healthy)
```

FreeRADIUS takes about 10 seconds to pass its healthcheck on first start. If it shows `starting` — wait a few seconds and run `docker compose ps` again.

### 5. Send a test packet

The stack ships with a test user (`testuser` / `testpass`) seeded by `config/postgres/init.sql`.

Open a second terminal and run:

```
docker compose exec radtest-tool sh
```

This drops you into a shell inside the test container. From there:

```
radtest testuser testpass freeradius 0 $RADIUS_SECRET
```

A successful response looks like:

```
Sent Access-Request Id 1 from 0.0.0.0:42513 to 172.28.0.x:1812
Received Access-Accept Id 1 from 172.28.0.x:1812
```

If you see `Access-Reject`, check that `RADIUS_SECRET` in your `.env` matches what you used in the `radtest` command (the last argument). The test container reads it from the env automatically.

Type `exit` to leave the container shell.

### 6. Stop the stack

```
docker compose down
```

This stops and removes the containers. Your database volume is preserved — restart with `docker compose up -d` and data is still there.

To also delete the database volumes:

```
docker compose down -v
```

---

## Profiles — adding more components

The base stack is just FreeRADIUS + PostgreSQL + pgBouncer. Optional components are activated with `--profile` flags.

### `testing` — test tools container

Adds a container with `radtest`, `radclient`, and the shell test scripts.

```
docker compose --profile testing up -d
```

Use this for local dev. The base stack does not include radtest-tool.

### `cache` — Redis auth cache

Adds Redis. FreeRADIUS caches auth results for `RADIUS_CACHE_TTL` seconds (default 300). Reduces database load 40–70% on repeat authentications.

```
docker compose --profile cache up -d
```

Requires `REDIS_PASSWORD` to be set in `.env`.

### `ha` — HAProxy + PostgreSQL replica

Adds a PostgreSQL streaming replica and HAProxy UDP load balancer. **Only useful when running multiple FreeRADIUS replicas — skip this profile for local dev.**

On Windows/Mac this profile works fine with the local override file, but you will only ever run one FreeRADIUS container locally regardless of `RADIUS_REPLICAS`.

### Combining profiles

```
docker compose --profile cache --profile testing up -d
```

---

## Common problems

### "Error response from daemon: driver failed programming external connectivity"

Port 1812 or 1813 is already in use on your machine. Another RADIUS server, or a previous stack that wasn't fully stopped.

```
docker compose down
```

If the port is still busy, find what's using it:

**Windows:**
```
netstat -ano | findstr :1812
```

**PowerShell:**
```
Get-NetTCPConnection -LocalPort 1812
```

### "freeradius-1 is unhealthy"

Check the logs:

```
docker compose logs freeradius
```

The most common cause is a missing or wrong `RADIUS_HEALTH_SECRET` in `.env`. The value in `.env` must match the password in `config/postgres/init.sql` for the `healthcheck` user. The default in `init.sql` is `CHANGE_ME_health_secret` — if you changed `.env` but not `init.sql`, they won't match.

To fix without rebuilding: update `.env`, delete the database volume so `init.sql` reruns, and restart:

```
docker compose down -v
docker compose up -d
```

### "connection refused" when using radtest from outside Docker

By default FreeRADIUS only accepts packets from known clients. Your host machine (outside Docker) is not in `clients.conf`.

Either use `radtest` from inside the `radtest-tool` container (which is inside the Docker network), or add your host IP to `config/freeradius/clients.conf`:

```
client my_host {
    ipaddr  = 192.168.x.x     # your machine's IP on the Docker bridge
    secret  = localtesting
    nas_type = other
}
```

Then restart FreeRADIUS:

```
docker compose restart freeradius
```

### Images won't pull / "network timeout"

Docker Desktop may not have network access. Check Docker Desktop is fully started (the whale icon in the system tray should not be animating). Also check your corporate proxy or VPN settings — those commonly block Docker Hub.

---

## Running on a Linux server

The main `docker-compose.yml` is designed for Linux. No override file needed.

### Install Docker (Ubuntu 24.04)

```bash
sudo apt-get update && sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker $USER
# log out and back in after this
```

### Start the stack

```bash
git clone <your-repo-url> radius && cd radius
cp .env.example .env
# edit .env — replace every CHANGE_ME with real secrets
docker compose up -d
```

For Tier C (multi-replica, full HA):

```bash
docker compose --profile cache --profile ha up -d
```

---

## What's in the repo

```
radius/
├── docker-compose.yml          production compose file (Linux)
├── docker-compose.local.yml    Windows / Mac override
├── .env.example                copy to .env and fill in secrets
├── config/
│   ├── freeradius/
│   │   ├── radiusd.conf        main config
│   │   ├── clients.conf        authorized NAS devices
│   │   ├── sites-enabled/      AAA pipeline (authorize → authenticate → post-auth → accounting)
│   │   └── mods-enabled/       sql, cache, pap, chap, mschap modules
│   ├── postgres/
│   │   ├── init.sql            schema + seed data (runs once on first start)
│   │   ├── pg_hba.conf         connection auth rules (scram-sha-256 enforced)
│   │   └── replica-init.sh     streaming replica bootstrap (ha profile)
│   ├── haproxy/
│   │   └── haproxy.cfg         UDP load balancer config (ha profile)
│   └── redis/                  (empty — Redis configured via compose env)
├── scripts/
│   └── tests/
│       ├── smoke.sh            single auth + reject test
│       └── load.sh             parallel load test via radclient
└── .github/
    └── workflows/
        └── deploy.yml          automated deploy to VM via SSH
```

---

## Next steps

- **Add real users** — insert rows into `radcheck` via the Postgres container:
  ```
  docker compose exec postgres psql -U radius -c \
    "INSERT INTO radcheck (username, attribute, op, value) VALUES ('alice', 'Cleartext-Password', ':=', 'alicepass');"
  ```

- **Add a real NAS/AP** — add a `client` block to `config/freeradius/clients.conf` with the NAS IP and a strong secret, then `docker compose restart freeradius`.

- **Run the load generator** — see `../radius-loadgen/README.md` for seeding and traffic simulation.

- **Deploy to a server** — see `GUIDE.md` for GitHub Actions deploy, Tier C tuning, and Tier D multi-zone setup.
