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

Each publishing script publishes its current `major.minor.patch` tag, then
increments the patch number in that repo's `.env` **only after the push succeeds**:
`0.0.1` is published, and `.env` becomes `0.0.2` for the next release.
Login, build, or push failures leave the version unchanged. Commit the updated
version files so other machines use the next available version. Do not run
publishes concurrently or from copies with stale version files.

The incremented version is **not yet published**. For deployment use the tag
printed in the `Published ...` line, not the new value in `.env`. This also
means `up --no-build` in a sibling repo will require a previously published tag.
Scripts do not check whether a registry tag already exists: a retry after an
interrupted push, or a stale version file, can still overwrite that tag.
For versions already pushed before enabling this feature, advance `.env` once
before publishing again to avoid replacing them.

Set a new `IMAGE_TAG` in each changed repo's `.env`. Set `CR_PAT` securely in your
environment with GHCR `write:packages` permission; never put credentials in git.
Then publish images from all five repos (the web-server repo publishes both nginx
and Certbot, for six images total):

```sh
bash publish-images.sh
```

Alternatively run `bash docker-push.sh` in just the changed repo. The React
images contain built static assets and nginx, not Node or Vite.
Use unique release tags; do not overwrite a deployed tag.

## Deploy to a server

Deployment uses HTTPS by default. The server needs Docker with the Compose
plugin, but not Node, Python, the sibling repos, or source builds. Clone this
repo there, then:

```sh
cp .env.production.example .env.production
# Edit .env.production: choose the published tag for each service.
openssl rand -base64 32 > secrets/postgres_password
# Set CR_PAT securely in the environment (classic PAT with read:packages).
bash pull-images.sh
bash setup-https.sh your-email@example.com # first-time certificate issuance only
bash tests/smoke-test.sh https://event.onsite-print.dk
```

`pull-images.sh` validates the deployment configuration, logs in to GHCR using
`CR_PAT` over standard input, and pulls the selected versions. It does not start
containers or change version files. `GHCR_USERNAME` defaults to `groskopf`; set
it to the token owner's GitHub username if different. The token's account needs
read access to all six packages, including `onsite-print-certbot`. Never store the PAT in `.env.production` or git.
Docker retains the login; use a credential helper for secure credential storage.
Public packages can instead be pulled anonymously with
`docker compose --env-file .env.production -f compose.deploy.yaml pull`.

`start-server.sh` starts the deployment in the background and waits up to 120
seconds for services to become healthy. It uses already pulled images and does
not log in or download images; run `pull-images.sh` first for new versions.
Both helpers work from any directory and use this repo's `.env.production`.
To stop the deployment:

```sh
bash stop-server.sh
```

Stopping removes containers and the Compose network but preserves the database
volume and password file. Neither helper changes version files or requires
`CR_PAT`. Command failures are returned without reporting success.

Generate the password only during first-time setup, and protect and back up that
file. The deployment mounts it as a Docker secret and stores database data in a
persistent volume. The default secret path is `./secrets/postgres_password`;
`POSTGRES_PASSWORD_FILE` can select an existing file instead.

Only the gateway is published, on ports 80 and 443 by default. Allow inbound
TCP 80 and 443 in the cloud and host firewalls. Port 80 serves certificate
validation only; normal HTTP requests return 403. Apps and the API use HTTPS.
App and backend containers are internal; deployment does not publish PostgreSQL.

`HTTP_BIND_ADDRESS` and `HTTP_PORT` in `.env.production` configure the binding.
Set them to `0.0.0.0` and `80`; `HTTPS_PORT` defaults to `443`.
Changing the example file alone has no effect on an existing `.env.production`.
Local development remains on port 8080.

The API currently has no authentication; HTTPS encrypts traffic but does not
restrict who can call it. Restrict access to trusted clients while testing.

**HTTPS is required for check-in camera access on phones.** `localhost` works
for desktop development, but a plain HTTP LAN address does not. The Docker-based
Let's Encrypt setup below provides HTTPS directly in the nginx gateway.

For updates, change the affected image tags in `.env.production`, repeat `pull`
and `up`, then run the smoke test. Keep the previous tags to roll back application
images. Future database schema changes will need a separate migration and backup
plan; changing the database image is not a substitute for one.

## HTTPS with automatic Let's Encrypt renewal

`compose.deploy.yaml` includes HTTPS and Certbot by default. The web-server repo
owns the TLS templates, nginx certificate watcher, renewal loop, and their tests.
They are baked into its nginx and Certbot images; the deployed server needs no
TLS source bind mounts or additional Compose override. Local development is
unchanged.

### First-time setup on the deployed server

1. Point `event.onsite-print.dk` to the server's public IP. Its A record currently
   points to `34.51.225.22`. If you add an AAAA record, IPv6 must also reach nginx.
2. Allow inbound TCP **80 and 443**. Keep `HTTP_BIND_ADDRESS=0.0.0.0` and
   `HTTP_PORT=80`. HTTP-01 certificate validation requires public port 80.
3. Add `TLS_DOMAIN=event.onsite-print.dk` and `HTTPS_PORT=443` to
   `.env.production`. Select the already published application image tags.
4. Pull images, then request the certificate with your real contact email:

```sh
bash pull-images.sh
bash setup-https.sh your-email@example.com
bash tests/smoke-test.sh https://event.onsite-print.dk
```

The setup script agrees to Let's Encrypt's terms, temporarily stops nginx and
the renewal container, and requests the certificate using port 80. After
issuance it starts the full HTTPS stack and waits for healthy services.
If issuance fails, nginx remains stopped and the script returns an error.
Fix DNS/firewall/email problems before retrying. There is no HTTP-only deployment
fallback; the gateway requires a certificate before it can start.

Open <https://event.onsite-print.dk/attendee/>,
<https://event.onsite-print.dk/checkin/>, or
<https://event.onsite-print.dk/api/v2/docs>. Normal HTTP requests return 403;
only the ACME challenge path is publicly served over HTTP. The HTTP health
endpoint is accessible only from container loopback. Port 80 must remain open
in the firewall for automatic certificate renewal; use HTTPS for all app and
API access. Local development stays on HTTP.

### Renewal and updates

Certbot checks for renewal immediately at startup and every **12 hours**. It
uses a shared webroot served by nginx on port 80, without interrupting HTTPS.
nginx checks certificate and key contents every **60 seconds**. When they
change, it validates the configuration and gracefully reloads to load the
renewed certificate. A failed validation/reload is logged and retried, and the
running nginx process keeps its previously loaded certificate.

No Docker socket or host cron job is exposed to either container. Certificates
and renewal settings live in the persistent `letsencrypt` volume, writable by
Certbot and read-only in nginx. Back up this volume securely; it contains private
keys. Never run `down -v` on the deployment.

Use the standard deployment helpers (no `--https` flag):

```sh
bash pull-images.sh
bash start-server.sh
bash stop-server.sh
```

Do not change `TLS_DOMAIN` without issuing a certificate for the new domain.

### Checking for an existing certificate

```sh
bash check-certificate.sh
```

It exits `0` when `live/$TLS_DOMAIN/fullchain.pem` and `privkey.pem` exist in
the `letsencrypt` volume, and `3` when they are missing. `start-server.sh`
runs this check first and refuses to start without a certificate.
`setup-https.sh` skips issuance and only starts the stack if a certificate
already exists. This avoids reaching Let's Encrypt rate limits.

### Removing an old setup or certificate

If the old `compose.https.yaml` override is still running, stop it once using
the old command. Then remove the old local override and TLS files:

```sh
docker compose --env-file .env.production -f compose.deploy.yaml -f compose.https.yaml down
rm -f compose.https.yaml && rm -rf tls
git status   # confirm that no other local changes remain
```

`bash start-server.sh` reuses the existing certificate volume. If
containers from the old setup remain, run
`docker compose --env-file .env.production -f compose.deploy.yaml up -d --remove-orphans`.

To replace a certificate, such as a wrong domain or a staging certificate,
delete it, then issue a new one:

```sh
bash stop-server.sh
docker compose --env-file .env.production -f compose.deploy.yaml run --rm --no-deps --entrypoint certbot certbot certificates
docker compose --env-file .env.production -f compose.deploy.yaml run --rm --no-deps --entrypoint certbot certbot delete --cert-name event.onsite-print.dk
bash check-certificate.sh   # should now report: No HTTPS certificate found
bash setup-https.sh your-email@example.com
```

To remove **all** Let's Encrypt data, including account and private keys,
remove the volume instead of running `certbot delete`. Back it up first.
Never use `down -v`, because it also deletes the database volume:

```sh
bash stop-server.sh
docker volume ls | grep letsencrypt          # e.g. onsite-print-server_letsencrypt
docker volume rm onsite-print-server_letsencrypt
```

Let's Encrypt limits duplicate certificates to 5 per week. Only remove and
reissue a certificate when necessary.

Check renewal logs and run a staging renewal test after initial setup:

```sh
docker compose --env-file .env.production -f compose.deploy.yaml logs --tail 100 certbot nginx
docker compose --env-file .env.production -f compose.deploy.yaml run --rm --no-deps --entrypoint certbot certbot renew --dry-run --webroot --webroot-path /var/www/certbot
```

Monitor these logs and certificate expiry; automated retries do not notify an
operator of sustained failures. HTTPS does not add authentication to the API.

### Updating an existing HTTPS deployment

Publish a new version from `onsite-print-web-server` with `bash docker-push.sh`.
It publishes both `onsite-print-web-server` and `onsite-print-certbot` using the
same tag. Set `WEB_SERVER_TAG` on the server to that published tag, update this
repo, then run `bash pull-images.sh` and `bash start-server.sh`.
The existing `letsencrypt` and `acme-webroot` volumes are reused when the Compose
project name/directory is unchanged. Do not request another certificate if one
already exists (`bash check-certificate.sh`). See
[Removing an old setup or certificate](#removing-an-old-setup-or-certificate).
The new Certbot GHCR package must be accessible to your pull token.

## Validation

```sh
bash tests/frontend-publish-test.sh # mocked Docker; never uploads images
bash tests/pull-images-test.sh      # mocked Docker; no registry login or downloads
bash tests/server-scripts-test.sh   # mocked Docker; does not start or stop containers
bash tests/setup-https-test.sh      # mocked issuance; no live certificate requests
bash ../onsite-print-web-server/tests/https-test.sh # builds image, tests reload in ~60s
bash ../onsite-print-web-server/tests/renew-certificates-test.sh
bash tests/smoke-test.sh https://event.onsite-print.dk # omit URL for local port 8080
```

See each sibling repo's README for its standalone development and publishing.
