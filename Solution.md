1.1 







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
## 2.2 – Environment Variable Isolation

The database password was moved to the `.env` file instead of relying on a hardcoded fallback value in `docker-compose.yml`.

### Changes Made

1. Created `.env` from `.env.example`:

   ```bash
   cp .env.example .env
   ```

2. Set a strong database password containing at least 16 characters, including uppercase and lowercase letters, numbers, and special characters.

3. Verified that the application depends on the `.env` file. After temporarily removing `.env`, the Docker Compose stack could not start correctly because the required environment variables were missing.

4. Restored the `.env` file after testing.

5. Added `.env` to `.gitignore` to prevent the file from being committed to Git.

6. Verified the Git status:

   ```bash
   git status
   ```

   The `.env` file is not shown as an untracked or modified file.

### Why `.env` Should Not Be Committed

The `.env` file may contain sensitive information such as database passwords, API keys, tokens, and other credentials. Committing these values to a Git repository can expose them to other users or attackers.

Even if the secret is removed in a later commit, it may still remain in the Git history and can potentially be recovered.

For this reason, `.env` should be excluded from version control using `.gitignore`.

### Secret Detection Tools

Several tools can help prevent accidental exposure of secrets:

* **git-secrets** – prevents commits containing detected secrets.
* **TruffleHog** – scans repositories and Git history for exposed credentials and secrets.
* **GitHub Secret Scanning** – detects supported secrets committed to GitHub repositories and can alert repository owners.

---

## 2.3 – Service Restart Policy and Dependency Order

The startup order was verified using:

docker compose up --build 2>&1 | grep -E "healthy|started|Starting"
```

The expected startup sequence is:

postgres (healthy)
       |
       +----------------------+
       |                      |
       v                      v
jobs-service           applications-service
       |                      |
       +----------+-----------+
                  |
                  v
              frontend
                  |
                  v
                nginx
```

### Dependency Conditions

The Docker Compose configuration uses:

condition: service_healthy
```

`service_healthy` means that Docker Compose waits until the dependency's configured `HEALTHCHECK` reports a healthy status before starting the dependent service.

In contrast:

condition: service_started
```

only means that the dependency's container has been started. It does **not** guarantee that the application inside the container is ready to accept connections.

For PostgreSQL, `service_healthy` is preferable because the backend services should not start before PostgreSQL is actually ready to accept database connections.

### PostgreSQL Failure After Startup

The following command was used to test the behavior:


docker compose stop postgres
```

After PostgreSQL was stopped, the PostgreSQL container became unavailable while the already-running dependent services were not automatically stopped just because their dependency became unavailable.

This demonstrates that `depends_on` controls the startup order and dependency conditions, but it does not continuously monitor dependencies or automatically restart dependent services when a dependency fails.

The backend services may continue running but database-related operations will fail until PostgreSQL becomes available again.

After testing, PostgreSQL was started again with:


docker compose start postgres
```

Its health status was then checked before continuing to use the application.

## 3.1 – Persistence Test After Restart

To verify data persistence, a new job was created through the API:

```bash
curl -s -X POST http://localhost/api/jobs/ \
  -H "Content-Type: application/json" \
  -d '{"title":"Persistence Test Job","description":"Testing Docker volumes","company":"Lab Inc","location":"Docker"}' \
  | python3 -m json.tool
```

The `Persistence Test Job` was successfully created and stored in the PostgreSQL database.

The containers were then stopped and restarted without removing the volumes:

```bash
docker compose stop
docker compose start
```

After the restart, the job list was checked again:

```bash
curl -s http://localhost/api/jobs/ | python3 -m json.tool
```

The `Persistence Test Job` was still present in the list. This confirms that PostgreSQL data is persisted in a Docker volume and is not lost when the containers are stopped and restarted.

### Difference Between Docker Compose Commands

#### `docker compose stop`

Stops the containers but does not remove the containers, networks, or volumes.

It is useful when temporarily stopping the application and starting it again later:

```bash
docker compose start
```

Data stored in volumes is preserved.

#### `docker compose down`

Stops and removes the containers and networks created by Docker Compose.

Volumes are not removed by default, so PostgreSQL data stored in named volumes is preserved.

It is useful when containers need to be removed and recreated while keeping persistent data.

#### `docker compose down -v`

Stops and removes the containers, networks, and volumes.

Data stored in the removed volumes will be deleted.

This command should only be used when a complete cleanup is required, for example, before starting with a completely clean test environment.

### Conclusion

For a normal restart while preserving database data, use:

```bash
docker compose stop
docker compose start
```

or:

```bash
docker compose down
docker compose up -d
```

`docker compose down -v` should not be used when PostgreSQL data needs to be preserved.

## 3.2 – Volume Management

The PostgreSQL Docker volume was checked using:

```bash
docker volume inspect jobboard-postgres-data
docker volume ls
```

### Location of the Data on the Host

The `docker volume inspect` command shows the physical location of the named volume on the Docker host.

For example, the output contains:

```json
"Mountpoint": ".../docker/volumes/jobboard-postgres-data/_data"
```

On Docker Desktop for Windows, the volume is managed inside the Docker Desktop/WSL2 virtual environment rather than being stored directly in the project directory.

The exact `Mountpoint` shown by `docker volume inspect jobboard-postgres-data` is the location used for this Docker volume.

### Named Volume vs Bind Mount

A **named volume** is declared in Docker Compose, for example:

```yaml
volumes:
  postgres-data:
```

and mounted into the container:

```yaml
volumes:
  - postgres-data:/var/lib/postgresql/data
```

Docker manages the storage location and lifecycle of the volume. This is the preferred approach for persistent application data such as PostgreSQL databases.

A **bind mount** directly maps a directory from the host:

```yaml
volumes:
  - ./data:/var/lib/postgresql/data
```

The application data is stored directly in the specified host directory.

### Comparison

| Feature            | Named Volume      | Bind Mount                        |
| ------------------ | ----------------- | --------------------------------- |
| Storage location   | Managed by Docker | Specified by the user             |
| Configuration      | Simple            | Requires a host path              |
| Portability        | Better            | More dependent on host filesystem |
| Database storage   | Recommended       | Usually less convenient           |
| Direct host access | Limited           | Easy                              |
| Development        | Good              | Very useful                       |

### Production Use

For production databases such as PostgreSQL, I would generally prefer **named volumes** because Docker manages the storage location and the application is less dependent on the host's directory structure.

For development, configuration files, source code, or situations where files need to be directly accessible and edited on the host, **bind mounts** are often more convenient.

For a real production environment, an external persistent storage solution or managed database service would also be considered to provide better backup, recovery, availability, and scalability.


## 3.3 – Database Backup and Restore

### Creating a Database Backup

On Windows PowerShell, the PostgreSQL database was backed up using:

```powershell
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
docker exec jobboard-db pg_dump -U postgres -d jobboard --no-owner --no-acl -F plain > "backup_$timestamp.sql"
```

This creates a SQL backup file with a timestamp, for example:

backup_20260812_120530.sql
```

### Checking the Backup

To display the first 30 lines of the backup:

```powershell
Get-Content .\backup_*.sql -TotalCount 30
```

To count `INSERT INTO` statements:

```powershell
(Get-Content .\backup_*.sql | Select-String "INSERT INTO").Count
```

The backup file contains the SQL statements required to recreate the database data.

### Database Restore Procedure

First, stop the application services and start only PostgreSQL:

```powershell
docker compose stop
docker compose up -d postgres
```

Check that PostgreSQL is running:

```powershell
docker compose ps
```

Copy the backup SQL file into the PostgreSQL container:

```powershell
docker cp .\backup_20260812_120530.sql jobboard-db:/tmp/backup.sql
```

> Replace `backup_20260812_120530.sql` with the actual backup filename.

Run the SQL backup inside the PostgreSQL container:

```powershell
docker exec -i jobboard-db psql -U postgres -d jobboard -f /tmp/backup.sql
```

After the restore, the database can be checked with:

```powershell
docker exec -it jobboard-db psql -U postgres -d jobboard
```

Inside `psql`, the tables can be listed with:

```sql
\dt
```

The restored data can then be verified, for example:

```sql
SELECT * FROM jobs;
```

Exit `psql` with:

```sql
\q
```

Finally, start the complete application stack:

```powershell
docker compose up -d
```

### Summary

The backup is stored as a local `.sql` file on the Windows host. The file can be copied into a new PostgreSQL container and restored using `psql`. This provides a simple recovery procedure in case the database data is lost.


## 5.1 – Docker Network Understanding

The Docker network was inspected using Windows PowerShell:

```powershell
docker network inspect jobboard-network
```

### Containers in the Network

The command above displays all containers connected to `jobboard-network`, including their container names and assigned IP addresses.

The following containers were present in the network:

| Container              | IP Address                                 |
| ---------------------- | ------------------------------------------ |
| `jobboard-db`          |  172.20.0.3/16                             |
| `jobs-service`         |  172.20.0.4/16                             |
| `applications-service` |  172.20.0.2/16`                            |
| `frontend`             |  172.20.0.5/16                             |
| `nginx`                | `172.20.0.6/16`                            |

The exact IP addresses can change when containers are recreated, so the values above should be taken from the current output of:

```powershell
docker network inspect jobboard-network
```

### Docker Internal DNS

Docker provides an internal DNS service for containers connected to the same user-defined network.

For example, `jobs-service` can connect to PostgreSQL using the hostname:


postgres
```

Docker's internal DNS resolves `postgres` to the IP address of the PostgreSQL container on `jobboard-network`.

Therefore, the application does not need to know the PostgreSQL container's IP address. It can use:


postgres:5432
```

The IP address can change when the PostgreSQL container is recreated, but the hostname `postgres` continues to resolve to the correct container through Docker's internal DNS.

### Accessing `jobs-service:8000 from a Browser

Trying to open:


http://jobs-service:8000
```

directly in a browser on the Windows host will normally **not work**.

The hostname `jobs-service` is available through Docker's internal DNS only to containers connected to the same Docker network. The Windows host/browser is outside this Docker network and therefore cannot resolve the `jobs-service` hostname.

In addition, the service may not expose port `8000` directly to the host.

External access should go through the published port or the configured reverse proxy, for example:


http://localhost
```

In this architecture, `nginx` acts as the external entry point and forwards requests to the appropriate internal services.

### Conclusion

Docker's internal DNS allows containers on the same user-defined network to communicate using service/container names instead of fixed IP addresses. This makes the application more reliable because container IP addresses can change without requiring changes to the application configuration.


5.2 – Inter-Service Communication Test

The connection from jobs-service to PostgreSQL was tested from inside the container.

On Windows PowerShell, the following command was used:

docker exec -it jobs-service python3 -c "import psycopg2, os; conn=psycopg2.connect(os.environ['DATABASE_URL']); print('Connected to PostgreSQL:', conn.get_dsn_parameters()); conn.close()"

A successful connection produces output:

Connected to PostgreSQL: {'user': 'postgres', 'dbname': 'jobboard', 'host': 'postgres', 'port': '5432'}

This confirms that:

jobs-service can access PostgreSQL.
Docker's internal DNS successfully resolves the hostname postgres.
PostgreSQL is accessible through its internal port 5432.
Containers can communicate with each other through the shared Docker network.

5.3 – Nginx Routing Analysis

The complete request path is:

Browser
   |
   | POST http://localhost/api/applications/
   v
Nginx
   |
   | location /api/applications/
   v
rewrite
   |
   v
applications-service
   |
   | HTTP response
   v
Nginx
   |
   v
Browser

1. Nginx location block

For the request:

POST http://localhost/api/applications/

Nginx selects the location block responsible for /api/applications/.

This routes the request to applications-service.

2. rewrite rule

If the Nginx configuration contains:

rewrite ^/api/applications/?(.*)$ /$1 break;

the original path:

/api/applications/

is rewritten to:

/

would be rewritten to:

/123

The exact result depends on the rewrite rule configured in nginx.conf.

3. Upstream container and port

Nginx forwards the request to:

applications-service

using the Docker internal network.

The service is accessed by its Docker DNS name:

applications-service:<internal-port>

applications-service:3000

The exact port should match the port configured for applications-service in docker-compose.yml.

4. Response back to the browser

The response follows the reverse path:

applications-service
        |
        v
      Nginx
        |
        v
     Browser

applications-service generates the HTTP response and sends it back to Nginx.

Nginx then forwards the response to the browser.

The browser therefore communicates with Nginx through:

http://localhost/api/applications/

and does not need direct access to the internal applications-service container.

Complete Request Flow
Browser
  |
  | POST http://localhost/api/applications/
  v
Nginx :80
  |
  | location /api/applications/
  | rewrite /api/applications/ → /
  v
applications-service :3000
  |
  | HTTP response
  v
Nginx :80
  |
  v
Browser


