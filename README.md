# Docker Production

## GHCR Image URL
ghcr.io/ibrahim-2010/docker-production:latest

## Run the Full Stack
```bash
docker compose up --build -d
```

This starts 5 services: Flask API, Redis, PostgreSQL, Prometheus, and Grafana.

## Setup
1. Clone this repository
2. Copy the environment file: `cp .env.example .env`
3. Fill in your own credentials in `.env`
4. Run: `docker compose up --build -d`

## Access Points
- Flask API: http://localhost:5000
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3000 (default login: admin/admin)

## Image Size Comparison

| Image                     | Approach                                                          | Virtual Size     | Compressed Size |
|---------------------------|-------------------------------------------------------------------|------------------|-----------------|
| flask-app:v1.0            | Single stage, python:3.11-slim                                    | 210 MB           | 51.1 MB         |
| flask-app:v2.0            | Multi-stage venv, python:3.11-slim both stages                    | 234 MB           | 55.5 MB         |
| flask-app:v2.0-multistage | Multi-stage --prefix, python:alpine final (Assignment 1 bonus)    | 80 MB            | 19.3 MB         |

### Why v2.0 is Larger Than v1.0
The multi-stage venv build produced a larger image — a counterintuitive result. In Assignment 1, pip installed Flask and Redis directly into the system Python at /usr/local/lib/python3.11/site-packages. In Assignment 2, the builder creates a full virtual environment at /opt/venv which includes its own copy of the Python binary, pip, setuptools, and activation scripts. Since both stages use python:3.11-slim, the runtime stage already has a complete Python installation. The copied venv adds a second, redundant copy of the Python binary and package management tools on top, causing the size to increase.

The value of multi-stage builds is architectural, not just numerical. Even when the size reduction is minimal, the pattern enforces a clean separation between build-time and run-time concerns. The final image contains no pip, no build metadata, and no installation tooling — only the application and its dependencies. This reduces the attack surface and follows the principle of
least privilege. In production environments with heavier dependencies (compilers, development headers), the same pattern yields dramatic size reductions.

## Trivy Security Scan Summary

Scanned flask-app:v2.0 (Debian 13.3) and rebuilt as flask-app:v2.1 using python:3.11-slim-bookworm (Debian 12.13) in an attempt to reduce vulnerabilities. The result was counterintuitive: the Bookworm image was less secure, not more. Total OS vulnerabilities increased from 84 to 116, and two new CRITICAL CVEs appeared in zlib1g (CVE-2023-45853) that did not exist in the original scan. The HIGH-severity glibc vulnerability (CVE-2026-0861) that was fixable in Debian 13.3 had no available patch in Bookworm. Python package findings were identical across both scans —
10 vulnerabilities in pip, setuptools/wheel, jaraco.context, and Flask, each appearing twice due to duplicate copies in the venv and system Python directories.

The correct decision was to revert to the original python:3.11-slim (Debian 13.3) base image. The key lesson: newer stable releases do not always mean fewer vulnerabilities. Debian 13 ships more recent upstream packages with more recent patches, while Bookworm (Debian 12) carries older versions that have accumulated more known CVEs. Always scan before and after a base image change and compare empirically.

### Before vs After Comparison

| Metric | v2.0 (Debian 13.3) | v2.1 (Bookworm/Debian 12.13) | Change |
|--------|--------------------|-----------------------------|--------|
| Total OS vulnerabilities | 84 | 116 | +32 (worse) |
| CRITICAL | 0 | 2 | +2 (worse) |
| HIGH | 2 | 2 | No change |
| MEDIUM | 8 | 19 | +11 (worse) |
| LOW | 73 | 92 | +19 (worse) |
| UNKNOWN | 1 | 1 | No change |
| Python vulnerabilities | 10 | 10 | No change |

### CRITICAL Findings (v2.1 only — introduced by Bookworm)

| Package | CVE | Description | Status |
|---------|-----|-------------|--------|
| zlib1g | CVE-2023-45853 | Integer overflow and heap-based buffer overflow in zipOpenNewFileInZip4_64 | will_not_fix |
| zlib1g | CVE-2026-27171 | DoS via infinite loop in CRC32 combine functions (MEDIUM) | affected |

### HIGH Findings (present in both scans)

| Package | CVE | Description | v2.0 Status | v2.1 Status |
|---------|-----|-------------|-------------|-------------|
| glibc (libc-bin, libc6) | CVE-2026-0861 | Integer overflow in memalign leads to heap corruption | Fix available (2.41-12+deb13u2) | No fix in Bookworm |

### Python Package Findings (identical in both scans)

| Library | CVE | Severity | Installed | Fixed In | Description |
|---------|-----|----------|-----------|----------|-------------|
| jaraco.context | CVE-2026-23949 | HIGH | 5.3.0 | 6.1.0 | Path traversal via malicious tar archives |
| wheel | CVE-2026-24049 | HIGH | 0.45.1 | 0.46.2 | Privilege escalation via malicious wheel file |
| pip | CVE-2025-8869 | MEDIUM | 24.0 | 25.3 | Missing checks on symbolic link extraction |
| pip | CVE-2026-1703 | LOW | 24.0 | 26.0 | Info disclosure via path traversal in wheel archives |
| Flask | CVE-2026-27205 | LOW | 3.0.0 | 3.1.3 | Info disclosure via improper session caching |

### Remediation Applied
Reverted to original python:3.11-slim (Debian 13.3) base image after confirming Bookworm introduced more vulnerabilities. Updated Flask version in requirements.txt to address CVE-2026-27205. The glibc HIGH vulnerability (CVE-2026-0861) has a fix available in Debian 13.3 and will be patched when the base image layers are refreshed.

## Screenshots
All screenshots are in the `screenshots/` directory:
- `part1-multistage.png` — Image size comparison showing v1.0 and v2.0
- `part2-actions.png` — GitHub Actions pipeline with all steps green
- `part2-ghcr.png` — GHCR Packages page showing sha and latest tags
- `part3-scan-before.png` — Trivy scan of v2.0 (Debian 13.3)
- `part3-scan-after.png` — Trivy scan of v2.1 (Bookworm) showing increased CVEs
- `part4-compose.png` — All services running with .env configuration
- `part4-gitignore.png` — .gitignore confirming .env exclusion
- `part5-stack.png` — All 5 services healthy in docker compose ps
- `part5-grafana.png` — Grafana dashboard showing Flask request metrics

## Challenges and Solutions

### Multi-Stage Build Produced a Larger Image
The multi-stage venv build (234MB / 55.5MB) was larger than the single-stage build (210MB / 51.1MB). The virtual environment at /opt/venv includes its own Python binary, pip, setuptools, and
activation scripts. Since the runtime stage already has a complete Python installation from the base image, the copied venv adds redundant copies. Multi-stage builds show real savings when the builder accumulates heavy dependencies like C compilers that get discarded. Flask and Redis are pure Python — nothing substantial to leave behind. The pattern is structurally correct and production-standard, but the size benefit depends on dependency complexity.

### Bookworm Base Image Increased Vulnerabilities
Switching to python:3.11-slim-bookworm was expected to improve security but made it worse. Total OS vulnerabilities increased from 84 to 116, two new CRITICAL CVEs appeared in zlib1g, and the glibc HIGH vulnerability that was fixable in Debian 13.3 had no patch in Bookworm. Debian 12 (Bookworm) is an older stable release with older package versions that have accumulated more known CVEs. Debian 13 (Trixie) ships newer upstream packages with more recent patches. The fix was to revert to the original base image and compare scan results empirically
rather than assuming a different tag means better security.

### Duplicate Python Vulnerabilities in Trivy Report
Trivy reported the same pip, setuptools, and wheel CVEs twice — once in /opt/venv/ and once in /usr/local/. This happens because the venv approach copies packages from the builder, but the runtime base image (python:3.11-slim) also ships its own system-level pip and setuptools. Both locations contain the same vulnerable versions, effectively doubling the Python vulnerability count. In production, the system copies could be removed since the application only uses the venv.

### Grafana Could Not Connect to Prometheus
After setting the Prometheus data source URL to http://prometheus:9090, Grafana returned: "lookup prometheus on 127.0.0.1:53: no such host." The cause was the Grafana service missing the `networks: - app-network` directive in docker-compose.yml. Without it, Grafana ran on the default network and could not resolve the Prometheus container's hostname via Docker's internal DNS. Adding the network configuration and restarting the stack resolved the issue.

### Health Check Without curl
The assignment template uses curl for the web service health check, but python:3.11-slim does not include curl. Installing it would add ~10MB and an additional package requiring security patching. Used Python's built-in urllib module instead, which is guaranteed to be present in any Python image and achieves the same result with zero additional dependencies.


### Secrets Hardcoded in Assignment 1
Assignment 1 committed POSTGRES_PASSWORD: secret directly in docker-compose.yml to a public GitHub repository. Moved all credentials to a .env file excluded from Git via .gitignore. Created .env.example with placeholder values so new developers know which variables are required without seeing real credentials. If credentials are accidentally committed, the immediate response is: rotate every credential first, then purge Git history with git filter-repo, then force push.

### Prometheus Service Name Resolution
The prometheus.yml scrape target must use the Docker service name (web:5000), not localhost:5000. Prometheus runs in its own container where localhost refers to itself, not the Flask container. Docker's internal DNS resolves service names across the app-network bridge, allowing containers to reach each other by their Compose service names.

## Reflection
The hardest part of this assignment was discovering that intuitive assumptions about security and optimization were wrong. The multi-stage build did not shrink the image. The Bookworm base image did not reduce vulnerabilities. These counterintuitive results forced a deeper understanding of how Docker images, Debian releases, and Python virtual environments actually work — not just how they are supposed to work in theory.

The most valuable lesson was that production readiness requires empirical verification at every step: scan before and after base image changes, compare image sizes with actual measurements, and test network connectivity between containers rather than assuming service names resolve. The combination of multi-stage builds, CI/CD automation, security scanning, secrets management, and observability creates a production-grade system — but only when each practice is validated with real data, not assumptions.


### Bonus A: Docker Swarm

Deployed the stack to a single-node Swarm cluster and scaled the Flask app to 3 replicas to demonstrate load balancing and self-healing.

#### Challenge: Swarm Incompatible with Compose File
Running `docker stack deploy -c docker-compose.yml myapp` failed with `services.web.depends_on must be a list`. Docker Swarm does not support the extended depends_on syntax with conditions (service_started, service_healthy), does not support the `build:` directive (requires pre-built images), and does not support `restart:` policies (uses `deploy.restart_policy` instead). The `healthcheck` directive at the ervice level is also handled differently in Swarm.

#### Solution: Separate Swarm-Specific Compose File
Created `docker-compose.swarm.yml` that strips out all Swarm-incompatible features: replaced `build: .` with `image: flask-app:v2.0`, removed `depends_on` conditions, removed `healthcheck` and `restart` directives, changed network driver from `bridge` to `overlay` (required for Swarm multi-node communication), and added `deploy.replicas` for scaling.

#### Results
- Scaled web service to 3 replicas with `docker service scale myapp_web=3`
- Each curl request returned a different hostname, confirming Swarm's built-in load balancer distributes requests across replicas
- Killed one replica with `docker rm -f` — Swarm detected the missing  replica and spawned a replacement within seconds to maintain the desired count of 3

#### Key Swarm vs Compose Differences Discovered

| Feature | Docker Compose | Docker Swarm |
|---------|---------------|--------------|
| Build from Dockerfile | `build: .` supported | Not supported — requires pre-built images |
| Startup ordering | `depends_on` with conditions | Simple list only, no conditions |
| Network driver | `bridge` | `overlay` (enables cross-node communication) |
| Scaling | Manual with `docker compose up --scale` | Built-in with `docker service scale` |
| Self-healing | `restart: unless-stopped` | Automatic — maintains desired replica count |
| Health checks | Defined per service | Managed by Swarm orchestrator |
| Load balancing | Not built-in | Automatic across replicas |


### Bonus B: Makefile

Created a Makefile at the project root that automates common Docker commands into simple shortcuts. Instead of typing complex multi-flag commands, any team member can run `make run` to start the full stack.

#### Challenge: make Not Installed on Windows
Running `make run` returned `bash: make: command not found`. The `make` utility is a Unix tool that does not come pre-installed with Git Bash on Windows. Unlike macOS or Linux where make is typically available out of the box, Windows requires a separate installation.

#### Solution
Installed make via Chocolatey: `choco install make -y`. Alternatively, make can be installed via `winget install GnuWin32.Make`. After installation, closing and reopening the terminal was required for the PATH to update.

#### Important: Makefiles Require Tabs
Makefiles are one of the few file types where indentation matters and must use actual tab characters, not spaces. If VS Code converts tabs to spaces (the default for many configurations), make will fail with `*** missing separator. Stop.` The fix is to check the bottom status bar in VS Code and switch from "Spaces" to "Tabs" for the Makefile.

#### Available Commands

| Command | What It Does |
|---------|-------------|
| `make build` | Builds the Docker image as flask-app:v2.0 |
| `make run` | Starts the full 5-service stack with docker compose up --build -d |
| `make stop` | Stops all services with docker compose down |
| `make clean` | Nuclear option — removes all containers, volumes, and images |
| `make scan` | Runs Trivy security scan for HIGH and CRITICAL vulnerabilities |
| `make push` | Tags and pushes the image to GHCR |
| `make logs` | Follows all container logs in real time |


### Bonus C: Prometheus Alerting
Added an alert rule that fires when the Flask app has been unreachable for 30+ seconds. The up metric is automatically tracked by Prometheus for every scrape target. Verified by stopping the web container and confirming the alert fired in the Prometheus Alerts UI.