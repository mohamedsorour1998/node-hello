# node-hello — CI/CD, Containerization & Terraform Deployment

A small Node.js "Hello World" web app, wired up end-to-end with a DevOps
workflow:

- **Containerized** with a multi-stage, non-root Dockerfile.
- **CI/CD** with GitHub Actions: lint → test → build → push to GitHub
  Container Registry (GHCR).
- **Deployed** locally with Terraform using the Docker provider (driven here by
  rootless **Podman**, which exposes a Docker-compatible API).
- **Monitored** with New Relic (APM + application log forwarding).

> Forked from [`johnpapa/node-hello`](https://github.com/johnpapa/node-hello)
> and extended for this assignment.

---

## Table of contents

1. [Architecture](#architecture)
2. [Repository layout](#repository-layout)
3. [The application](#the-application)
4. [Local development](#local-development)
5. [Container image (Docker / Podman)](#container-image-docker--podman)
6. [CI/CD pipeline (GitHub Actions)](#cicd-pipeline-github-actions)
7. [Deployment with Terraform](#deployment-with-terraform)
8. [Monitoring & logging (New Relic)](#monitoring--logging-new-relic)
9. [Configuration reference](#configuration-reference)
10. [Assumptions](#assumptions)

---

## Architecture

```
                         push / PR
   Developer ─────────────────────────────▶ GitHub
                                              │
                                              ▼
                                   GitHub Actions (CI/CD)
                                   ┌────────────────────────────┐
                                   │ 1. Lint  (eslint)          │
                                   │ 2. Test  (node --test)     │
                                   │ 3. Build (Docker Buildx)   │
                                   │ 4. Push  ──▶ GHCR image    │
                                   └────────────────────────────┘
                                              │
                    ghcr.io/mohamedsorour1998/node-hello:latest
                                              │
                       terraform apply        ▼
   Operator ───────────────────────▶ Docker/Podman provider ──▶ Container
                                                                   │  stdout logs + APM
                                                                   ▼
                                                              New Relic
```

## Repository layout

```
.
├── index.js                 # Entrypoint: New Relic hook + graceful shutdown
├── lib/
│   ├── server.js            # HTTP server factory (routes: / and /health)
│   └── logger.js            # Dependency-free structured JSON logger
├── newrelic.js              # New Relic agent config (env-driven, no secrets)
├── test/
│   └── app.test.js          # node:test smoke tests (/ and /health)
├── eslint.config.js         # ESLint flat config
├── Dockerfile               # Multi-stage, non-root, HEALTHCHECK
├── .dockerignore
├── .github/workflows/ci.yml # Lint → Test → Build → Push (GHCR)
├── terraform/               # Local deployment via the Docker provider
│   ├── versions.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── .env.example
└── README.md
```

## The application

A minimal HTTP server (Node core `http`, no web framework) exposing:

| Method | Path       | Response                                  |
| ------ | ---------- | ----------------------------------------- |
| GET    | `/`        | `Hello Node!` (text/plain)                |
| GET    | `/health`  | `{"status":"ok","uptime":<seconds>}` JSON |

It also emits one **structured JSON log line per event** to stdout and handles
`SIGTERM`/`SIGINT` for **graceful shutdown** (important for clean container
stops and zero-dropped-request restarts).

## Local development

Requires Node.js 20+ (developed and tested on Node 22).

```bash
npm ci            # install dependencies from the lockfile
npm run lint      # ESLint
npm test          # node --test
npm start         # run on http://localhost:3000
```

Quick check:

```bash
curl localhost:3000/          # Hello Node!
curl localhost:3000/health    # {"status":"ok","uptime":...}
```

To run with New Relic locally, copy `.env.example` to `.env` and set
`NEW_RELIC_LICENSE_KEY`. `.env` is gitignored.

## Container image (Docker / Podman)

The commands below use `podman`, but `docker` is a drop-in replacement (swap
the binary name).

```bash
# Build. NOTE: with Podman add `--format docker` so the HEALTHCHECK is kept
# (OCI images drop it). Docker/BuildKit keeps it by default.
podman build --format docker -t node-hello:local .

# Run
podman run -d --name node-hello -p 8080:3000 node-hello:local

# Verify
curl localhost:8080/            # Hello Node!
curl localhost:8080/health      # {"status":"ok",...}
podman inspect --format '{{.State.Health.Status}}' node-hello   # healthy

# Stop (graceful) & remove
podman rm -f node-hello
```

Image characteristics:

- `node:22-alpine` base, multi-stage build (~220 MB).
- Runs as the non-root `nodejs` user.
- Production-only dependencies (`npm ci --omit=dev`).
- Built-in `HEALTHCHECK` hitting `/health`.

## CI/CD pipeline (GitHub Actions)

Workflow: [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

**Triggers:** push to `master`/`main`, pull requests, and manual
`workflow_dispatch`.

**Jobs:**

1. **`lint-and-test`** — Node 22, `npm ci`, `npm run lint`, `npm test`.
2. **`build-and-push`** (needs `lint-and-test`) — builds the image with Docker
   Buildx and pushes to GHCR.
   - Authenticates with the built-in `GITHUB_TOKEN` (no extra secrets needed).
   - Tags via `docker/metadata-action`: `latest` (default branch), the commit
     SHA, and the branch/PR ref.
   - Layer caching via GitHub Actions cache (`type=gha`).
   - **Pull requests build but do not push** (validation without publishing).

**Published image:**

```
ghcr.io/mohamedsorour1998/node-hello:latest
```

### Running the pipeline

Just push to the repo (or open a PR):

```bash
git add .
git commit -m "ci: trigger pipeline"
git push origin master
```

Watch it:

```bash
gh run watch          # or: gh run list / gh run view --log
```

The required `NEW_RELIC_LICENSE_KEY` secret (see below) can be set with:

```bash
gh secret set NEW_RELIC_LICENSE_KEY -R mohamedsorour1998/node-hello
```

### Making the image pullable

Packages published to GHCR are **private by default**. To let Terraform (or
anyone) pull without credentials, mark the package **public** once:

`GitHub → your profile → Packages → node-hello → Package settings → Change
visibility → Public`

Otherwise authenticate first:

```bash
echo $CR_PAT | podman login ghcr.io -u mohamedsorour1998 --password-stdin
```

## Deployment with Terraform

Terraform (`terraform/`) uses the [`kreuzwerker/docker`] provider to run the
container locally. Because Podman exposes a Docker-compatible API socket, the
same provider works against Podman with **no daemon and no root**.

[`kreuzwerker/docker`]: https://registry.terraform.io/providers/kreuzwerker/docker/latest

### Prerequisites

Enable the rootless Podman API socket (one-time):

```bash
systemctl --user enable --now podman.socket
ls -l /run/user/$(id -u)/podman/podman.sock   # confirm it exists
```

(Alternatively, point `docker_host` at a real Docker daemon such as
`unix:///var/run/docker.sock`.)

### Configure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   - set docker_host to your socket (run `id -u` to get your UID)
#   - either keep the GHCR image (make the package public), or
#     set build_local = true to build straight from the Dockerfile
#   - optionally set newrelic_license_key
```

`terraform.tfvars` is **gitignored** so your key never gets committed. You can
also pass the key via the environment instead:

```bash
export TF_VAR_newrelic_license_key="<your-key>"
```

### Apply

```bash
terraform init
terraform apply        # review the plan, then approve

# Outputs include the URLs:
curl "$(terraform output -raw app_url)"       # Hello Node!
curl "$(terraform output -raw health_url)"    # {"status":"ok",...}
```

### Destroy

```bash
terraform destroy
```

### Deployment options

| Goal                                   | Setting                                     |
| -------------------------------------- | ------------------------------------------- |
| Run the image published by CI (GHCR)   | `build_local = false` (default) + public pkg |
| Build & run straight from source       | `build_local = true`                        |
| Use real Docker instead of Podman      | `docker_host = "unix:///var/run/docker.sock"` |

> **Cloud note:** the assignment allows a local Docker-provider deployment
> _or_ a cloud free tier. This repo implements the **local** option. The same
> image in GHCR could be deployed to ECS/EKS/a k8s cluster by swapping the
> Terraform provider/resources; the app is stateless and container-ready.

## Monitoring & logging (New Relic)

The New Relic Node.js agent is included as a dependency and configured in
[`newrelic.js`](newrelic.js) entirely from environment variables.

- The agent loads **only when `NEW_RELIC_LICENSE_KEY` is set** (see the top of
  `index.js`), so local dev/CI stay clean.
- **`application_logging.forwarding` is enabled**, so the app's stdout JSON
  logs are shipped to New Relic (log aggregation, "logs in context") — no
  separate log shipper required.
- APM (transactions, distributed tracing) and log→metrics are enabled too.
- Sensitive request/response headers (cookies, authorization) are excluded from
  captured attributes.

Enable it by providing the key at runtime — via `terraform.tfvars`
(`newrelic_license_key`), `TF_VAR_newrelic_license_key`, `.env`, or
`podman run -e NEW_RELIC_LICENSE_KEY=...`. Data then appears in New Relic under
the app name **`node-hello`** (APM & Services, and Logs).

## Configuration reference

| Variable                 | Default       | Description                                   |
| ------------------------ | ------------- | --------------------------------------------- |
| `PORT`                   | `3000`        | HTTP listen port                              |
| `HOST`                   | `0.0.0.0`     | HTTP bind address                             |
| `LOG_LEVEL`              | `info`        | App log level (`debug`/`info`/`warn`/`error`) |
| `SHUTDOWN_TIMEOUT_MS`    | `10000`       | Grace period before forced exit               |
| `NEW_RELIC_LICENSE_KEY`  | _(unset)_     | Enables New Relic when present                |
| `NEW_RELIC_APP_NAME`     | `node-hello`  | New Relic application name                    |
| `NEW_RELIC_LOG_LEVEL`    | `info`        | New Relic agent log level                     |

## Assumptions

- **"Fork the provided repo"** → the app was forked from
  `johnpapa/node-hello` into `mohamedsorour1998/node-hello`, then extended.
- **Registry** → GitHub Container Registry (GHCR) was chosen over Docker Hub
  because it authenticates with the built-in `GITHUB_TOKEN`, needing no extra
  credentials. The image name follows the repo: `ghcr.io/<owner>/node-hello`.
- **Deployment target** → the **local Docker-provider** option was chosen. The
  environment has no Docker daemon and no root, so **rootless Podman** provides
  the Docker-compatible API the Terraform provider talks to. Commands use
  `podman`, but `docker` is interchangeable.
- **`docker_host` default** assumes UID `1000`
  (`unix:///run/user/1000/podman/podman.sock`). Adjust to your `id -u`.
- **GHCR visibility** → images are private by default; the package must be made
  public (or `podman login` used) for a credential-free `terraform apply`.
  `build_local = true` avoids this entirely for a self-contained local run.
- **New Relic** → the provided license key is treated as a secret: stored as a
  GitHub Actions secret and in gitignored local files (`.env`,
  `terraform.tfvars`), never committed. US data-center endpoint assumed.
- **Security** → this is a public, unauthenticated demo endpoint by design (no
  sensitive data). A real deployment would add TLS, authentication, and network
  controls (e.g., an ingress/load balancer).
- **Time-box** → scoped to the assignment's 8-hour guidance; kept intentionally
  small and readable rather than over-engineered.
