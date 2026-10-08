# Learn Docker on AWS EC2 (no Docker on your laptop needed)

Your laptop only needs a browser and PowerShell. Docker itself runs on a small Linux server in AWS.

```
Your laptop (PowerShell + browser)
        |  SSH (port 22)            browser (port 8080)
        v                                 v
   +-------------------- EC2 instance (Amazon Linux) --------------------+
   |   Docker engine                                                     |
   |     +-- nginx container  (host 8080 -> container 80)                |
   +---------------------------------------------------------------------+
```

## Table of Contents

1. [Plan and cost safety](#part-1-plan-and-cost-safety)
2. [Launch the EC2 instance](#part-2-launch-the-ec2-instance)
3. [Connect from your laptop](#part-3-connect-from-your-laptop)
4. [Install Docker on the instance](#part-4-install-docker-on-the-instance)
5. [Lab A: first container](#lab-a-first-container-hello-world)
6. [Lab B: images and container lifecycle](#lab-b-images-and-container-lifecycle)
7. [Lab C: nginx with port mapping](#lab-c-run-nginx-and-map-a-port-main-lab)
8. [Lab D: volumes](#lab-d-volumes)
9. [Lab E: build your own image](#lab-e-build-your-own-image)
10. [Stop or delete the instance](#part-5-stop-or-delete-the-instance-to-avoid-charges)
11. [Common problems](#common-problems)
12. [Checklist](#checklist)

---

# Part 1: Plan and cost safety

| Item | Choice |
|---|---|
| Region | One close to you (for example Asia Pacific (Mumbai) `ap-south-1`) |
| OS image (AMI) | Amazon Linux 2023 |
| Instance type | `t2.micro` or `t3.micro`, whichever the console marks **Free tier eligible** |
| Disk | 8 GiB default is fine; use 16 GiB if you want to keep many images |
| Ports to open | 22 (SSH) and 8080 to 8090 (your containers), **from your IP only** |

**Cost rules to follow from the start:**

- A running instance costs money once free-tier hours or credits are used up. Check your account's current free-tier terms in the Billing console.
- **Stop** the instance when you finish studying. A stopped instance has no compute charge, though its disk still costs a little.
- **Terminate** it when the whole Docker module is done.
- Set a budget alert: AWS Console > Billing > **Budgets** > create a small monthly budget (for example 5 USD) with an email alert.
- A stopped and restarted instance gets a **new public IP**. Always re-check it in the console.

---

# Part 2: Launch the EC2 instance

## 2.1 Open the launch wizard

1. Sign in to the AWS Console and choose your region (top right).
2. Search **EC2**, open it, then click **Launch instance**.

## 2.2 Fill in the form

1. **Name:** `docker-lab`
2. **Application and OS Images:** choose **Amazon Linux**, and select **Amazon Linux 2023 AMI**.
3. **Instance type:** `t2.micro` or `t3.micro` (the one marked free tier eligible).
4. **Key pair (login):** click **Create new key pair**.
   - Name: `docker-lab`
   - Type: RSA, format: **.pem**
   - Click **Create key pair**. The file `docker-lab.pem` downloads. **This is the only time you can download it.**
   - If you already have a key pair from your Terraform practice, you can reuse it, provided you still have the `.pem` file.
5. **Network settings:** click **Edit**.
   - Auto-assign public IP: **Enable**
   - Create a new security group named `docker-lab-sg`.
   - Rule 1: Type **SSH**, port 22, Source type **My IP**.
   - Click **Add security group rule**. Rule 2: Type **Custom TCP**, port range `8080-8090`, Source type **My IP**.
6. **Configure storage:** 8 GiB gp3 is fine (16 GiB if you prefer).
7. Leave everything else as default.
8. Click **Launch instance**.

Why **My IP** and not `0.0.0.0/0`? "My IP" means only your connection can reach the server. Opening SSH to the whole internet invites constant bot attacks. If you later get a timeout from a new network (for example a different Wi-Fi), edit the rule and set My IP again.

## 2.3 Wait and note the public IP

1. Click **View all instances**.
2. Wait until **Instance state** is `Running` and **Status check** is `2/2 checks passed`.
3. Select the instance and copy the **Public IPv4 address** from the details panel. This guide calls it `<PUBLIC-IP>`.

## 2.4 Keep the key safe

Move the downloaded key **outside your Git repo**:

```powershell
mkdir C:\Users\ADMIN\.ssh -ErrorAction SilentlyContinue
move C:\Users\ADMIN\Downloads\docker-lab.pem C:\Users\ADMIN\.ssh\docker-lab.pem
```

Never place a `.pem` file inside `C:\Users\ADMIN\Devops`, because a `git add .` could upload it to GitHub.

## Exercise 2

1. Launch the instance as above.
2. Find in the console: its instance ID, public IP, the security group, and the two inbound rules.
3. Question: why do we open port 8080 and not port 80? (Answer: any free port works, and 8080 avoids clashing with anything already on port 80. The container side is still 80.)

---

# Part 3: Connect from your laptop

## Option 1: SSH from PowerShell (recommended, you learn real server skills)

**3.1 Restrict the key file's permissions.** Windows SSH refuses keys that other users can read.

```powershell
icacls "C:\Users\ADMIN\.ssh\docker-lab.pem" /inheritance:r
icacls "C:\Users\ADMIN\.ssh\docker-lab.pem" /grant:r "$($env:USERNAME):(R)"
```

**3.2 Connect:**

```powershell
ssh -i "C:\Users\ADMIN\.ssh\docker-lab.pem" ec2-user@<PUBLIC-IP>
```

Type `yes` to the fingerprint question the first time. A successful login shows a prompt like:

```
[ec2-user@ip-172-31-xx-xx ~]$
```

Everything from here on runs **on the server**.

If `ssh` is not recognised, install the Windows feature: Settings > Apps > Optional features > **OpenSSH Client**.

## Option 2: Browser-based (no key needed)

1. In the EC2 console select the instance and click **Connect**.
2. Choose the **EC2 Instance Connect** tab, keep the user `ec2-user`, and click **Connect**.

This opens a terminal in your browser. It's a good fallback if SSH gives trouble. It needs port 22 open to AWS's connect service range, so if it fails, SSH from PowerShell is the more reliable route.

## Exercise 3

1. Connect via SSH.
2. Run `whoami`, `hostname` and `cat /etc/os-release`. Confirm it's Amazon Linux 2023.
3. Run `exit`, then reconnect.

---

# Part 4: Install Docker on the instance

On the server:

```bash
sudo dnf update -y
sudo dnf install -y docker
sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user
```

What each line does:

| Command | Meaning |
|---|---|
| `dnf update -y` | Update the server's packages |
| `dnf install -y docker` | Install the Docker engine |
| `systemctl enable --now docker` | Start Docker now and on every boot |
| `usermod -aG docker ec2-user` | Let `ec2-user` run Docker without `sudo` |

The group change applies only to **new** logins, so log out and back in:

```bash
exit
```

```powershell
ssh -i "C:\Users\ADMIN\.ssh\docker-lab.pem" ec2-user@<PUBLIC-IP>
```

Verify:

```bash
docker --version
docker info
systemctl status docker
```

`docker info` should show `Containers: 0` and `Images: 0`. Press `q` to leave the `systemctl status` view.

If you see `permission denied ... docker.sock`, you haven't re-logged in yet, or run `newgrp docker` as a quick fix.

---

# Lab A: first container (hello-world)

```bash
docker run hello-world
docker ps
docker ps -a
docker images
```

What happened: Docker did not find the image locally, **pulled** it from Docker Hub, created a **container**, ran it, and the container exited when its program finished. `docker ps` shows nothing running, and `docker ps -a` shows the exited container.

**Exercise:** run it twice and count the containers in `docker ps -a` (2, because each `run` creates a new one). Remove them with `docker rm <id>`.

---

# Lab B: images and container lifecycle

## Images

```bash
docker pull nginx
docker pull nginx:alpine
docker pull busybox
docker images
docker history nginx:alpine
```

An image name looks like `name:tag`. No tag means `latest`. `alpine` variants are much smaller.

## Containers

```bash
docker run -d --name sleeper busybox sleep 300
docker ps
docker stop sleeper
docker ps -a
docker start sleeper
docker rm -f sleeper
```

| Flag | Meaning |
|---|---|
| `-d` | Run in the background |
| `--name` | Give the container a name |
| `--rm` | Delete the container when it stops |
| `-it` | Interactive terminal |

## Go inside a container

```bash
docker run -it --rm busybox sh
```

Run `ls`, `hostname`, then `exit`.

**Exercise:** compare image sizes in `docker images`. Which is smallest? (`busybox`.) Why does a container running `echo` exit immediately while `sleep 300` stays up? (A container runs only as long as its main process.)

---

# Lab C: run nginx and map a port (main lab)

## C.1 Without port mapping (see the problem)

```bash
docker run -d --name web-nomap nginx
docker ps
curl http://localhost:8080
```

The curl fails, because nothing is published to the host. Remove it:

```bash
docker rm -f web-nomap
```

## C.2 With port mapping

```bash
docker run -d --name web -p 8080:80 nginx
docker ps
```

You should see `0.0.0.0:8080->80/tcp`. The format is `-p <host-port>:<container-port>`:

```
Browser --> EC2 host port 8080 --> container port 80 (nginx)
```

## C.3 Test it

On the server:

```bash
curl http://localhost:8080
```

You'll see the HTML of the "Welcome to nginx!" page.

On your laptop, open a browser at:

```
http://<PUBLIC-IP>:8080
```

You should see **Welcome to nginx!**. If the page times out, see [Common problems](#common-problems): it's almost always the security group.

## C.4 Several containers from one image

```bash
docker run -d --name web2 -p 8081:80 nginx
docker run -d --name web3 -p 8082:80 nginx
docker ps
docker port web2
```

Three independent nginx containers, from one image, on three ports. Open `http://<PUBLIC-IP>:8081` and `:8082` in your browser too.

## C.5 Look inside

```bash
docker logs web
docker logs -f web          # follow; refresh the browser, then Ctrl+C
docker exec -it web bash    # shell inside; try: ls /usr/share/nginx/html ; exit
docker inspect web | head -30
docker stats --no-stream
```

## C.6 Change the page inside the container

```bash
docker exec web sh -c "echo '<h1>Edited inside the container</h1>' > /usr/share/nginx/html/index.html"
```

Refresh the browser: the page changed. Now:

```bash
docker rm -f web
docker run -d --name web -p 8080:80 nginx
```

Refresh again: **the change is gone**. Containers are disposable. That leads to volumes.

## Exercise C

1. Run nginx named `lab1` on port 8085. Confirm it in the browser from your laptop.
2. Start `lab2` on 8085 too. What error do you get? (`port is already allocated`.)
3. Stop `lab1` and confirm the browser can't reach it.
4. Use `docker logs -f` and count the log lines your browser requests create.
5. Remove all containers: `docker rm -f $(docker ps -aq)`.

---

# Lab D: volumes

## D.1 Data lost without a volume

```bash
docker run -d --name tmp1 busybox sleep 300
docker exec tmp1 sh -c "echo 'important data' > /data.txt"
docker exec tmp1 cat /data.txt
docker rm -f tmp1
docker run -d --name tmp1 busybox sleep 300
docker exec tmp1 cat /data.txt
```

The last command fails: the file was lost with the old container.

## D.2 Named volume (data survives)

```bash
docker volume create mydata
docker run -d --name vol1 -v mydata:/data busybox sleep 300
docker exec vol1 sh -c "echo 'saved forever' > /data/note.txt"
docker rm -f vol1
docker run -d --name vol2 -v mydata:/data busybox sleep 300
docker exec vol2 cat /data/note.txt
docker volume ls
docker volume inspect mydata
```

The file survives because it lives in the volume, not in the container.

## D.3 Bind mount: serve your own web page

```bash
mkdir -p ~/html
nano ~/html/index.html
```

Type this, then save with `Ctrl+O`, `Enter`, and exit with `Ctrl+X`:

```html
<h1>Hello from my Docker container on EC2!</h1>
<p>Served by nginx using a bind mount.</p>
```

Run nginx with the folder mounted:

```bash
docker rm -f web 2>/dev/null
docker run -d --name mysite -p 8080:80 -v ~/html:/usr/share/nginx/html:ro nginx
```

Open `http://<PUBLIC-IP>:8080`. Now edit the file, save, and refresh the browser: the change appears **without restarting** the container.

```bash
nano ~/html/index.html
```

| Type | Syntax | Use for |
|---|---|---|
| Named volume | `-v mydata:/data` | Data Docker manages (databases) |
| Bind mount | `-v ~/html:/path` | A folder you control (site files, config) |

## Exercise D

1. Repeat D.2 with a volume called `webdata` and prove the file survives container removal.
2. Run the `mysite` lab and change the page text twice.
3. Remove `mysite`, run it again with the same command, and confirm your page is still served (the content lives on the server's disk, not in the container).

---

# Lab E: build your own image

```bash
mkdir -p ~/my-nginx/html
cd ~/my-nginx
echo "<h1>Baked into my image v1</h1>" > html/index.html
nano Dockerfile
```

Contents of `Dockerfile`:

```dockerfile
FROM nginx:alpine
COPY html/ /usr/share/nginx/html/
EXPOSE 80
```

Build and run:

```bash
docker build -t my-nginx:1.0 .
docker images
docker run -d --name mine -p 8083:80 my-nginx:1.0
```

Open `http://<PUBLIC-IP>:8083`. Note the `.` at the end of `docker build`: it means "use this folder". `EXPOSE 80` only documents the port; `-p` still does the publishing.

**Exercise:** change the heading, rebuild as `my-nginx:2.0`, run it on port 8084, and compare both versions side by side. Open ports 8083 and 8084: both fall in the `8080-8090` rule you created.

---

# Part 5: Stop or delete the instance to avoid charges

## Clean up Docker first (optional)

```bash
docker rm -f $(docker ps -aq)
docker system prune -a
docker system df
```

`prune -a` removes all unused images, so the next pulls will download again. Fine for a lab.

## When you finish a study session: Stop

1. EC2 console > select `docker-lab` > **Instance state** > **Stop instance**.
2. Next time: **Start instance**, copy the **new** public IP, and SSH again with it.

Docker installs, images, volumes and files on the disk stay after a stop/start. Containers you started with `-d` won't automatically restart unless you used `--restart unless-stopped`.

## When the module is finished: Terminate

1. **Instance state > Terminate instance.** This deletes the server and its disk. Everything is gone.
2. Confirm in the console that the state reads `Terminated`.
3. Optional: delete the security group `docker-lab-sg` and the key pair `docker-lab`.
4. Check **Billing > Bills** a day later to make sure nothing is still running. Also look at **EC2 > Volumes** and **Elastic IPs** for leftovers.

---

# Common problems

| Problem | Fix |
|---|---|
| SSH: `Connection timed out` | The security group SSH rule doesn't match your current IP, the instance isn't running, or you used an old public IP. Re-set the rule to My IP and recheck the IP |
| SSH: `Permissions for key are too open` | Run the two `icacls` commands in Part 3 |
| SSH: `Permission denied (publickey)` | Wrong key file, or wrong user. Use `ec2-user` on Amazon Linux |
| Browser page on `:8080` times out | Security group lacks the inbound rule for that port, or your IP changed. Also confirm `docker ps` shows the mapping |
| `curl localhost:8080` works but the browser doesn't | It's the security group. The container is fine |
| `curl localhost:8080` fails too | Container isn't running or not mapped. Run `docker ps -a` and `docker logs <name>` |
| `permission denied ... docker.sock` | Log out and back in after `usermod`, or run `newgrp docker` |
| `Cannot connect to the Docker daemon` | `sudo systemctl start docker` |
| `port is already allocated` | Choose another host port or remove the container using it |
| `container name already in use` | `docker rm -f <name>` |
| `toomanyrequests` when pulling | Docker Hub limits anonymous pulls per IP. Wait a while, or log in with `docker login` using a free account |
| `No space left on device` | `docker system df`, then `docker system prune -a`, or use a bigger disk |
| Public IP changed | Normal after stop/start. Copy the new one from the console |

---

# Checklist

- [ ] Budget alert created in AWS Billing
- [ ] EC2 instance launched (Amazon Linux 2023, free-tier type)
- [ ] Key pair saved in `C:\Users\ADMIN\.ssh`, outside the Git repo
- [ ] Security group: SSH 22 and 8080-8090, source My IP
- [ ] Connected by SSH from PowerShell
- [ ] Docker installed, `docker --version` works without `sudo`
- [ ] Ran hello-world and understood each step
- [ ] Pulled images, listed and removed some
- [ ] Ran nginx with `-p 8080:80` and opened it from my laptop's browser
- [ ] Ran three nginx containers on different ports
- [ ] Proved data is lost without a volume and kept with one
- [ ] Served a custom page with a bind mount and edited it live
- [ ] Built my own image with a Dockerfile
- [ ] Stopped the instance after studying (and terminated it when finished)

---

# Save these notes to GitHub

Copy this file into your repo's `docker` folder and push it:

```powershell
cd C:\Users\ADMIN\Devops
git add docker/docker-on-ec2.md
git commit -m "Add Docker on EC2 guide"
git push origin main
```
