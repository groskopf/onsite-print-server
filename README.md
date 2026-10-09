# onsite-print-server

Top-level repo. Starts the onsite-print services with Docker Compose by including
the compose files of the sibling repos:

- `../onsite-print-web-server` – nginx, http://localhost:8080; forwards `/api/` to the backend
- `../onsite-print-backend` – FastAPI REST API, http://localhost:8080/api/docs
- `../onsite-print-database` – PostgreSQL, `127.0.0.1:5432` (`postgres:5432` inside the Compose network)

Clone all repos next to each other:

```sh
mkdir onsite-print && cd onsite-print
for r in onsite-print-server onsite-print-web-server onsite-print-backend onsite-print-database; do
  git clone git@github.com:groskopf/$r.git
done
openssl rand -base64 32 > onsite-print-database/secrets/postgres_password
cd onsite-print-server
docker compose up -d
```

Changes in the sibling repos are picked up directly. See each repo's README for details.
