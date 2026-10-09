# onsite-print-server

Top-level repo. Starts the onsite-print services with Docker Compose:

- `web-server` – nginx, http://localhost:8080
- `database` – PostgreSQL, `127.0.0.1:5432` (`postgres:5432` inside the Compose network)

```sh
git clone --recurse-submodules git@github.com:groskopf/onsite-print-server.git
cd onsite-print-server
openssl rand -base64 32 > database/secrets/postgres_password
docker compose up -d
```

See each submodule's README for details.
