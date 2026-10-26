# onsite-print-server

Starts the onsite-print services with Docker Compose. Local builds use sibling
repos; server deployments use published images and need only this repo.

- `../onsite-print-web-server` – nginx, http://localhost:8080; forwards `/api/` to the backend
- `../onsite-print-backend` – FastAPI REST API, http://localhost:8080/api/v2/docs
- `../onsite-print-database` – PostgreSQL, `127.0.0.1:5432` (`postgres:5432` inside the Compose network)
- `../onsite-print-attendee` – http://localhost:8080/attendee/
- `../onsite-print-checkin` – http://localhost:8080/checkin/
- `../onsite-print-admin` – http://localhost:8080/admin/
- `../onsite-print-event` – event-code facilitator workspace, http://localhost:8080/event/

The apps call the same-origin `/api/v2/` API; no separate API hostname or CORS
configuration is needed. nginx preserves each app's path prefix.

## Local development

### VS Code dev containers

Development containers belong to the repositories containing the application
code, rather than this Compose orchestration repository:

- [onsite-print-backend](../onsite-print-backend/README.md#develop): Python 3.12,
  backend dependencies, pytest/httpx, Docker tools, and PostgreSQL client tools.
- [onsite-print-attendee](../onsite-print-attendee/README.md#start-in-the-dev-container):
  Node.js 24, npm, and ESLint.
- [onsite-print-checkin](../onsite-print-checkin/README.md#start-in-the-dev-container):
  Node.js 24, npm, and ESLint.
- [onsite-print-admin](../onsite-print-admin/README.md#start-in-the-dev-container):
  Node.js 24, npm, and ESLint.
- [onsite-print-event](../onsite-print-event/README.md#start-in-the-dev-container):
  Node.js 24, npm, and ESLint.

Install Docker and the VS Code **Dev Containers** extension, open the relevant
repository folder in its own VS Code window, and run **Dev Containers: Reopen
in Container**. Reopening does not start the full application stack or reset data.
Run the Compose tasks below from this repository on the host.

The backend's Python source is in `../onsite-print-backend/app/`, not in this
repository. The multi-root
[onsite-print-server.code-workspace](onsite-print-server.code-workspace)
is still available for a host-side overview; opening individual repositories
selects their respective development environments.

### Starting the application stack

Open this repo in VS Code and press **Ctrl+Shift+B** to run **Onsite Print: Start
development server**. It builds the images, starts the hot-reload stack, and waits
for startup. Containers keep running after the task completes. Use **Terminal >
Run Task > Onsite Print: Stop development server** to stop them without deleting
database data. The tasks are defined in [.vscode/tasks.json](.vscode/tasks.json).
The sibling repos and database password file below must already exist.

Clone all repos next to each other:

```sh
mkdir onsite-print && cd onsite-print
for r in onsite-print-server onsite-print-web-server onsite-print-backend onsite-print-database onsite-print-attendee onsite-print-checkin onsite-print-admin onsite-print-event; do
  git clone git@github.com:groskopf/$r.git
done
openssl rand -base64 32 > onsite-print-database/secrets/postgres_password
cd onsite-print-server
docker compose -f compose.yaml -f compose.dev.yaml up -d --build
```

Only create the password file if it does not already exist. PostgreSQL initializes
its password on first start; overwriting the file does not change an existing
database user's password.

Edit any React repo and Vite updates the page through nginx, including its
WebSocket connection. Dependencies live in Docker volumes, separate from the
host's `node_modules`. `npm ci` runs when each dev container starts; restart that
service after changing its package lockfile. Backend source changes also reload
automatically. Rebuild after changing backend dependencies.
After editing the gateway's nginx configuration, restart its service to reload it.

```sh
docker compose -f compose.yaml -f compose.dev.yaml logs -f
docker compose -f compose.yaml -f compose.dev.yaml exec attendee npm run lint
docker compose -f compose.yaml -f compose.dev.yaml exec checkin npm run lint
docker compose -f compose.yaml -f compose.dev.yaml exec admin npm run lint
docker compose -f compose.yaml -f compose.dev.yaml exec event npm run lint
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

Each image-owning repo (`web-server`, `database`, `backend`, `attendee`,
`checkin`, `admin`, `event`) publishes its own image(s) from its current
`major.minor.patch` tag in `.env`, then increments the patch number **only
after the push succeeds**: `0.0.1` is published, and `.env` becomes `0.0.2`
for the next release. Login, build, or push failures leave the version
unchanged.

The recommended way to publish is to trigger that repo's **Publish release**
GitHub Actions workflow (`workflow_dispatch` only, run from `main`) from its
Actions tab. It builds and pushes the image(s) to GHCR using the built-in
`GITHUB_TOKEN`, tags the published commit on `main` with the published
version (no `v` prefix), and commits the incremented `.env` back to `main` —
no local credentials or manual commits needed. Each repo's README documents
the one-time branch-protection bypass this requires.

Alternatively, publish locally: set a new `IMAGE_TAG` in the changed repo's
`.env`, set `CR_PAT` securely in your environment with GHCR `write:packages`
permission, and run `bash docker-push.sh` in that repo (the web-server repo
publishes both nginx and Certbot). The incremented version is **not yet
published**; for deployment use the tag printed in the `Published ...` line,
not the new value in `.env`. This also means `up --no-build` in a sibling
repo will require a previously published tag. Scripts do not check whether a
registry tag already exists: a retry after an interrupted push, or a stale
version file, can still overwrite that tag. For versions already pushed
before enabling this feature, advance `.env` once before publishing again to
avoid replacing them. Commit the updated version file so other machines use
the next available version. Do not run publishes concurrently or from copies
with stale version files, and never put credentials in git.

The React images contain built static assets and nginx, not Node or Vite.
Use unique release tags; do not overwrite a deployed tag.

Publishing an image does not deploy it. `.env.production` in this repo is the
single source of truth for which published version of each image is deployed,
and it is committed directly to git (not a `.example` template) specifically
so that checking out a commit of this repo pins the exact image versions it
deploys. After publishing a new version, manually set the matching `*_TAG` in
`.env.production` to that version and commit the change here — there is no
sibling-repo clone or extra sync script involved; see "Deploy to a server"
below to roll the change out.

## Deploy to a server

Deployment uses HTTPS by default. The server needs Docker with the Compose
plugin, but not Node, Python, the sibling repos, or source builds. Clone this
repo there, then:

```sh
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
read access to all eight packages, including `onsite-print-certbot`,
`onsite-print-admin`, and `onsite-print-event`. Never store the PAT in `.env.production` or git.
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
Edits only take effect on the server after pulling the updated `.env.production`
commit and restarting the stack (`bash start-server.sh`).
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
the `letsencrypt` volume, and `3` when they are missing. Run this check before
starting if you are unsure whether a certificate has been set up.
`start-server.sh` does not run this check automatically; nginx fails to start
if the required certificate files are missing. Run
`bash setup-https.sh your-email@example.com` for first-time certificate setup.
`setup-https.sh` skips issuance and only starts the stack if a certificate
already exists. This avoids reaching Let's Encrypt rate limits.

`bash start-server.sh` reuses the existing certificate volume. If containers
from an earlier deployment remain, run
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
already exists (`bash check-certificate.sh`). The new Certbot GHCR package must
be accessible to your pull token.

## Validation

### Admin deployment

The local stack includes the admin app at `/admin/`, with Vite hot reload in
development. Production deployment also includes the admin service and waits
for it to be healthy before starting nginx. Set `ADMIN_TAG` in `.env.production`
to a published `onsite-print-admin` version. Publish an updated web-server image
and set `WEB_SERVER_TAG` to its published version so HTTP and HTTPS gateways
include the `/admin/` route. No images are published by starting the local stack.

Adding the admin site does not add authentication or authorization. Do not expose
it as a secured administration interface until backend access controls from the
[security plan](../onsite-print-backend/docs/security.md) are implemented.

### Event deployment

The local stack includes the facilitator event-code app at `/event/`, with Vite
hot reload in development. Production deployment also includes the event service
and waits for it to be healthy before starting nginx. Set `EVENT_TAG` in
`.env.production` to a published `onsite-print-event` version. Publish an updated
web-server image and set `WEB_SERVER_TAG` to its published version so HTTP and
HTTPS gateways include the `/event/` route. No images are published by starting
the local stack.

### Test coverage

GitHub Actions runs the mocked HTTPS setup test and production-stack smoke test
on pushes and pull requests using the shared runner, `run-tests.sh`.
Publishing-script tests run in each image-owning repository's own workflow, so
they always test the script from the same revision as the tests.

CI pulls the five GHCR images pinned by digest in `compose.test.yaml`: web-server
0.0.2 and database/backend/attendee/checkin 0.0.1. It does not check out sibling
repos or build images. This HTTP-only test stack uses a separate Compose project,
test database volume, generated password, and dynamically assigned loopback port.
It does not use deployment data, Certbot, or real certificates. CI removes its
test containers and volume afterward, and prints stack logs on failure.

The smoke test checks attendee, check-in, admin, and event by default. Historical
pinned-image CI explicitly sets `SMOKE_APPS="attendee checkin"` because those
releases predate the admin and event apps and their gateway routes. Admin and
event routing must also be smoke-tested against local production builds or a
deployment; add them to pinned CI when admin, event, and updated gateway
release digests are available.

For private GHCR packages, grant this repository **Actions read access** under
each package's **Manage Actions access** settings. CI uses `GITHUB_TOKEN` with
`packages: read`; it does not require a PAT. Fork pull requests may not have
access to private packages.

After publishing a release, update the relevant image digest and version comment
in `compose.test.yaml` explicitly. Find the digest with
`docker pull ghcr.io/groskopf/onsite-print-attendee:<published-tag>` followed by
`docker image inspect ghcr.io/groskopf/onsite-print-attendee:<published-tag> --format '{{json .RepoDigests}}'`.
Digest pinning prevents a replaced tag from silently changing the tested image.

In VS Code, use **Terminal > Run Task > Onsite Print: Run tests** for the mocked
test. It does not require sibling repos, start containers, publish images, or
request certificates.

**Onsite Print: Run full test suite** adds the smoke test against
`http://localhost:8080`. Start the local production-build preview first
(`docker compose up -d --build`); the smoke test does not support the hot-reload
development stack. Neither test task starts or stops containers.

The same runner can be used from the terminal:

```sh
bash run-tests.sh
bash run-tests.sh --smoke
bash run-tests.sh --smoke https://event.onsite-print.dk
```

To smoke-test the same pinned images as CI locally, run this isolated stack
(log in to GHCR first if the packages are private):

```sh
export COMPOSE_FILE=compose.test.yaml COMPOSE_PROJECT_NAME=onsite-print-tests
export POSTGRES_PASSWORD_FILE="$(mktemp)"
openssl rand -base64 32 > "$POSTGRES_PASSWORD_FILE"
chmod 644 "$POSTGRES_PASSWORD_FILE" # disposable test secret, readable by non-root backend
docker compose pull
docker compose up -d --no-build --pull never --wait --wait-timeout 300
bash run-tests.sh --smoke "http://$(docker compose port nginx 80)"
docker compose down -v # deletes only this isolated test project's data
rm -f -- "$POSTGRES_PASSWORD_FILE"
unset COMPOSE_FILE COMPOSE_PROJECT_NAME POSTGRES_PASSWORD_FILE
```

Individual tests and the web-server repo's additional TLS tests:

```sh
bash tests/setup-https-test.sh      # mocked issuance; no live certificate requests
bash ../onsite-print-web-server/tests/https-test.sh # builds image, tests reload in ~60s
bash ../onsite-print-web-server/tests/renew-certificates-test.sh
bash tests/smoke-test.sh https://event.onsite-print.dk # omit URL for local port 8080
```

See each sibling repo's README for its standalone development and publishing.
