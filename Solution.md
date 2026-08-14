1.1 
How many CRITICAL CVEs did you find in total across all images?

1. Critical CVEs
A total of 5 Critical CVEs were found:
frontend — 0
job-board-nginx — 0
applications-service — 1 (CVE-2026-59873, tar)
jobs-service — 4 (perl-base)
2. Image with the Most Vulnerabilities
jobs-service — 192 vulnerabilities:
4 Critical
22 High
68 Medium
68 Low/Unknown
applications-service has 28, while frontend and nginx have 0.

Which image has the most vulnerabilities?

jobs-service uses Debian 13.6, which contains more system packages and therefore more vulnerabilities than the Alpine-based images. A slim, distroless, or Alpine base image could be considered.

Pick one CRITICAL CVE and explain: (a) what it is, (b) which package it affects, (c) what the fix/mitigation is.

Example Critical CVE — CVE-2026-13221
The affected package is perl-base 5.40.1-6. The vulnerability is an integer overflow related to processing very large regular expressions.
With more than 65,535 alternatives, a regular expression may behave incorrectly without producing an error, which could be dangerous if it is used for security checks.
Mitigation: update perl-base and avoid constructing extremely large regular expressions.
Other CVEs in the same package cluster:
CVE-2026-42496 — path traversal;
CVE-2026-57433 — integer overflow.

1.2
#### Before
jobs-service          274 MB
applications-service  231 MB
frontend              98  MB


#### After
jobs-service          263 MB
applications-service  223 MB
frontend              98  MB

### Result

The Dockerfiles were successfully hardened and optimized:

* Containers run as non-root users.
* Base images are pinned to exact SHA256 digests.
* Unnecessary files are excluded from the build context.
* Container health checks are configured.
* The number of Docker image layers was reduced by combining `RUN` commands.
* The final image sizes were optimized compared with the original versions.

2.2
why committing .env to git is a security risk and what tools exist to prevent it (e.g., git-secrets, truffleHog, GitHub secret scanning).

The .env file often contains sensitive information, such as database passwords, API keys, tokens, and other credentials. If it is committed to Git, these secrets can remain in the Git history even after the file is deleted, so anyone with access to the repository may be able to recover them.
To prevent this:
git-secrets — scans commits and prevents known secret patterns from being committed.
TruffleHog — scans Git repositories and history for exposed credentials and secrets.
GitHub Secret Scanning — detects secrets pushed to GitHub and can alert you when credentials are exposed.
---

## 2.3 – Service Restart Policy and Dependency Order

                    ┌──────────────┐
                    │   postgres   │
                    │   Database   │
                    └──────┬───────┘
                           │
                  service_healthy
                    ┌──────┴───────┐
                    ↓              ↓
          ┌────────────────┐ ┌──────────────────────┐
          │  jobs-service  │ │ applications-service │
          └───────┬────────┘ └──────────┬───────────┘
                  │                     │
                  │   service_healthy   │
                  └──────────┬──────────┘
                             ↓
                    ┌────────────────┐
                    │    frontend    │
                    └───────┬────────┘
                            │
                            ↓
                    ┌────────────────┐
                    │      nginx     │
                    │ reverse proxy  │
                    └────────────────┘

Explain what condition: service_healthy does vs condition: service_started

service_healthy — waits until the dependency's healthcheck passes before starting the dependent service.
service_started — only waits until the dependency's container has started. It does not check whether the application inside is ready.

What happens if postgres crashes after the other services are running? Verify with: docker compose stop postgres

If PostgreSQL crashes after the other services are already running, condition: service_healthy does not automatically restart jobs-service or applications-service.
postgres → Stopped
jobs-service → usually remains Running, but database requests will fail.
applications-service → usually remains Running, but database operations will fail.
frontend and nginx → may continue running, but API requests that require PostgreSQL will fail.
condition: service_healthy mainly controls startup order. It does not provide automatic recovery when a dependency crashes later.

## 3.1 – Persistence Test After Restart

Explain the difference between docker compose down, docker compose down -v, and docker compose stop. When would you use each?
| Command                  | Containers                     | Volumes                   | Use when                                                  |
| ------------------------ | ------------------------------ | ------------------------- | --------------------------------------------------------- |
| `docker compose stop`    | Stops them                     | **Keeps** volumes         | Temporarily stop services                                 |
| `docker compose down`    | Removes containers and network | **Keeps** named volumes   | Stop and clean up containers but preserve database data   |
| `docker compose down -v` | Removes containers and network | **Deletes** named volumes | Completely reset the environment, including database data |


## 3.2 – Volume Management

Where on the host machine is the data actually stored?

"/var/lib/docker/volumes/jobboard-postgres-data/_data"
The PostgreSQL data is stored in the Docker named volume jobboard-postgres-data, not in the container's writable layer. On Windows with Docker Desktop, the volume is managed inside Docker's Linux VM/WSL environment.

What is the difference between a named volume (postgres-data:) and a bind mount (./data:/var/lib/postgresql/data)?
Docker manages the jobboard-postgres-data volume.
With a bind mount PostgreSQL stores its data directly in the data folder next to docker-compose.yml.
Named volume → Docker manages the storage.
Bind mount → You specify the exact folder on the host.

When would you prefer each approach in production?

Named volume → prefer for database data (PostgreSQL, MySQL, etc.). Docker manages the storage, making it easier to manage and move between containers.
Bind mount → prefer when the application needs direct access to specific host files, for example configuration files, certificates, or development source code.

## 3.3 – Database Backup and Restore

Get the new PostgreSQL pod name
 $PG_POD = kubectl get pods -n jobboard -l app=postgres -o jsonpath="{.items[0].metadata.name}"

Copy the backup into the PostgreSQL pod
 kubectl cp .\backup.sql "jobboard/$PG_POD:/tmp/backup.sql"
 
Restore the backup
 kubectl exec -n jobboard $PG_POD -- \
  psql -U postgres -d jobboard -f /tmp/backup.sql



## 5.1 – Docker Network Understanding

List all containers on the network with their IP addresses

| Container              | IP Address                                 |
| ---------------------- | ------------------------------------------ |
| `jobboard-db`          |  172.20.0.3/16                             |
| `jobs-service`         |  172.20.0.4/16                             |
| `applications-service` |  172.20.0.2/16`                            |
| `frontend`             |  172.20.0.5/16                             |
| `nginx`                | `172.20.0.6/16`                            |

Explain how jobs-service resolves the hostname postgres (Docker's embedded DNS)

jobs-service resolves postgres using Docker's embedded DNS.Since both containers are attached to the jobboard-network, Docker automatically maps the hostname postgres to the PostgreSQL container's IP address.
This allows the application to connect using postgres:5432 instead of a hard-coded IP address.

What happens if you try to reach jobs-service:8000 from your browser directly? Why?

directly in the browser, the connection will not work.
jobs-service is a hostname resolved by Docker's DNS only inside the Docker network jobboard-network.
Your browser runs on the Windows host, outside that Docker network.
jobs-service does not have a published ports: mapping in your docker-compose.yml.
jobs-service:8000 is reachable from containers inside the Docker network, not directly from the Windows browser.

## 5.3 – Nginx Routing Analysis

Which nginx location block matches?

The request POST /api/applications/ matches the location /api/applications block. 
Nginx rewrites the path from /api/applications/ to /applications/ and proxies the request to applications-service on port 3001.

What the rewrite rule transforms the path to

The rewrite rule transforms /api/applications/... into /applications/...

Which upstream container receives the request and on which port

The request is forwarded to the applications-service container on port 3001.

How the response travels back to the browser

The response travels from applications-service:3001 back to Nginx, which then forwards the HTTP response to the browser.

