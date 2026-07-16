# node-hello — CI/CD, Containerization & Terraform Deployment

A small Node.js "Hello World" web app, wired up end-to-end with a DevOps
workflow:

- **Containerized** with a multi-stage, non-root Dockerfile.
- **CI/CD** with GitHub Actions: lint → test → build → push to GitHub
  Container Registry (GHCR).
- **Deployed** with Terraform two ways:
  - **locally** via the Docker provider (driven here by rootless **Podman**), and
  - to **AWS ECS (Fargate)** using the `terraform-aws-modules/ecs` module.
- **Monitored** with New Relic (APM + application log forwarding), plus
  CloudWatch Logs on ECS.

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
   - [Local (Docker / Podman)](#local-docker--podman)
   - [AWS ECS (Fargate)](#aws-ecs-fargate)
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
                    ┌─────────────────────────┴─────────────────────────┐
             terraform apply                                     terraform apply
             (terraform/)                                        (terraform/ecs/)
                    │                                                    │
                    ▼                                                    ▼
        Docker / Podman provider                          AWS ECS Fargate service
        local container :8080                             task w/ public IP :3000
                    │                                        │  + CloudWatch Logs
                    └───────────────────┬────────────────────┘
                                        ▼
                            stdout JSON logs + APM
                                        │
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
│   ├── terraform.tfvars.example
│   └── ecs/                 # AWS ECS Fargate deployment
│       ├── versions.tf
│       ├── variables.tf
│       ├── main.tf
│       ├── outputs.tf
│       └── terraform.tfvars.example
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

The `NEW_RELIC_LICENSE_KEY` secret (used for runtime monitoring) can be set with:

```bash
gh secret set NEW_RELIC_LICENSE_KEY -R mohamedsorour1998/node-hello
```

### Making the image pullable

Packages published to GHCR are **private by default**. To let Terraform/ECS (or
anyone) pull without credentials, mark the package **public** once:

`GitHub → your profile → Packages → node-hello → Package settings → Change
visibility → Public`

Otherwise authenticate first:

```bash
echo $CR_PAT | podman login ghcr.io -u mohamedsorour1998 --password-stdin
```

## Deployment with Terraform

The assignment allows a local Docker-provider deployment **or** a cloud free
tier — this repo implements **both**.

### Local (Docker / Podman)

Terraform in [`terraform/`](terraform/) uses the [`kreuzwerker/docker`] provider
to run the container locally. Because Podman exposes a Docker-compatible API
socket, the same provider works against Podman with **no daemon and no root**.

[`kreuzwerker/docker`]: https://registry.terraform.io/providers/kreuzwerker/docker/latest

Enable the rootless Podman API socket (one-time):

```bash
systemctl --user enable --now podman.socket
ls -l /run/user/$(id -u)/podman/podman.sock   # confirm it exists
```

(Alternatively, point `docker_host` at a real Docker daemon such as
`unix:///var/run/docker.sock`.)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   - set docker_host to your socket (run `id -u` to get your UID)
#   - either keep the GHCR image (make the package public), or
#     set build_local = true to build straight from the Dockerfile
#   - optionally set newrelic_license_key

terraform init
terraform apply

curl "$(terraform output -raw app_url)"       # Hello Node!
curl "$(terraform output -raw health_url)"    # {"status":"ok",...}

terraform destroy
```

`terraform.tfvars` is **gitignored** so your key never gets committed. You can
also pass the key via `export TF_VAR_newrelic_license_key="<your-key>"`.

| Goal                                   | Setting                                       |
| -------------------------------------- | --------------------------------------------- |
| Run the image published by CI (GHCR)   | `build_local = false` (default) + public pkg  |
| Build & run straight from source       | `build_local = true`                          |
| Use real Docker instead of Podman      | `docker_host = "unix:///var/run/docker.sock"` |

### AWS ECS (Fargate)

Terraform in [`terraform/ecs/`](terraform/ecs/) runs the same GHCR image as an
**AWS ECS Fargate** service (serverless containers), using the community
[`terraform-aws-modules/ecs`] module.

[`terraform-aws-modules/ecs`]: https://registry.terraform.io/modules/terraform-aws-modules/ecs/aws/latest

It creates: an ECS **cluster**, a **Fargate service** (1 task) in the default
VPC's public subnets with a **public IP**, a **task definition** for the image,
an IAM **task-execution role**, a **security group**, a **CloudWatch Logs**
group (awslogs driver), and — when a New Relic key is provided — an **SSM
SecureString** injected via ECS `secrets` (so the key never appears in the task
definition).

```bash
cd terraform/ecs
cp terraform.tfvars.example terraform.tfvars   # optionally set newrelic_license_key
terraform init
terraform apply                                # ~2-3 min (waits for steady state)
```

The task's public IP is assigned at runtime, so fetch it and test:

```bash
# Print (and run) the helper command that resolves the running task's IP:
eval "$(terraform output -raw get_public_ip_command)"        # -> <PUBLIC_IP>

curl http://<PUBLIC_IP>:3000/                  # Hello Node!
curl http://<PUBLIC_IP>:3000/health            # {"status":"ok",...}
```

Tear it down when finished:

```bash
terraform destroy
```

Requires AWS credentials (`aws configure` / environment). This was verified
end-to-end: the service came up, served traffic on the task's public IP, shipped
logs to CloudWatch, and reported to New Relic (the agent auto-detects the ECS
environment), then destroyed cleanly.

> **Security & cost:** the task's security group opens the app port to
> `0.0.0.0/0` for demo reachability and the app is unauthenticated — fine for a
> throwaway hello-world, **not** production. For real use, front it with an ALB +
> HTTPS/WAF, tighten the security group, and use private subnets + NAT. Fargate
> and CloudWatch bill by usage, so run `terraform destroy` when done.

## Monitoring & logging (New Relic)
<img width="2546" height="1252" alt="image" src="https://github.com/user-attachments/assets/d9232a69-17a7-4d72-9af4-f039ac7378de" />
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

Provide the key at runtime — via `terraform.tfvars` (`newrelic_license_key`),
`TF_VAR_newrelic_license_key`, `.env`, or `podman run -e NEW_RELIC_LICENSE_KEY=...`.
On ECS the key is stored in **SSM Parameter Store** and injected as a container
secret. Data appears in New Relic under the app name **`node-hello`** (APM &
Services, and Logs). On ECS, container stdout also lands in **CloudWatch Logs**.

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
- **Deployment target** → both options in the brief are implemented: a **local**
  Docker-provider deploy (rootless **Podman**, since the box has no Docker
  daemon and no root) and an **AWS ECS Fargate** deploy. Commands use `podman`,
  but `docker` is interchangeable.
- **ECS shape** → Fargate task with a **public IP** in the default VPC's public
  subnets and no ALB, to keep the demo cheap and simple. A production setup would
  add an ALB, HTTPS, private subnets, and a tighter security group.
- **`docker_host` default** assumes UID `1000`
  (`unix:///run/user/1000/podman/podman.sock`). Adjust to your `id -u`.
- **GHCR visibility** → images are private by default; the package must be made
  public (or `podman login` used) for a credential-free pull.
  `build_local = true` avoids this entirely for a self-contained local run.
- **New Relic** → the provided license key is treated as a secret: stored as a
  GitHub Actions secret, in gitignored local files (`.env`, `terraform.tfvars`),
  and as an SSM SecureString on ECS — never committed. US data-center assumed.
- **Security** → this is a public, unauthenticated demo endpoint by design (no
  sensitive data). A real deployment would add TLS, authentication, and network
  controls (e.g., an ingress/load balancer).
- **Time-box** → scoped to the assignment's 8-hour guidance; kept intentionally
  small and readable rather than over-engineered.
