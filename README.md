# onsite-print-server

Starts the onsite-print services with Docker Compose. Local builds use sibling
repos; server deployments use published images and need only this repo.

- `../onsite-print-web-server` – nginx, http://localhost:8080; forwards `/api/` to the backend
- `../onsite-print-backend` – FastAPI REST API, http://localhost:8080/api/v2/docs
- `../onsite-print-database` – PostgreSQL, `127.0.0.1:5432` (`postgres:5432` inside the Compose network)
- `../onsite-print-attendee` – http://localhost:8080/attendee/
- `../onsite-print-checkin` – http://localhost:8080/checkin/

The apps call the same-origin `/api/v2/` API; no separate API hostname or CORS
configuration is needed. nginx preserves each app's path prefix.

## Local development

Open this repo in VS Code and press **Ctrl+Shift+B** to run **Onsite Print: Start
development server**. It builds the images, starts the hot-reload stack, and waits
for startup. Containers keep running after the task completes. Use **Terminal >
Run Task > Onsite Print: Stop development server** to stop them without deleting
database data. The tasks are defined in [.vscode/tasks.json](.vscode/tasks.json).
The sibling repos and database password file below must already exist.

Clone all repos next to each other:

```sh
mkdir onsite-print && cd onsite-print
for r in onsite-print-server onsite-print-web-server onsite-print-backend onsite-print-database onsite-print-attendee onsite-print-checkin; do
  git clone git@github.com:groskopf/$r.git
done
openssl rand -base64 32 > onsite-print-database/secrets/postgres_password
cd onsite-print-server
docker compose -f compose.yaml -f compose.dev.yaml up -d --build
```

Only create the password file if it does not already exist. PostgreSQL initializes
its password on first start; overwriting the file does not change an existing
database user's password.

Edit either React repo and Vite updates the page through nginx, including its
WebSocket connection. Dependencies live in Docker volumes, separate from the
host's `node_modules`. `npm ci` runs when each dev container starts; restart that
service after changing its package lockfile. Backend source changes also reload
automatically. Rebuild after changing backend dependencies.
After editing the gateway's nginx configuration, restart its service to reload it.

```sh
docker compose -f compose.yaml -f compose.dev.yaml logs -f
docker compose -f compose.yaml -f compose.dev.yaml exec attendee npm run lint
docker compose -f compose.yaml -f compose.dev.yaml exec checkin npm run lint
docker compose -f compose.yaml -f compose.dev.yaml down
```

For a local production-build preview (no hot reload):

```sh
docker compose up -d --build
bash tests/smoke-test.sh
```

Use `--build` when switching back to development or changing Dockerfiles.
Both modes use the same local PostgreSQL data volume. `down` preserves data;
do not use `down -v` unless you intend to delete it.

## Publish images

Set a new `IMAGE_TAG` in each changed repo's `.env`. Set `CR_PAT` securely in your
environment with GHCR `write:packages` permission; never put credentials in git.
Then publish all five images:

```sh
bash publish-images.sh
```

Alternatively run `bash docker-push.sh` in just the changed repo. The React
images contain built static assets and nginx, not Node or Vite.
Use unique release tags; do not overwrite a deployed tag.

## Deploy to a server

The server needs Docker with the Compose plugin, but not Node, Python, the sibling
repos, or source builds. Clone this repo there, then:

```sh
cp .env.production.example .env.production
# Edit .env.production: choose the published tag for each service.
openssl rand -base64 32 > secrets/postgres_password
# If GHCR packages are private, log in with a read:packages token first.
docker login ghcr.io
docker compose --env-file .env.production -f compose.deploy.yaml pull
docker compose --env-file .env.production -f compose.deploy.yaml up -d --wait --wait-timeout 120
bash tests/smoke-test.sh
```

Generate the password only during first-time setup, and protect and back up that
file. The deployment mounts it as a Docker secret and stores database data in a
persistent volume. The default secret path is `./secrets/postgres_password`;
`POSTGRES_PASSWORD_FILE` can select an existing file instead.

Only the gateway is published, on `127.0.0.1:8080` by default. Put your server's
HTTPS reverse proxy in front of it, forwarding the original host and WebSocket
upgrade headers. App and backend containers are internal, and deployment does
not publish PostgreSQL. `HTTP_BIND_ADDRESS` and `HTTP_PORT` in `.env.production`
configure the gateway's binding; do not expose it directly over plain HTTP.

**HTTPS is required for check-in camera access on phones.** `localhost` works
for desktop development, but a plain HTTP LAN address does not. Certificates,
the public domain, and HTTPS ingress must be configured on your server.

For updates, change the affected image tags in `.env.production`, repeat `pull`
and `up`, then run the smoke test. Keep the previous tags to roll back application
images. Future database schema changes will need a separate migration and backup
plan; changing the database image is not a substitute for one.

## Validation

```sh
bash tests/frontend-publish-test.sh # mocked Docker; never uploads images
bash tests/smoke-test.sh            # checks running production routes and API
```

See each sibling repo's README for its standalone development and publishing.
