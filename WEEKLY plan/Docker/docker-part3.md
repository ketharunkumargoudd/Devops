# Docker Part 3: Docker Compose, then CI with GitHub Actions

**Goal:** run the demo shop with Docker Compose, then build a CI pipeline so that **every push to GitHub automatically runs the Maven build, builds the Docker image, and pushes it to Docker Hub**.

This guide continues from Part 2. It assumes you already have:
- the `demo-shop` project (Maven, multi-stage `Dockerfile`) in `~/demo-shop` on your EC2 instance
- a Docker Hub account
- Git set up on your laptop, with a GitHub account

**Where each part runs:**

| Part | Runs on |
|---|---|
| Docker Compose labs | **EC2 instance** (your laptop can't run Docker) |
| Git, the workflow file, GitHub settings | **Your laptop** (PowerShell and a browser) |
| The pipeline itself (Maven, Docker build, push) | **GitHub's servers** (called runners) |

## Table of Contents

1. [The big picture](#part-1-the-big-picture)
2. [Prepare EC2 and install Compose](#part-2-prepare-ec2-and-install-compose)
3. [Compose concepts](#part-3-compose-concepts)
4. [Compose labs](#part-4-compose-labs)
5. [CI concepts](#part-5-ci-concepts)
6. [Put the project in its own GitHub repo](#part-6-put-the-project-in-its-own-github-repo)
7. [Docker Hub token, GitHub secret and variable](#part-7-docker-hub-token-github-secret-and-variable)
8. [Add a test and write the workflow](#part-8-add-a-test-and-write-the-workflow)
9. [Run it, watch it, break it, fix it](#part-9-run-it-watch-it-break-it-fix-it)
10. [Deploy the CI-built image with Compose](#part-10-deploy-the-ci-built-image-with-compose)
11. [If demo-shop lives inside your Devops repo](#part-11-if-demo-shop-lives-inside-your-devops-repo)
12. [Save these notes to GitHub](#part-12-save-these-notes-to-github)
13. [Cleanup and cost](#part-13-cleanup-and-cost)
14. [Common problems](#common-problems)
15. [Cheat sheet](#cheat-sheet)
16. [Self-check questions](#self-check-questions)
17. [Checklist](#day-checklist)

---

# Part 1: The big picture

```
 Your laptop                    GitHub                         Docker Hub
 -----------                    ------                         ----------
 edit code  --git push-->  repo (main branch)
                                  |
                                  | triggers workflow
                                  v
                         GitHub Actions runner
                         1. checkout the code
                         2. mvn verify  (build + tests)
                         3. docker build
                         4. docker push  ------------------->  <user>/demo-shop:latest
                                                               <user>/demo-shop:<commit>
                                                                        |
                                                                        v
 EC2 server:  docker compose pull && docker compose up -d  <------ pulls the new image
```

## Key terms

| Term | Simple meaning |
|---|---|
| **Docker Compose** | A tool that starts several containers together from one YAML file, with one command |
| **Service** | One container definition inside a Compose file (for example `shop`, `proxy`) |
| **CI (Continuous Integration)** | Every code change is automatically built and tested, so problems show up in minutes |
| **GitHub Actions** | GitHub's built-in CI system. You describe the pipeline in a YAML file inside your repo |
| **Workflow** | One automated pipeline (one YAML file) |
| **Job** | A group of steps that runs on one fresh machine |
| **Runner** | The temporary virtual machine GitHub gives a job |
| **Step** | One command or one reusable action inside a job |
| **Secret** | An encrypted value (like a token) that workflows can use but nobody can read afterwards |

## Why Compose before CI?

Real applications need several containers (an app, a proxy, a database). Starting each with a long `docker run` command doesn't scale. Compose writes the whole setup down in one file you can commit to Git. CI then produces the image that the Compose file runs.

---

# Part 2: Prepare EC2 and install Compose

## 2.1 Connect and check the server

```powershell
ssh -i "C:\Users\ADMIN\.ssh\docker-lab.pem" ec2-user@<PUBLIC-IP>
```

```bash
docker --version
free -h
df -h /
```

- Swap should still show about 2 GB. If `Swap` is `0B` after a reboot, run `sudo swapon /swapfile`.
- Keep at least about 2 GB free on `/`. If not: `docker system prune -a`.

## 2.2 Free up the ports

Compose will use host port 8080, so remove old containers from earlier labs:

```bash
docker ps -a
docker rm -f $(docker ps -aq)
```

Make sure the security group still allows ports **8080-8090** from **My IP** (from Part 1 of the EC2 guide).

## 2.3 Install the Compose plugin

Amazon Linux doesn't include Compose by default. Install it as a Docker CLI plugin:

```bash
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
docker compose version
```

`$(uname -m)` fills in `x86_64` or `aarch64` to match your server's CPU, so the same command works on both. You should see a line like `Docker Compose version v2.x.x`.

For repeatable setups, you can pin a specific release instead of `latest` (see the releases page of the `docker/compose` project on GitHub).

Note the command is `docker compose` (with a space). The old `docker-compose` (with a hyphen) was Compose version 1 and is retired.

## Exercise 2

1. Run `docker compose version`.
2. Run `docker compose --help` and read the list of subcommands.

---

# Part 3: Compose concepts

## 3.1 YAML in one minute

Compose files are written in YAML:

```yaml
key: value            # a setting
list:                 # a list: each item starts with "- "
  - one
  - two
parent:               # nesting uses indentation
  child: value
```

Rules that cause most errors:
- Indent with **spaces only**, never tabs. Use 2 spaces per level.
- Spacing is meaningful: `key: value` needs a space after the colon.
- Quote values like `"8080:80"`. Unquoted, YAML can misread them.

## 3.2 The main parts of `compose.yaml`

| Key | Meaning | Same as |
|---|---|---|
| `services:` | The containers to run | One `docker run` per entry |
| `image:` | Image to use | the image argument |
| `build:` | Build the image from a Dockerfile in this folder | `docker build` |
| `ports:` | `"host:container"` | `-p` |
| `volumes:` | Mounts and named volumes | `-v` |
| `environment:` | Environment variables | `-e` |
| `restart:` | Restart policy | `--restart` |
| `healthcheck:` | How to test that the container is healthy | `HEALTHCHECK` |
| `depends_on:` | Start order, optionally waiting for a healthy dependency | |
| `container_name:` | Fixed container name | `--name` |

## 3.3 What Compose does for you

- Creates a **private network** for the project. Services reach each other **by service name**, like `http://shop:8080` (built-in DNS).
- Names everything with the project name (by default, the folder name, so `demo-shop-shop-1`).
- Starts, stops and removes the whole group together.

The file is named `compose.yaml` (preferred) or `docker-compose.yml`. Both work.

---

# Part 4: Compose labs

Work in your project folder on EC2:

```bash
cd ~/demo-shop
ls
```

You should see `Dockerfile`, `pom.xml` and `src`. If the folder is missing, redo Part 4 of `docker-part2.md`.

## Lab A: one service

```bash
cat > compose.yaml <<'EOF'
services:
  shop:
    build: .
    image: demo-shop:compose
    container_name: shop
    ports:
      - "8080:8080"
    restart: unless-stopped
EOF
```

Check the file, build, and start:

```bash
docker compose config            # validates the file and prints the resolved version
docker compose up -d --build
docker compose ps
docker compose logs -f           # wait for "Started DemoShopApplication", then Ctrl+C
curl http://localhost:8080/health
```

Open `http://<PUBLIC-IP>:8080` in your browser to see the shop.

Stop and remove everything:

```bash
docker compose down
docker compose ps -a
```

`down` removes the containers and the project network, but keeps images and named volumes.

## Lab B: two services (app plus nginx reverse proxy)

A reverse proxy is the usual front door for an app. Visitors talk to nginx, and nginx forwards requests to the shop.

```
Browser --> proxy (nginx, port 80, published as 8080) --> shop (Spring Boot, port 8080, private)
```

**B.1 Create the nginx config**

```bash
cat > nginx.conf <<'EOF'
server {
    listen 80;

    location / {
        proxy_pass http://shop:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF
```

`proxy_pass http://shop:8080` uses the **service name** `shop` as the host name. Compose's built-in DNS resolves it to the shop container.

**B.2 Replace `compose.yaml`**

```bash
cat > compose.yaml <<'EOF'
services:
  shop:
    build: .
    image: demo-shop:compose
    container_name: shop
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/health"]
      interval: 15s
      timeout: 3s
      retries: 5
      start_period: 40s

  proxy:
    image: nginx:alpine
    container_name: proxy
    restart: unless-stopped
    ports:
      - "8080:80"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      shop:
        condition: service_healthy
EOF
```

What's new:

| Part | Meaning |
|---|---|
| `shop` has **no `ports:`** | It isn't published to the outside. Only containers on the same Compose network can reach it |
| `proxy` publishes `"8080:80"` | The only public entry point: host 8080 goes to nginx's port 80 |
| `volumes: ./nginx.conf:...:ro` | A bind mount of your config file, read-only |
| `depends_on ... service_healthy` | `proxy` starts only after `shop` passes its healthcheck, so nginx doesn't forward to a shop that's still starting |

**B.3 Start and test**

```bash
docker compose up -d
docker compose ps
```

Wait until `shop` shows `(healthy)`. The first start takes up to a minute while the JVM warms up.

```bash
curl http://localhost:8080/health
curl http://localhost:8080/api/products
```

These requests go through nginx. Open `http://<PUBLIC-IP>:8080` in your browser as well.

**B.4 See the networking**

```bash
docker compose exec proxy wget -qO- http://shop:8080/health   # proxy reaches shop by name
docker network ls                                              # note demo-shop_default
docker port shop                                               # prints nothing: not published
docker compose logs proxy                                      # nginx access logs
```

**B.5 Restart behaviour**

```bash
docker compose stop shop
curl -i http://localhost:8080/health      # nginx returns 502 Bad Gateway
docker compose start shop
```

A `502 Bad Gateway` means nginx is up but the app behind it isn't. You'll meet this error in real life often, and now you know what it means.

## Lab C: configuration with an `.env` file

Compose reads a file called `.env` in the project folder and substitutes `${VARIABLE}` in `compose.yaml`.

```bash
echo "HOST_PORT=8085" > .env
sed -i 's/"8080:80"/"${HOST_PORT:-8080}:80"/' compose.yaml
docker compose config | grep -A1 ports
docker compose up -d
curl http://localhost:8085/health
```

- `${HOST_PORT:-8080}` means "use `HOST_PORT`, or 8080 if it's not set".
- Open `http://<PUBLIC-IP>:8085` in your browser (port 8085 is inside the 8080-8090 range you allowed).
- Never put secrets in a `.env` file that you commit to Git. Add `.env` to `.gitignore`.

## Lab D: everyday Compose commands

| Command | What it does |
|---|---|
| `docker compose up -d` | Create and start everything in the background |
| `docker compose up -d --build` | Rebuild images first, then start |
| `docker compose ps` | Status of this project's containers |
| `docker compose logs -f <service>` | Follow logs (omit the name for all services) |
| `docker compose exec <service> sh` | Shell inside a running service |
| `docker compose stop` / `start` / `restart` | Control without removing |
| `docker compose pull` | Download newer images for services that use `image:` |
| `docker compose down` | Stop and remove containers and the network |
| `docker compose down -v` | Also delete the project's named volumes (**deletes data**) |
| `docker compose config` | Validate and print the final file |

## Exercise 4

1. Run Lab B and confirm `docker compose ps` shows both services `Up`, and `shop` `healthy`.
2. Open the shop in your browser through the proxy.
3. Stop only `shop`, observe the 502, start it again.
4. Use `.env` to move the proxy to port 8086, and confirm it in the browser.
5. Add a named volume for nginx logs:
   - under `proxy:` add `- nginx-logs:/var/log/nginx` to `volumes:`
   - at the bottom of the file add a top-level block `volumes:` with `nginx-logs:` under it
   - run `docker compose up -d`, then `docker volume ls`
6. Run `docker compose down`, then `docker compose up -d` again. Does the volume survive? (Yes. `down` keeps volumes. `down -v` removes them.)
7. Question: why can't `curl http://<PUBLIC-IP>:8080` reach `shop` directly? (It has no `ports:` entry. Only the proxy is published.)

Finish with `docker compose down`.

---

# Part 5: CI concepts

## 5.1 What a workflow looks like

A workflow is a YAML file in `.github/workflows/` at the **root of the repository**:

```yaml
name: CI                      # shown in the Actions tab

on:                           # WHEN to run
  push:
    branches: [ main ]

jobs:                         # WHAT to run
  build:
    runs-on: ubuntu-latest    # which runner
    steps:
      - uses: actions/checkout@v4    # a reusable action
      - run: echo "hello"            # a shell command
```

| Key | Meaning |
|---|---|
| `on` | The trigger: `push`, `pull_request`, `workflow_dispatch` (a manual button), `schedule` |
| `jobs` | Jobs run in parallel by default. Use `needs:` to make one wait for another |
| `runs-on` | The runner image. `ubuntu-latest` is a fresh Linux VM that already has Docker and Git |
| `steps` | Run in order. A failed step stops the job |
| `uses:` | Run a reusable action, such as `actions/checkout@v4` |
| `run:` | Run a shell command |
| `with:` | Inputs for an action |
| `${{ secrets.NAME }}` | An encrypted secret |
| `${{ vars.NAME }}` | A normal (non-secret) variable |
| `if:` | Run a job or step only when a condition is true |

## 5.2 Our pipeline

```
push to main
   |
   v
Job 1: build-test  (Maven)
   checkout -> set up Java 21 -> mvn verify (compile + tests + package) -> keep the jar
   |
   | needs: only if job 1 succeeds
   v
Job 2: docker
   checkout -> set up Buildx -> log in to Docker Hub -> build image -> push tags
```

Why separate Maven and Docker jobs when the `Dockerfile` already runs Maven?

- The Maven job **runs the tests** (the Dockerfile skips them with `-DskipTests`) and fails fast with clear test reports.
- If tests fail, the Docker job **never runs**, so a broken build is never pushed.
- The Docker build still compiles the jar itself, which keeps the image reproducible from source alone.

On pull requests, only the Maven job runs. Images are pushed **only on pushes to `main`**.

---

# Part 6: Put the project in its own GitHub repo

GitHub only looks for workflows in `.github/workflows/` at the **root** of a repository. A separate repo for `demo-shop` keeps things simple.

## 6.1 Bring the project to your laptop

In PowerShell on your laptop:

```powershell
cd C:\Users\ADMIN
scp -i "C:\Users\ADMIN\.ssh\docker-lab.pem" -r ec2-user@<PUBLIC-IP>:~/demo-shop C:\Users\ADMIN\demo-shop
cd C:\Users\ADMIN\demo-shop
dir
```

Create this folder **outside** `C:\Users\ADMIN\Devops`. Putting one Git repo inside another causes confusing problems.

Delete anything that must not be committed:

```powershell
Remove-Item -Recurse -Force target -ErrorAction SilentlyContinue
Remove-Item .env -ErrorAction SilentlyContinue
```

## 6.2 Add a `.gitignore`

```powershell
notepad .gitignore
```

Contents:

```
target/
.env
*.pem
*.key
*.log
.idea/
.vscode/
```

## 6.3 Create the GitHub repo

1. On github.com click **+ > New repository**.
2. Name: `demo-shop`. Choose Public or Private.
3. Leave **Add a README**, **.gitignore** and **license** **unchecked**.
4. Click **Create repository** and copy the HTTPS URL.

## 6.4 Push

```powershell
cd C:\Users\ADMIN\demo-shop
git init -b main
git add .
git status
```

Check the list. You should see `pom.xml`, `Dockerfile`, `compose.yaml`, `nginx.conf`, `src/...`, and **not** `target/`, `.env`, or any `.pem`.

```powershell
git commit -m "Initial commit: demo-shop with Dockerfile and compose"
git remote add origin https://github.com/<github-username>/demo-shop.git
git push -u origin main
```

If Git says "Please tell me who you are", set your name and email with `git config --global user.name "..."` and `git config --global user.email "..."` first. If it asks you to sign in, use the browser prompt or a Personal Access Token.

Refresh GitHub and confirm the files are there.

## Exercise 6

1. Confirm the repo on GitHub lists `Dockerfile`, `compose.yaml` and `src`.
2. Confirm there's **no** `target` folder and **no** `.env` file on GitHub.

---

# Part 7: Docker Hub token, GitHub secret and variable

The workflow logs in to Docker Hub for you. It needs credentials, and those must never appear in your code.

## 7.1 Create a dedicated Docker Hub token

1. Sign in at hub.docker.com.
2. Open **Account settings > Personal access tokens** (menu names may differ slightly) and click **Generate new token**.
3. Description: `github-actions-demo-shop`. Access permissions: **Read & Write**.
4. Copy the token. It's shown only once.

Use a **separate token for CI** (not the one from Part 2), so you can revoke each one on its own.

## 7.2 Store them in GitHub

Open your repo on GitHub, then **Settings > Secrets and variables > Actions**.

**The token is a secret.** On the **Secrets** tab, click **New repository secret**:

| Name | Value |
|---|---|
| `DOCKERHUB_TOKEN` | the token you copied |

**The username is not secret.** On the **Variables** tab, click **New repository variable**:

| Name | Value |
|---|---|
| `DOCKERHUB_USERNAME` | your Docker Hub username |

Why split them? Secret values are masked as `***` everywhere in logs. Keeping the username as a normal variable makes the logs and the image names readable.

Once saved, a secret can't be read again, only replaced. That's by design.

## Exercise 7

1. Create the token, the secret and the variable.
2. Confirm that you can see the variable's value but not the secret's value.

---

# Part 8: Add a test and write the workflow

## 8.1 Add a unit test

CI is much more useful with a test that can fail. Work on your laptop in `C:\Users\ADMIN\demo-shop`.

**Add the test dependency** to `pom.xml`, inside `<dependencies>` (after the `spring-boot-starter-web` block):

```xml
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-test</artifactId>
      <scope>test</scope>
    </dependency>
```

**Create the test file:**

```powershell
mkdir src\test\java\com\example\shop -Force
notepad src\test\java\com\example\shop\ProductControllerTest.java
```

Click **Yes** to create the file, and paste:

```java
package com.example.shop;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class ProductControllerTest {

    @Test
    void returnsThreeProducts() {
        assertEquals(3, new ProductController().products().size());
    }
}
```

This is a plain unit test. It doesn't start Spring, so it runs in a second.

Notepad can silently save as `.java.txt`. Check with `dir src\test\java\com\example\shop`, or create the file in VS Code (`code .`).

## 8.2 Write the workflow

```powershell
mkdir .github\workflows -Force
code .github\workflows\ci.yml
```

(Or use `notepad`. Just make sure the file name ends in `.yml` and not `.yml.txt`.)

Paste this. Use **spaces, not tabs**:

```yaml
name: CI - Build and Push

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  build-test:
    name: Maven build and test
    runs-on: ubuntu-latest
    steps:
      - name: Check out code
        uses: actions/checkout@v4

      - name: Set up Java 21
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
          cache: maven

      - name: Build and test with Maven
        run: mvn -B verify

      - name: Keep the jar
        uses: actions/upload-artifact@v4
        with:
          name: demo-shop-jar
          path: target/demo-shop.jar

  docker:
    name: Docker build and push
    needs: build-test
    if: github.event_name == 'push'
    runs-on: ubuntu-latest
    steps:
      - name: Check out code
        uses: actions/checkout@v4

      - name: Compute short commit id
        run: echo "SHORT_SHA=${GITHUB_SHA::7}" >> "$GITHUB_ENV"

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ vars.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build and push image
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: |
            ${{ vars.DOCKERHUB_USERNAME }}/demo-shop:latest
            ${{ vars.DOCKERHUB_USERNAME }}/demo-shop:${{ env.SHORT_SHA }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

The versions after `@` (`v4`, `v3`, `v6`) are the major versions that work with this workflow. Newer majors of these actions may exist by the time you read this. If a step warns about a deprecated version, open that action's page on GitHub Marketplace to see the current one.

## 8.3 What each part does

| Part | Meaning |
|---|---|
| `on: push: branches: [ main ]` | Run on every push to `main` |
| `pull_request` | Also run (Maven job only) when someone opens a pull request into `main` |
| `workflow_dispatch` | Adds a **Run workflow** button in the Actions tab |
| `permissions: contents: read` | The workflow's built-in token may only read the repo (least privilege) |
| `actions/checkout@v4` | Downloads your repo onto the runner. Without it the runner has no code |
| `actions/setup-java@v4` with `cache: maven` | Installs Java 21 and caches `~/.m2`, so later runs skip downloads |
| `mvn -B verify` | Compile, run the tests, package the jar. `-B` is batch mode (clean logs) |
| `upload-artifact` | Saves the jar on the run page, so you can download it later |
| `needs: build-test` | The Docker job starts **only if** the Maven job succeeded |
| `if: github.event_name == 'push'` | Skips the Docker job on pull requests, so untested code never gets pushed as an image |
| `echo "SHORT_SHA=..." >> "$GITHUB_ENV"` | Saves the first 7 characters of the commit ID for later steps |
| `docker/login-action@v3` | Logs the runner in to Docker Hub with your variable and secret |
| `docker/build-push-action@v6` | Builds with your `Dockerfile` and pushes. `tags:` lists every tag to publish |
| `cache-from / cache-to: type=gha` | Reuses Docker layers between runs using GitHub's cache |

You publish **two tags** per build:
- `latest` is a moving convenience tag.
- `<short-commit-id>` is permanent and traces exactly which commit produced the image. You can roll back to it.

## 8.4 Optional: ignore documentation-only pushes

Add this under `push:` if you don't want a build when only Markdown files change:

```yaml
  push:
    branches: [ main ]
    paths-ignore:
      - '**.md'
```

## Exercise 8

1. Add the test dependency and the test file.
2. Create `ci.yml` and check the file name and spaces in your editor.
3. Question: why does the workflow have `needs: build-test` on the Docker job? (So a failing test stops the pipeline before any image is pushed.)

---

# Part 9: Run it, watch it, break it, fix it

## 9.1 Trigger the first run

```powershell
cd C:\Users\ADMIN\demo-shop
git add .
git status
git commit -m "Add unit test and CI workflow"
git push origin main
```

## 9.2 Watch it

1. On GitHub open your repo and click the **Actions** tab.
2. Click the newest run, **CI - Build and Push**.
3. You'll see two jobs: **Maven build and test** and **Docker build and push**. The second waits for the first.
4. Click a job, then click any step to expand its log.

A yellow dot means running, a green tick means success, and a red cross means failure. The first run takes a few minutes, since nothing is cached. Later runs are much faster.

Under **Artifacts** at the bottom of the run summary, you can download `demo-shop-jar`.

## 9.3 Verify the image on Docker Hub

Open `https://hub.docker.com/r/<dockerhub-username>/demo-shop`. Under **Tags** you should see `latest` and a 7-character tag matching your commit ID. Compare it with the one shown by:

```powershell
git log --oneline -1
```

## 9.4 Add a status badge

Create a `README.md` in the repo root:

```markdown
# demo-shop

![CI](https://github.com/<github-username>/demo-shop/actions/workflows/ci.yml/badge.svg)

Spring Boot demo shop, built and pushed to Docker Hub by GitHub Actions.
```

Push it. The badge shows green or red depending on the latest run. If you added `paths-ignore` for `**.md`, this push won't trigger a build, which is expected.

## 9.5 Break it on purpose

A pipeline you've never seen fail isn't one you understand yet.

1. Edit the test so it expects the wrong number: change `assertEquals(3, ...)` to `assertEquals(4, ...)`.
2. Commit and push:
   ```powershell
   git add .
   git commit -m "Break the test on purpose"
   git push origin main
   ```
3. In the **Actions** tab, watch the run:
   - **Maven build and test** fails with a red cross, and the log shows the failed assertion (`expected: <4> but was: <3>`).
   - **Docker build and push** is **skipped**, because it `needs` the first job.
4. Check Docker Hub: **no new tag appeared**. A broken build was never published.

## 9.6 Fix it

1. Change `4` back to `3`.
2. Commit and push again:
   ```powershell
   git add .
   git commit -m "Fix the test"
   git push origin main
   ```
3. Both jobs go green, and a new tag appears on Docker Hub.

## 9.7 Try the pull request path

1. Create a branch and push a small change:
   ```powershell
   git switch -c feature/title-change
   ```
   Edit the heading in `src/main/resources/static/index.html`, then:
   ```powershell
   git add .
   git commit -m "Change shop title"
   git push -u origin feature/title-change
   ```
2. On GitHub, open a pull request into `main`.
3. In the Actions tab, only **Maven build and test** runs. The Docker job is skipped because it's a pull request, not a push.
4. Merge the pull request. Now the push to `main` triggers the **full** pipeline, and a new image is published.

## Exercise 9

1. Complete 9.1 to 9.3 and confirm the green pipeline and the tags on Docker Hub.
2. Break the test, observe the skipped Docker job, then fix it.
3. Run the pipeline from the **Run workflow** button (Actions tab, select the workflow, **Run workflow**).
4. Question: where does the image's short tag come from? (The first 7 characters of the commit ID, from `GITHUB_SHA`.)

---

# Part 10: Deploy the CI-built image with Compose

Now close the loop. A server that only **pulls** the image, with no source code and no build.

## 10.1 Create a deployment folder on EC2

```bash
mkdir -p ~/deploy && cd ~/deploy
```

**`.env`**, with your Docker Hub username:

```bash
echo "DOCKERHUB_USER=<dockerhub-username>" > .env
```

**`nginx.conf`** (the same as before):

```bash
cat > nginx.conf <<'EOF'
server {
    listen 80;

    location / {
        proxy_pass http://shop:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF
```

**`compose.yaml`**, with `image:` and no `build:`:

```bash
cat > compose.yaml <<'EOF'
services:
  shop:
    image: ${DOCKERHUB_USER:?set DOCKERHUB_USER in .env}/demo-shop:${TAG:-latest}
    container_name: shop
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/health"]
      interval: 15s
      timeout: 3s
      retries: 5
      start_period: 40s

  proxy:
    image: nginx:alpine
    container_name: proxy
    restart: unless-stopped
    ports:
      - "8080:80"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      shop:
        condition: service_healthy
EOF
```

- `${DOCKERHUB_USER:?message}` stops with your message if the variable isn't set, which prevents a silent mistake.
- `${TAG:-latest}` uses the `latest` tag unless you set `TAG`.

## 10.2 Pull and run

```bash
docker compose pull
docker compose up -d
docker compose ps
curl http://localhost:8080/api/products
```

The image comes from **Docker Hub**, built by **GitHub Actions**. Open `http://<PUBLIC-IP>:8080` in your browser.

If the pull is denied, your Docker Hub repository may be private. Run `docker login -u <dockerhub-username>` on the server first, or make the repo public.

## 10.3 The full update cycle

On your **laptop**, change something visible:

```powershell
cd C:\Users\ADMIN\demo-shop
```

Edit the heading in `src/main/resources/static/index.html`, then:

```powershell
git add .
git commit -m "Update shop heading"
git push origin main
```

Wait for the green pipeline in the Actions tab. Then on **EC2**:

```bash
cd ~/deploy
docker compose pull
docker compose up -d
```

Compose notices the new image and recreates only the `shop` container. Hard-refresh the browser (`Ctrl + F5`) to see the change.

```
edit -> git push -> CI builds and pushes -> docker compose pull -> docker compose up -d -> live
```

## 10.4 Roll back to an older version

Every build has its own commit tag on Docker Hub. To go back:

```bash
docker image ls | grep demo-shop         # or look at the Tags tab on Docker Hub
TAG=<older-short-commit-id> docker compose up -d
```

To make it stick across commands, put `TAG=<older-short-commit-id>` into `.env`. Remove that line to follow `latest` again. This is why you publish a commit tag as well as `latest`.

## Exercise 10

1. Deploy from Docker Hub with `~/deploy`.
2. Make a visible change on your laptop, push, wait for green, and redeploy. Confirm it in the browser.
3. Roll back to the previous commit tag, then forward again to `latest`.
4. Question: why does the deploy folder have no `Dockerfile` or source code? (The image already contains the built app. The server only runs it.)

---

# Part 11: If demo-shop lives inside your Devops repo

If your `demo-shop` folder sits inside the `Devops` repo (for example `Devops/demo-shop`), the workflow must still live at `Devops/.github/workflows/`, and it needs to know where the project is:

```yaml
on:
  push:
    branches: [ main ]
    paths:
      - 'demo-shop/**'
      - '.github/workflows/demo-shop-ci.yml'

jobs:
  build-test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: demo-shop
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
          cache: maven
          cache-dependency-path: demo-shop/pom.xml
      - run: mvn -B verify

  docker:
    needs: build-test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          username: ${{ vars.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}
      - uses: docker/build-push-action@v6
        with:
          context: ./demo-shop
          push: true
          tags: ${{ vars.DOCKERHUB_USERNAME }}/demo-shop:latest
```

The differences: `paths:` limits runs to changes in that folder, `working-directory` points the Maven commands at the subfolder, and `context: ./demo-shop` tells Docker where the `Dockerfile` is. Name the file something like `demo-shop-ci.yml`, because one repo can hold several workflows.

---

# Part 12: Save these notes to GitHub

Put this file in your `Devops` repo's Docker folder, from the repo root:

```powershell
cd C:\Users\ADMIN\Devops
git pull --rebase origin main
git add -v "WEEKLY plan/Docker/docker-part3.md"
git status
git commit -m "Add Docker part 3 notes"
git push origin main
```

Quote the path (it has a space), and run `git pull --rebase` first so the push isn't rejected if GitHub has newer commits.

Keep the project itself in the separate `demo-shop` repo.

---

# Part 13: Cleanup and cost

On EC2:

```bash
cd ~/demo-shop && docker compose down
cd ~/deploy && docker compose down
docker system prune -a
```

- **Stop the EC2 instance** when you finish studying, and terminate it (and any extra EBS volumes) when the module is done.
- GitHub Actions has free usage allowances that depend on your plan and on whether the repo is public or private. Check **Settings > Billing** (or the plans page) for current limits. Each run of this pipeline takes a few minutes.
- Revoke the Docker Hub tokens you no longer need: **Docker Hub > Account settings > Personal access tokens**.
- To save GitHub Actions cache and artifact space, you can delete old runs from the Actions tab.

---

# Common problems

## Docker Compose

| Problem | Cause and fix |
|---|---|
| `docker: 'compose' is not a docker command` | The plugin isn't installed or isn't executable. Redo Part 2.3 and run `docker compose version` |
| `no configuration file provided: not found` | You're not in the folder that holds `compose.yaml`. `cd` into it |
| `yaml: line N: mapping values are not allowed here` or similar | YAML indentation or spacing error near line N. Use spaces only, with a space after each colon. Check with `docker compose config` |
| `port is already allocated` | Another container or program uses that host port. `docker ps`, then `docker rm -f <name>`, or change the port in `.env` |
| `proxy` never starts, `shop` is `unhealthy` | Check `docker compose logs shop`. Usually the app crashed, or the healthcheck URL is wrong |
| Browser or curl shows `502 Bad Gateway` | nginx is up but `shop` isn't ready or the service name in `nginx.conf` is wrong. Check `docker compose ps` and that `proxy_pass` uses `http://shop:8080` |
| `The "HOST_PORT" variable is not set` warning | The `.env` file is missing or in another folder. Compose reads `.env` from the project folder |
| `set DOCKERHUB_USER in .env` error | The required variable is missing. Add `DOCKERHUB_USER=<username>` to `.env` |
| Changes to `compose.yaml` aren't applied | Run `docker compose up -d` again. It recreates only what changed. Use `--build` after code changes |
| `pull access denied` in `compose pull` | Wrong username in `.env`, a typo in the image name, or the repo is private. Check the name and `docker login` |
| Out of disk space | `docker system df`, then `docker system prune -a` |

## GitHub Actions

| Problem | Cause and fix |
|---|---|
| The Actions tab shows no workflow | The file isn't at `.github/workflows/<name>.yml` in the **repo root**, or its extension is wrong (such as `.yml.txt`) |
| `Invalid workflow file` with a line number | YAML syntax error, usually indentation or a tab character. Fix the line it names |
| The run doesn't start on push | The push was to a different branch, a `paths`/`paths-ignore` filter excluded it, or Actions are disabled under **Settings > Actions** |
| Docker job shows **Skipped** | The Maven job failed (`needs`), or the run came from a pull request (`if` condition). Both are expected |
| `Error: Username and password required` | The `DOCKERHUB_USERNAME` variable or `DOCKERHUB_TOKEN` secret is missing, or has a different name than the workflow uses. Names are case-sensitive |
| `unauthorized: incorrect username or password` | Wrong username, or the token was revoked or mistyped. Create a new token and replace the secret |
| `denied: requested access to the resource is denied` | The token is read-only, or the image name's namespace isn't your username. Check the token has **Read & Write**, and the variable's value |
| `invalid reference format` in the build step | The username variable is empty, so the tag became `/demo-shop:latest`. Add the variable |
| Maven step fails with test errors | Read the log for `Tests run: ... Failures:` and fix the code or the test |
| `Unsupported class file major version` or Java errors | The Java version in the workflow doesn't match `<java.version>` in `pom.xml`. Make both 21 |
| `Resource not accessible by integration` | The job needs a permission that `permissions:` didn't grant. Add only what's needed |
| Secrets are empty on pull requests from forks | By design. GitHub doesn't give secrets to forks, so the Docker job skips on pull requests |
| Workflow runs twice for one change | Both `push` and `pull_request` triggered it (a push to a branch with an open PR). Normal |
| Build is slow | The first run has no cache. Later runs reuse the Maven and layer caches |

---

# Cheat sheet

| Command or setting | Purpose |
|---|---|
| `docker compose up -d --build` | Build and start all services |
| `docker compose ps` | Status and health |
| `docker compose logs -f <svc>` | Follow logs |
| `docker compose exec <svc> sh` | Shell into a service |
| `docker compose pull` | Download newer images |
| `docker compose down` | Stop and remove containers and the network |
| `docker compose config` | Validate and show the final file |
| `TAG=abc1234 docker compose up -d` | Run a specific image tag (rollback) |
| `.github/workflows/ci.yml` | Where the pipeline definition lives |
| `on: push / pull_request / workflow_dispatch` | Triggers |
| `needs: <job>` | Run after another job succeeds |
| `if: github.event_name == 'push'` | Conditional job or step |
| `${{ secrets.NAME }}` / `${{ vars.NAME }}` | Secret / normal variable |
| `actions/checkout`, `setup-java`, `docker/login-action`, `docker/build-push-action` | The four main actions in this pipeline |

---

# Self-check questions

1. What problem does Docker Compose solve? *(It describes and runs several related containers together from one file, with one command.)*
2. How does the `proxy` service find the `shop` service? *(By service name, through Compose's built-in DNS on the project network.)*
3. What is the difference between `docker compose down` and `docker compose down -v`? *(`down` removes containers and the network. `-v` also deletes named volumes and their data.)*
4. Why doesn't `shop` publish a port in Lab B? *(It's only reachable through the proxy, which keeps the app private.)*
5. What does `depends_on` with `condition: service_healthy` do? *(Delays starting a service until its dependency passes its healthcheck.)*
6. What does CI mean, and why use it? *(Continuous Integration: every push is built and tested automatically, so problems are found quickly.)*
7. Where must a GitHub Actions workflow file be stored? *(`.github/workflows/` at the root of the repository.)*
8. What does `needs: build-test` do? *(Makes the Docker job wait for the Maven job, and run only if it succeeds.)*
9. Why store the Docker Hub token as a secret and not in the workflow file? *(Workflow files are committed to Git and visible. Secrets are encrypted and masked in logs.)*
10. Why are images pushed on `push` but not on pull requests? *(Pull requests contain unreviewed code, and pull requests from forks have no access to secrets.)*
11. Why publish both `latest` and a commit-ID tag? *(`latest` is convenient. The commit tag is permanent, traceable, and lets you roll back.)*
12. After CI pushes a new image, how does the EC2 server pick it up? *(`docker compose pull`, then `docker compose up -d`.)*

---

# Day checklist

**Docker Compose**
- [ ] Compose plugin installed, `docker compose version` works
- [ ] Lab A: one service built and running from `compose.yaml`
- [ ] Lab B: shop plus nginx proxy running, shop healthy, proxy reaching it by name
- [ ] Saw a `502 Bad Gateway` by stopping `shop`
- [ ] Used `.env` to change the host port
- [ ] Used `docker compose down`, and understood what `-v` does

**CI with GitHub Actions**
- [ ] `demo-shop` is in its own GitHub repo, with no `target/`, `.env` or `.pem` files
- [ ] Docker Hub token created, `DOCKERHUB_TOKEN` secret and `DOCKERHUB_USERNAME` variable added
- [ ] Unit test added, `ci.yml` created at `.github/workflows/ci.yml`
- [ ] First run is green, and both tags appear on Docker Hub
- [ ] Broke the test on purpose and saw the Docker job skip, then fixed it
- [ ] Tried a pull request and saw that it doesn't push an image
- [ ] Deployed from Docker Hub with the `~/deploy` Compose file
- [ ] Made a change, pushed, waited for green, and redeployed with `docker compose pull`
- [ ] Rolled back using a commit tag
- [ ] Notes pushed to my `Devops` repo, and the instance stopped when finished

**Next steps:** deploy the same image to your Kubernetes cluster by referencing `<dockerhub-username>/demo-shop:<commit-id>` in a Deployment. Later, add an automated deploy step, an image vulnerability scan (such as Trivy), and release tags.
