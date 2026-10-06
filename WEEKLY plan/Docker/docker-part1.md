# Docker Part 1: Images, Containers, Ports, Volumes

**Goal:** run nginx in a container and map a port, while understanding Docker from scratch.

Commands are shown for **PowerShell on Windows** (Docker Desktop) and for **Amazon Linux on EC2** (your `ec2-user` server). Where they differ, both are given.

## Table of Contents

1. [What is Docker and why use it](#part-1-what-is-docker-and-why-use-it)
2. [Core concepts in simple terms](#part-2-core-concepts-in-simple-terms)
3. [Install Docker](#part-3-install-docker)
4. [Your first container: hello-world](#part-4-your-first-container-hello-world)
5. [Images](#part-5-images)
6. [Containers and their lifecycle](#part-6-containers-and-their-lifecycle)
7. [Main lab: run nginx and map a port](#part-7-main-lab-run-nginx-and-map-a-port)
8. [Volumes: keeping data](#part-8-volumes-keeping-data)
9. [Logs, exec and inspect: looking inside](#part-9-logs-exec-and-inspect-looking-inside)
10. [Bonus: build your own image](#part-10-bonus-build-your-own-image)
11. [Clean up](#part-11-clean-up)
12. [Final lab: everything together](#part-12-final-lab-everything-together)
13. [Cheat sheet](#command-cheat-sheet)
14. [Common problems](#common-problems)
15. [Self-check questions](#self-check-questions)
16. [Checklist](#day-checklist)
17. [Save these notes to GitHub](#save-these-notes-to-github)

---

# Part 1: What is Docker and why use it

## The problem Docker solves

> "It works on my laptop, but not on the server."

Your app needs a specific OS libraries, a specific version of Python/Java/nginx, and specific settings. Every machine is a little different, so things break.

## The idea

Docker packs your app **together with everything it needs** into one portable unit. That unit runs the same way on your laptop, on an EC2 server, or in Kubernetes.

## Real-life analogy: shipping containers

Before shipping containers, every cargo (sacks, barrels, cars) needed different handling at every port. Then the standard steel container arrived. Ships, trucks and cranes only had to handle *one* shape, whatever was inside.

Docker does that for software: the app goes into a standard box (container), and any machine with Docker can run the box.

## Containers vs virtual machines

| | Virtual machine | Container |
|---|---|---|
| Includes | A full guest OS plus your app | Only your app and its libraries |
| Size | GBs | MBs |
| Start time | Minutes | Seconds or less |
| Isolation | Strong (separate kernel) | Good (shares the host kernel) |
| Example | An EC2 instance | An nginx process in its own box |

A container is **not a mini computer**. It's an isolated process that thinks it has its own filesystem and network.

---

# Part 2: Core concepts in simple terms

| Term | Simple meaning | Analogy |
|---|---|---|
| **Image** | A read-only package: app + libraries + settings | A recipe, or a class in programming |
| **Container** | A running instance of an image | The dish made from the recipe, or an object |
| **Registry** | A store of images (Docker Hub is the public one) | An app store |
| **Dockerfile** | A text file with instructions to build an image | The written recipe |
| **Port mapping** | Connects a port on your machine to a port inside the container | A phone extension: dial the front desk, get routed to a room |
| **Volume** | Storage that lives outside the container | An external hard drive plugged into the container |
| **Docker daemon** | The background service that does the real work | The engine |
| **Docker CLI** | The `docker` command you type | The steering wheel |

## The flow

```
Dockerfile --build--> Image --run--> Container
                        ^
                        | pull / push
                     Registry (Docker Hub)
```

- One image can start **many** containers.
- Containers are **temporary by default**: delete one and its internal data is gone, unless you used a volume.

---

# Part 3: Install Docker

## Option A: Windows (Docker Desktop)

1. Download **Docker Desktop** from docker.com and run the installer.
2. Keep **Use WSL 2** ticked if offered.
3. Restart if asked, then start Docker Desktop and wait until it says **Engine running**.

Check in PowerShell:

```powershell
docker --version
docker info
```

If `docker info` says it cannot connect to the daemon, Docker Desktop isn't running. Start it and wait a minute.

## Option B: Amazon Linux on EC2

**Amazon Linux 2023:**

```bash
sudo dnf install -y docker
sudo systemctl enable --now docker
```

**Amazon Linux 2:**

```bash
sudo yum install -y docker
sudo systemctl enable --now docker
```

Let `ec2-user` run docker without `sudo`:

```bash
sudo usermod -aG docker ec2-user
```

Log out and back in (or run `newgrp docker`) for the group change to apply, then check:

```bash
docker --version
docker info
```

Not sure which Amazon Linux you have? Run `cat /etc/os-release`.

## Exercise 3

1. Install Docker on your machine (or EC2).
2. Run `docker --version` and note the version.
3. Run `docker info` and find the lines **Containers** and **Images**. Both should be `0` on a fresh install.

---

# Part 4: Your first container: hello-world

```bash
docker run hello-world
```

## What happens, step by step

1. The Docker CLI asks the daemon to run an image called `hello-world`.
2. The daemon looks for it locally and doesn't find it (`Unable to find image 'hello-world:latest' locally`).
3. It **pulls** the image from Docker Hub.
4. It creates a **container** from the image and runs it.
5. The program prints a welcome message and **exits**.

Run it again. This time there is no download, because the image is now cached locally.

```bash
docker ps        # running containers: empty
docker ps -a     # all containers, including stopped: shows hello-world as "Exited"
docker images    # images on this machine: shows hello-world
```

Key point: the container ran and finished. A container lives only as long as its main process runs.

## Exercise 4

1. Run `docker run hello-world` twice.
2. Run `docker ps -a`. How many `hello-world` containers do you see? (Answer: 2, since each `run` creates a new container.)
3. Remove them: `docker rm <container-id>` for each. Check with `docker ps -a`.

---

# Part 5: Images

## Pull and list

```bash
docker pull nginx
docker images
```

Output looks like:

```
REPOSITORY   TAG      IMAGE ID       CREATED       SIZE
nginx        latest   a1b2c3d4e5f6   2 weeks ago   190MB
```

## Image names and tags

`nginx:1.27` has two parts: the **name** (`nginx`) and the **tag** (`1.27`, the version). If you leave off the tag, Docker uses `latest`.

```bash
docker pull nginx:alpine
```

`alpine` is a very small variant of nginx (about 50 MB instead of 190 MB). Compare:

```bash
docker images
```

**Tip:** `latest` changes over time. In real projects, pin a specific tag (like `nginx:1.27`) so your setup stays predictable.

## Layers (why images pull fast the second time)

An image is built from stacked read-only **layers**. Images that share layers share the disk space, and Docker only downloads layers it doesn't already have. See them with:

```bash
docker history nginx
```

## Inspect and remove

```bash
docker image inspect nginx      # full details as JSON
docker search nginx             # search Docker Hub from the terminal
docker rmi nginx:alpine         # remove an image
```

You cannot remove an image while a container (even a stopped one) still uses it. Remove the container first.

## Exercise 5

1. Pull `nginx`, `nginx:alpine` and `busybox`.
2. Run `docker images`. Which is the smallest? (Answer: `busybox`, around 4 MB.)
3. Run `docker history nginx:alpine` and count the layers.
4. Remove `busybox` with `docker rmi busybox`.

---

# Part 6: Containers and their lifecycle

## The lifecycle

```
          create        start          stop
 image ---------> Created ----> Running ----> Stopped (Exited)
                                   |              |
                                   | pause        | start again
                                   v              v
                                Paused         Running
                                                  
                                  rm (on a stopped container) --> gone
```

## The essential commands

| Command | What it does |
|---|---|
| `docker run <image>` | Create **and** start a container |
| `docker ps` | List running containers |
| `docker ps -a` | List all containers |
| `docker stop <name>` | Stop gracefully |
| `docker start <name>` | Start a stopped container again |
| `docker restart <name>` | Stop and start |
| `docker rm <name>` | Delete a stopped container |
| `docker rm -f <name>` | Force delete, even if running |

## Useful `docker run` flags

| Flag | Meaning |
|---|---|
| `-d` | **Detached**: run in the background and give your terminal back |
| `--name web` | Give the container a name instead of a random one |
| `-p 8080:80` | Port mapping (see Part 7) |
| `-v ...` | Volume or bind mount (see Part 8) |
| `-e KEY=value` | Set an environment variable |
| `-it` | Interactive terminal (to get a shell inside) |
| `--rm` | Auto-delete the container when it stops |

## Foreground vs background

```bash
docker run busybox echo "hello from busybox"
```

It prints the message and exits. Now an interactive one:

```bash
docker run -it --rm busybox sh
```

You are now **inside** a container. Try `ls`, `pwd` and `hostname`, then type `exit`. The `--rm` flag removes the container when you leave.

## Exercise 6

1. Run `docker run -d --name sleeper busybox sleep 300`. This keeps a container alive for 5 minutes.
2. `docker ps` should show it. Stop it with `docker stop sleeper`.
3. `docker ps` no longer shows it, but `docker ps -a` does (status Exited).
4. Start it again with `docker start sleeper`, then remove it with `docker rm -f sleeper`.
5. Question: why did the `echo` container exit immediately while `sleeper` stayed up? (Answer: a container runs only as long as its main command runs.)

---

# Part 7: Main lab: run nginx and map a port

This is the core task for the day.

## 7.1 Why port mapping is needed

A container has its **own private network**. nginx listens on port 80 *inside* the container, but your machine can't see that port unless you connect it. Port mapping is that connection:

```
Your browser --> host port 8080 --> container port 80 (nginx)
```

Format: `-p <host-port>:<container-port>`. Host first, container second.

## 7.2 Run nginx WITHOUT mapping (to see the problem)

```bash
docker run -d --name web-nomap nginx
docker ps
```

The `PORTS` column shows `80/tcp` only. Open `http://localhost:80` and it **won't work**, because nothing is mapped. Remove it:

```bash
docker rm -f web-nomap
```

## 7.3 Run nginx WITH port mapping

```bash
docker run -d --name web -p 8080:80 nginx
```

What this means:

| Part | Meaning |
|---|---|
| `docker run` | Create and start a container |
| `-d` | Run in the background |
| `--name web` | Call it `web` |
| `-p 8080:80` | Host port 8080 forwards to container port 80 |
| `nginx` | The image to use |

Check it:

```bash
docker ps
```

```
CONTAINER ID   IMAGE   COMMAND   STATUS         PORTS                  NAMES
3f2a1b9c8d7e   nginx   ...       Up 5 seconds   0.0.0.0:8080->80/tcp   web
```

`0.0.0.0:8080->80/tcp` reads as "anything arriving at host port 8080 goes to port 80 in the container".

## 7.4 Test it

**On Windows (PowerShell):**

Open `http://localhost:8080` in your browser. You should see **"Welcome to nginx!"**.

From the terminal:

```powershell
curl.exe http://localhost:8080
```

Use `curl.exe`, not `curl`. In PowerShell, plain `curl` is an alias for `Invoke-WebRequest` and prints different output.

**On EC2:**

```bash
curl http://localhost:8080
```

To open it from your own browser, allow the port in the EC2 **security group**:

1. AWS Console > EC2 > Instances > select your instance > **Security** tab > click the security group.
2. **Edit inbound rules > Add rule**: Type **Custom TCP**, Port **8080**, Source **My IP**.
3. Save, then open `http://<EC2-public-IP>:8080` in your browser.

Use **My IP** instead of `0.0.0.0/0` so only you can reach it.

## 7.5 Try different host ports

The container side stays `80`, because that's where nginx listens. The host side can be anything free.

```bash
docker run -d --name web2 -p 9090:80 nginx
docker run -d --name web3 -p 9091:80 nginx
```

Now three nginx containers run side by side on ports 8080, 9090 and 9091. Each is separate, but all come from the **same image**. That's the image/container relationship in action.

Check which port maps where:

```bash
docker port web
```

## 7.6 Stop, start, remove

```bash
docker stop web web2 web3
docker start web
docker rm -f web2 web3
```

## 7.7 If you installed nginx on EC2 earlier

If a host-installed nginx already uses port 80 and you map `-p 80:80`, you'll get an error about the port. Either map a different host port (like `8080`) or stop the host service:

```bash
sudo systemctl stop nginx
```

## Exercise 7

1. Run nginx in the background on host port **8081**, named `lab1`.
2. Open it in the browser (or `curl`) and confirm the welcome page.
3. Run `docker port lab1` and `docker ps` and read the mapping.
4. Run a second container named `lab2` on port **8082**.
5. Stop `lab1` and confirm that `8081` no longer responds while `8082` still does.
6. Try to start a third container on port 8082 again. What error do you get? (Answer: `port is already allocated`. Two things cannot listen on the same host port.)
7. Remove all your lab containers.

---

# Part 8: Volumes: keeping data

## 8.1 The problem: container data disappears

Containers are disposable. Anything written inside is **lost when the container is removed**.

**Demo:**

```bash
docker run -d --name tmp1 busybox sleep 300
docker exec tmp1 sh -c "echo 'important data' > /data.txt"
docker exec tmp1 cat /data.txt
```

It prints `important data`. Now delete and recreate:

```bash
docker rm -f tmp1
docker run -d --name tmp1 busybox sleep 300
docker exec tmp1 cat /data.txt
```

Result: `No such file or directory`. The data is gone with the old container.

## 8.2 The solution: volumes

A volume stores data **outside** the container's lifecycle. Two kinds you need to know:

| Type | Syntax | Use it for |
|---|---|---|
| **Named volume** | `-v mydata:/data` | Data Docker manages for you (databases, app data) |
| **Bind mount** | `-v /host/path:/container/path` | Sharing a folder from your machine (your code, config, website files) |

## 8.3 Named volume demo (data survives)

```bash
docker volume create mydata
docker run -d --name vol1 -v mydata:/data busybox sleep 300
docker exec vol1 sh -c "echo 'saved forever' > /data/note.txt"
docker rm -f vol1

docker run -d --name vol2 -v mydata:/data busybox sleep 300
docker exec vol2 cat /data/note.txt
```

It prints `saved forever`. The first container is gone, but the volume kept the file, and the new container sees it.

Useful volume commands:

```bash
docker volume ls
docker volume inspect mydata
docker volume rm mydata        # only after containers using it are removed
```

## 8.4 Bind mount: serve your own web page with nginx

This is the most practical use for now. You edit a file on your PC and nginx serves it instantly.

**Step 1: create a folder and a page**

PowerShell:

```powershell
mkdir html
notepad html\index.html
```

Linux:

```bash
mkdir html
nano html/index.html
```

Paste:

```html
<h1>Hello from my Docker container!</h1>
<p>Served by nginx using a bind mount.</p>
```

**Step 2: run nginx with the folder mounted**

PowerShell (run from the folder that contains `html`):

```powershell
docker run -d --name mysite -p 8080:80 -v "${PWD}/html:/usr/share/nginx/html:ro" nginx
```

Linux:

```bash
docker run -d --name mysite -p 8080:80 -v "$(pwd)/html:/usr/share/nginx/html:ro" nginx
```

| Part | Meaning |
|---|---|
| `${PWD}/html` or `$(pwd)/html` | Folder on your machine |
| `/usr/share/nginx/html` | Where nginx looks for web pages inside the container |
| `:ro` | Read-only, so the container can't change your files |

**Step 3: test and edit live**

Open `http://localhost:8080`. You see your heading instead of the default nginx page. Now edit `index.html` (change the heading), save, and refresh the browser. The change appears **without restarting** the container.

## Exercise 8

1. Create a named volume `webdata`.
2. Run a busybox container with `webdata` mounted at `/data`, write a file, remove the container, start a new one with the same volume, and confirm the file is still there.
3. Run the `mysite` bind-mount lab. Change the page text twice and refresh the browser each time.
4. Question: what is the difference between a named volume and a bind mount? (Answer: a named volume is managed by Docker and stored in its own area, while a bind mount points to a specific folder you choose on your machine.)
5. Remove the containers, then `docker volume rm webdata`.

---

# Part 9: Logs, exec and inspect: looking inside

Start a container to practise on:

```bash
docker run -d --name web -p 8080:80 nginx
```

## Logs

nginx writes access logs to the container's output, which Docker captures.

```bash
docker logs web
docker logs -f web          # follow live; press Ctrl+C to stop
docker logs --tail 20 web   # last 20 lines
```

Refresh the browser at `http://localhost:8080` while following, and you'll see each request appear.

## Exec: run a command inside a running container

```bash
docker exec web nginx -v                # one-off command
docker exec -it web bash                # open a shell inside
```

Inside the shell, try:

```bash
ls /usr/share/nginx/html
cat /etc/nginx/conf.d/default.conf
exit
```

Edit the default page *inside* the container:

```bash
docker exec web sh -c "echo '<h1>Edited inside container</h1>' > /usr/share/nginx/html/index.html"
```

Refresh the browser. The change shows up. But if you `docker rm -f web` and recreate it, the change is gone, which is exactly why volumes exist.

## Copy files in and out

```bash
docker cp web:/etc/nginx/nginx.conf ./nginx.conf     # container to host
docker cp ./index.html web:/usr/share/nginx/html/    # host to container
```

## Inspect and stats

```bash
docker inspect web                      # everything as JSON
docker inspect -f "{{.NetworkSettings.IPAddress}}" web
docker stats                            # live CPU and memory (Ctrl+C to stop)
docker top web                          # processes inside
```

## Exercise 9

1. Start `web` on port 8080 and run `docker logs -f web`. Refresh the browser five times and count the new log lines.
2. Open a shell with `docker exec -it web bash` and find the nginx config file path.
3. Use `docker cp` to copy `nginx.conf` out to your machine and open it.
4. Replace the page content from inside the container, refresh, then remove and recreate the container. What happens to your change? (Answer: it is lost.)

---

# Part 10: Bonus: build your own image

This previews Docker Part 2. Instead of mounting files at run time, you bake them into an image.

**Project layout:**

```
my-nginx/
├── Dockerfile
└── html/
    └── index.html
```

**`Dockerfile`:**

```dockerfile
FROM nginx:alpine
COPY html/ /usr/share/nginx/html/
EXPOSE 80
```

| Line | Meaning |
|---|---|
| `FROM nginx:alpine` | Start from the small nginx image |
| `COPY html/ /usr/share/nginx/html/` | Copy your site into the image |
| `EXPOSE 80` | Documents that the app uses port 80. It does **not** publish the port; `-p` still does that |

**Build and run:**

```bash
cd my-nginx
docker build -t my-nginx:1.0 .
docker images
docker run -d --name mine -p 8080:80 my-nginx:1.0
```

The `.` at the end means "use the current folder as the build context". Don't forget it.

Open `http://localhost:8080` and you see your page, now carried inside the image. You could push this image to Docker Hub and run it on any other machine.

## Exercise 10

1. Build `my-nginx:1.0` as above.
2. Change the heading in `index.html`, rebuild as `my-nginx:2.0`, and run it on port 8081.
3. Run both versions side by side. Observe that each image keeps its own content.

---

# Part 11: Clean up

Docker leaves stopped containers and unused images behind, which eat disk space (important on a small EC2 volume).

```bash
docker ps -a                     # see what exists
docker rm -f $(docker ps -aq)    # remove ALL containers (Linux/Git Bash)
docker container prune           # remove all stopped containers (asks first)
docker image prune               # remove dangling images
docker system df                 # see disk usage
docker system prune              # remove stopped containers, unused networks, dangling images
```

PowerShell version of "remove all containers":

```powershell
docker rm -f (docker ps -aq)
```

Be careful with `-f` and `prune`, because they delete without a second look (except the confirmation prompt on `prune`). Volumes are **not** removed by `docker system prune` unless you add `--volumes`.

---

# Part 12: Final lab: everything together

Do this from scratch without looking at the notes. It combines all concepts.

**Task:** Run a personal web page on nginx in a container, reachable on port **8085**, whose content you can edit live and which survives container re-creation.

1. Create a folder `final-lab/html` with an `index.html` containing your name and today's date.
2. Run nginx named `final` on host port **8085**, with `html` bind-mounted read-only.
3. Open `http://localhost:8085` and confirm your page.
4. Edit the page and refresh to see the live change.
5. Run `docker logs final` and find your browser's requests.
6. Run `docker rm -f final`, then recreate it with the **same** command. Your page is back, since the content lives on your machine, not in the container.
7. Run `docker stop final`, `docker ps -a`, then `docker rm final`.
8. Run `docker system df` and note the image size.

If you can do all 8 steps without help, you understand images, containers, ports and volumes.

---

# Command cheat sheet

| Command | Purpose |
|---|---|
| `docker --version` | Check installed version |
| `docker info` | Daemon and system details |
| `docker pull <image>` | Download an image |
| `docker images` | List local images |
| `docker rmi <image>` | Remove an image |
| `docker run -d --name n -p H:C <image>` | Run in background with name and port map |
| `docker run -it --rm <image> sh` | Temporary interactive shell |
| `docker ps` / `docker ps -a` | List running / all containers |
| `docker stop / start / restart <name>` | Control a container |
| `docker rm <name>` / `docker rm -f <name>` | Delete a container |
| `docker logs -f <name>` | Follow logs |
| `docker exec -it <name> bash` | Shell inside a running container |
| `docker cp` | Copy files between host and container |
| `docker inspect <name>` | Detailed JSON info |
| `docker port <name>` | Show port mappings |
| `docker stats` | Live resource usage |
| `docker volume create / ls / rm` | Manage named volumes |
| `docker build -t name:tag .` | Build an image from a Dockerfile |
| `docker system df` | Disk usage |
| `docker system prune` | Remove unused data |

---

# Common problems

| Problem | Cause and fix |
|---|---|
| `Cannot connect to the Docker daemon` | Docker isn't running. Windows: start Docker Desktop. Linux: `sudo systemctl start docker` |
| `permission denied ... /var/run/docker.sock` | User isn't in the docker group. `sudo usermod -aG docker ec2-user`, then log out and in |
| `port is already allocated` / `address already in use` | Something already uses that host port. Pick another (`-p 8081:80`) or stop the other container or service |
| `container name "/web" is already in use` | A container with that name exists. `docker rm -f web`, or pick another name |
| Page doesn't load on EC2 from your browser | Security group missing an inbound rule for that port |
| Page doesn't load, container shows `Exited` | Check `docker logs <name>` for the reason |
| `curl` output looks odd in PowerShell | Use `curl.exe` instead of `curl` |
| Bind mount shows an empty or default page | Wrong path. Use the full folder path, and check the file name is `index.html` |
| `unable to find image` / pull fails | Check spelling and internet access. Search with `docker search` |
| `image is being used by stopped container` | Remove the container before the image |
| Disk full on EC2 | `docker system df`, then `docker system prune` |

---

# Self-check questions

1. What is the difference between an image and a container? *(An image is a read-only template; a container is a running instance of it.)*
2. Why does `docker run hello-world` exit immediately? *(Its main process finishes, and a container lives only as long as its main process.)*
3. In `-p 8080:80`, which number is the host and which is the container? *(Host 8080, container 80.)*
4. Why can't you open the nginx page without `-p`? *(The container's network is private; the port must be published to the host.)*
5. What happens to data inside a container when you remove it? *(It's lost, unless it was stored in a volume.)*
6. Named volume vs bind mount? *(Docker-managed storage vs a specific folder on your machine.)*
7. What does `-d` do? *(Runs the container in the background.)*
8. How do you see what a container printed? *(`docker logs <name>`.)*
9. How do you get a shell inside a running container? *(`docker exec -it <name> bash`, or `sh`.)*
10. Can two containers use the same host port? *(No. Two things can't listen on one host port at once. They can share the same container port, since each container has its own network.)*

---

# Day checklist

- [ ] Docker installed and `docker --version` works
- [ ] Ran `hello-world` and understood the steps
- [ ] Pulled images, listed them, removed one
- [ ] Started, stopped, restarted and removed containers
- [ ] Ran nginx with `-p 8080:80` and opened the welcome page
- [ ] Ran multiple nginx containers on different ports
- [ ] Opened the port in the EC2 security group (if using EC2)
- [ ] Proved data is lost without a volume, and survives with one
- [ ] Served a custom page via a bind mount and edited it live
- [ ] Used `logs`, `exec`, `cp` and `inspect`
- [ ] Built a custom image (bonus)
- [ ] Cleaned up containers and images
- [ ] Completed the final lab

---

# Save these notes to GitHub

Put this file in the `docker` folder of your `devops` repo, then:

```powershell
cd C:\Users\ADMIN\Devops
git add docker/docker-part1.md
git status
git commit -m "Add Docker part 1 notes"
git push origin main
```

As you complete the exercises, save your own files (Dockerfile, `html/index.html`) in subfolders like `docker/nginx-lab/` and commit them too. Add a `.dockerignore` and `.gitignore` before your next project so secrets and junk stay out of images and out of GitHub.
