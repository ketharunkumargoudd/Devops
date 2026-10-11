# Docker Part 2: Dockerfile, Multi-Stage Builds, Docker Hub

**Goal:** dockerize the demo shop (a Maven project) with a multi-stage Dockerfile, and push the image to Docker Hub.

All commands run on your **EC2 instance** (Amazon Linux, Docker already installed from Part 1), connected from PowerShell with SSH.

## Table of Contents

1. [The big picture](#part-1-the-big-picture)
2. [Prepare the EC2 instance](#part-2-prepare-the-ec2-instance)
3. [Dockerfile basics (with exercises)](#part-3-dockerfile-basics)
4. [The demo shop project](#part-4-the-demo-shop-project)
5. [The wrong way: single-stage build](#part-5-the-wrong-way-single-stage-build)
6. [The right way: multi-stage build](#part-6-the-right-way-multi-stage-build)
7. [Build cache: why order matters](#part-7-build-cache-why-order-matters)
8. [Configure the container with environment variables](#part-8-configure-the-container-with-environment-variables)
9. [Docker Hub: push and pull](#part-9-docker-hub-push-and-pull)
10. [Tagging strategy](#part-10-tagging-strategy)
11. [Using your own demo shop instead](#part-11-using-your-own-demo-shop-instead-of-the-sample)
12. [Save everything to GitHub](#part-12-save-everything-to-github)
13. [Cleanup](#part-13-cleanup-and-cost)
14. [Common problems](#common-problems)
15. [Cheat sheet](#command-cheat-sheet)
16. [Self-check questions](#self-check-questions)
17. [Checklist](#day-checklist)

---

# Part 1: The big picture

```
 Source code          Maven build            Docker build              Registry
 (pom.xml + src) --> (compile, package) --> (image with the app) --> Docker Hub
                       creates app.jar         demo-shop:1.0          <user>/demo-shop:1.0
                                                                              |
                                                       later: Kubernetes pulls it from here
```

| Term | Simple meaning |
|---|---|
| **Dockerfile** | A text recipe that tells Docker how to build an image, step by step |
| **Maven** | The Java build tool. `mvn package` turns your source code into a runnable `.jar` file |
| **Multi-stage build** | One Dockerfile with several `FROM` stages. You build in a big stage, then copy only the result into a small final stage |
| **Docker Hub** | A public online store for images, where you push yours and anyone (or your Kubernetes cluster) can pull them |
| **Tag** | A label on an image version, like `1.0` |

## Why multi-stage?

To build Java you need the **JDK and Maven** (hundreds of MB). To *run* the app you only need a **JRE** and the `.jar`. A multi-stage build uses the big tools to build, then throws them away:

| | Single stage | Multi-stage |
|---|---|---|
| Contains | Maven, JDK, source code, downloaded dependencies, jar | JRE and the jar only |
| Size | Large (hundreds of MB) | Much smaller |
| Security | More tools means a bigger attack surface | Fewer tools means a smaller one |

---

# Part 2: Prepare the EC2 instance

## 2.1 Connect and check Docker

```powershell
ssh -i "C:\Users\ADMIN\.ssh\docker-lab.pem" ec2-user@<PUBLIC-IP>
```

```bash
docker --version
docker ps
```

If `docker ps` shows `permission denied`, log out and back in, or run `newgrp docker`. If it says it can't reach the daemon, run `sudo systemctl start docker`.

## 2.2 Check disk space

```bash
df -h /
```

A Maven build downloads dependencies and creates large layers. Keep at least **3 GB free**. If space is low, clean up Part 1 leftovers:

```bash
docker system prune -a
```

## 2.3 Add swap memory (important on `t2.micro` and `t3.micro`)

These instances have about 1 GB of RAM. Maven can run out of memory and get killed (you'd see `Killed` or exit code `137`). Add 2 GB of swap as a safety net:

```bash
free -h
sudo dd if=/dev/zero of=/swapfile bs=128M count=16
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
free -h
```

The `Swap` row should now show about 2.0G. This lasts until reboot. To make it permanent:

```bash
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

If builds are still slow or fail, use a `t3.small` (2 GB RAM) while you do this lab.

## 2.4 Open the port

Your container will listen on **8080**. In the EC2 security group, make sure an inbound rule allows port **8080** from **My IP** (from Part 1 this likely exists).

---

# Part 3: Dockerfile basics

## 3.1 The instructions you must know

| Instruction | What it does | Example |
|---|---|---|
| `FROM` | The base image to start from (every Dockerfile begins with it) | `FROM nginx:alpine` |
| `WORKDIR` | Set the working folder inside the image (created if missing) | `WORKDIR /app` |
| `COPY` | Copy files from your folder into the image | `COPY pom.xml .` |
| `RUN` | Run a command **while building** (install, compile) | `RUN mvn package` |
| `ENV` | Set an environment variable, available at build **and** run time | `ENV PORT=8080` |
| `ARG` | A variable available **only at build time** | `ARG VERSION=1.0` |
| `EXPOSE` | Documents the port the app uses. It does **not** publish it, since `-p` does that | `EXPOSE 8080` |
| `USER` | Run the rest (and the container) as this user instead of root | `USER app` |
| `CMD` | Default command when the container starts (easy to override) | `CMD ["nginx", "-g", "daemon off;"]` |
| `ENTRYPOINT` | The fixed program the container runs | `ENTRYPOINT ["java", "-jar", "app.jar"]` |
| `HEALTHCHECK` | A command Docker runs to test that the app is healthy | `HEALTHCHECK CMD wget -qO- http://localhost:8080/health` |

**`RUN` vs `CMD`:** `RUN` happens once, at *build* time, and its result is saved in the image. `CMD` and `ENTRYPOINT` happen every time a *container starts*.

**`CMD` vs `ENTRYPOINT`:**

| | `CMD` | `ENTRYPOINT` |
|---|---|---|
| Role | Default command or arguments | The fixed executable |
| `docker run image something` | `something` **replaces** the CMD | `something` is **appended** as an argument |
| Use for | Flexible defaults | Containers that behave like one program (like our app) |

## 3.2 Layers and the build context

- Each instruction creates a **layer**. Docker caches layers and reuses them if nothing above them changed.
- `docker build -t name:tag .` sends the **build context** (the folder given by `.`) to Docker. `COPY` can only use files inside it.
- A `.dockerignore` file lists things to leave out of the context (like `target/`, `.git`), which makes builds faster and safer.

## 3.3 Exercise A: your first Dockerfile (nginx)

```bash
mkdir -p ~/df-lab/html && cd ~/df-lab
echo "<h1>Built with my own Dockerfile</h1>" > html/index.html
nano Dockerfile
```

Contents:

```dockerfile
FROM nginx:alpine
LABEL maintainer="your-name"
COPY html/ /usr/share/nginx/html/
EXPOSE 80
```

Build and run:

```bash
docker build -t my-nginx:1.0 .
docker images my-nginx
docker run -d --name dflab -p 8081:80 my-nginx:1.0
curl http://localhost:8081
```

Look at the build output. Each instruction is a numbered step. Then see the layers:

```bash
docker history my-nginx:1.0
```

Clean up: `docker rm -f dflab`.

## 3.4 Exercise B: ARG vs ENV, and CMD

```bash
mkdir -p ~/df-args && cd ~/df-args
nano Dockerfile
```

Contents:

```dockerfile
FROM busybox
ARG GREETING=Hello
ENV NAME=Docker
RUN echo "$GREETING" > /greeting.txt
CMD ["sh", "-c", "cat /greeting.txt; echo \"from $NAME\""]
```

```bash
docker build -t args-demo .
docker run --rm args-demo
```

Output:

```
Hello
from Docker
```

Now change each:

```bash
docker build --build-arg GREETING=Namaste -t args-demo .
docker run --rm args-demo                     # greeting baked in at build time
docker run --rm -e NAME=World args-demo       # ENV overridden at run time
docker run --rm args-demo echo "CMD replaced" # CMD replaced by your command
```

What you learned:
- `ARG` values are set with `--build-arg` and are fixed into the image at **build** time.
- `ENV` values can be changed with `-e` at **run** time.
- Anything after the image name replaces `CMD`.

Clean up: `docker rmi args-demo my-nginx:1.0`.

---

# Part 4: The demo shop project

You have two options:

- **Option A (this part):** create a small sample Spring Boot "demo shop" that uses Maven, so you can complete the lab exactly as written.
- **Option B:** use your own Maven demo shop. See [Part 11](#part-11-using-your-own-demo-shop-instead-of-the-sample) for what to adapt.

## 4.1 Project layout

```
demo-shop/
├── pom.xml
├── Dockerfile
├── Dockerfile.single
├── .dockerignore
└── src/main/
    ├── java/com/example/shop/
    │   ├── DemoShopApplication.java
    │   ├── Product.java
    │   └── ProductController.java
    └── resources/static/
        └── index.html
```

## 4.2 Create the files on EC2

Copy and paste each block. The `'EOF'` (in quotes) stops the shell from changing anything in the text.

```bash
mkdir -p ~/demo-shop/src/main/java/com/example/shop ~/demo-shop/src/main/resources/static
cd ~/demo-shop
```

**`pom.xml`**

```bash
cat > pom.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.4.1</version>
    <relativePath/>
  </parent>

  <groupId>com.example</groupId>
  <artifactId>demo-shop</artifactId>
  <version>1.0.0</version>
  <name>demo-shop</name>

  <properties>
    <java.version>21</java.version>
  </properties>

  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
  </dependencies>

  <build>
    <finalName>demo-shop</finalName>
    <plugins>
      <plugin>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-maven-plugin</artifactId>
      </plugin>
    </plugins>
  </build>
</project>
EOF
```

`<finalName>demo-shop</finalName>` makes Maven produce `target/demo-shop.jar`, a name that is easy to refer to in the Dockerfile.

**`DemoShopApplication.java`**

```bash
cat > src/main/java/com/example/shop/DemoShopApplication.java <<'EOF'
package com.example.shop;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class DemoShopApplication {
    public static void main(String[] args) {
        SpringApplication.run(DemoShopApplication.class, args);
    }
}
EOF
```

**`Product.java`**

```bash
cat > src/main/java/com/example/shop/Product.java <<'EOF'
package com.example.shop;

public record Product(int id, String name, int price) {}
EOF
```

**`ProductController.java`**

```bash
cat > src/main/java/com/example/shop/ProductController.java <<'EOF'
package com.example.shop;

import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ProductController {

    @GetMapping("/api/products")
    public List<Product> products() {
        return List.of(
            new Product(1, "Laptop", 55000),
            new Product(2, "Headphones", 2500),
            new Product(3, "Keyboard", 1500)
        );
    }

    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "UP");
    }
}
EOF
```

**`index.html`** (the shop page)

```bash
cat > src/main/resources/static/index.html <<'EOF'
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Demo Shop</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 40px; }
    .item { border: 1px solid #ccc; padding: 10px; margin: 8px 0; width: 300px; }
  </style>
</head>
<body>
  <h1>Demo Shop</h1>
  <div id="list">Loading...</div>
  <script>
    fetch('/api/products')
      .then(function (r) { return r.json(); })
      .then(function (items) {
        document.getElementById('list').innerHTML = items.map(function (p) {
          return '<div class="item"><b>' + p.name + '</b><br>Price: ' + p.price + '</div>';
        }).join('');
      });
  </script>
</body>
</html>
EOF
```

**`.dockerignore`**

```bash
cat > .dockerignore <<'EOF'
target/
.git/
*.log
*.md
.env
*.pem
EOF
```

Check the layout:

```bash
find . -type f | sort
```

## 4.3 Optional: test Maven without Docker

You don't need this, because the Docker build does it for you. If you want to see it:

```bash
sudo dnf install -y java-21-amazon-corretto-devel maven
mvn -B package -DskipTests
ls -lh target/demo-shop.jar
java -jar target/demo-shop.jar
```

Press `Ctrl+C` to stop it. One of the benefits of multi-stage builds is that you can skip installing Java and Maven on the server entirely.

---

# Part 5: The wrong way: single-stage build

Build it the naive way first, so you can see the problem.

```bash
cat > Dockerfile.single <<'EOF'
FROM maven:3.9-eclipse-temurin-21
WORKDIR /app
COPY . .
RUN mvn -B package -DskipTests
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "target/demo-shop.jar"]
EOF
```

```bash
docker build -f Dockerfile.single -t demo-shop:single .
docker images demo-shop
```

The first build takes several minutes, because it downloads Maven dependencies. The image is large (several hundred MB), since it still contains Maven, the full JDK, the source code, and all downloaded dependencies, none of which are needed to *run* the app.

Run and test it:

```bash
docker run -d --name shop-single -p 8080:8080 demo-shop:single
docker logs -f shop-single       # wait for "Started DemoShopApplication", then Ctrl+C
curl http://localhost:8080/health
curl http://localhost:8080/api/products
docker rm -f shop-single
```

It works, but it's heavy. Note the size from `docker images` for the comparison in Part 6.

---

# Part 6: The right way: multi-stage build

## 6.1 The Dockerfile

```bash
cat > Dockerfile <<'EOF'
# ---------- Stage 1: build with Maven ----------
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /build

# Copy only pom.xml first, so the dependency layer is cached
COPY pom.xml .
RUN mvn -B dependency:go-offline

# Now copy the source and build the jar
COPY src ./src
RUN mvn -B package -DskipTests

# ---------- Stage 2: small runtime image ----------
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

# Run as a non-root user
RUN addgroup -S app && adduser -S app -G app

# Copy ONLY the jar from the build stage
COPY --from=build /build/target/demo-shop.jar app.jar

USER app
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=40s \
  CMD wget -qO- http://localhost:8080/health || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]
EOF
```

## 6.2 How to read it

| Line | Meaning |
|---|---|
| `FROM maven:... AS build` | Stage 1 is named `build`. It has Maven and the JDK |
| `COPY pom.xml .` then `RUN mvn dependency:go-offline` | Download dependencies in their own layer, so they're cached |
| `COPY src ./src` then `RUN mvn package` | Compile and package the jar. Only this layer redoes when your code changes |
| `FROM eclipse-temurin:21-jre-alpine` | Stage 2 starts **fresh** from a small JRE image. Nothing from stage 1 comes along unless copied |
| `COPY --from=build ... app.jar` | The one thing carried over: the finished jar |
| `RUN addgroup ... adduser` and `USER app` | A normal user runs the app, since running as root in a container is a security risk |
| `HEALTHCHECK` | Docker marks the container `healthy` or `unhealthy` by calling `/health` |
| `ENTRYPOINT [...]` | The app starts when the container starts |

The JSON-array form `["java", "-jar", "app.jar"]` runs the program directly as the main process, so it receives stop signals correctly.

## 6.3 Build

```bash
docker build -t demo-shop:1.0 .
docker images demo-shop
```

You'll see output like this (your sizes will differ):

```
REPOSITORY   TAG      SIZE
demo-shop    1.0      ~150-250MB
demo-shop    single   ~700MB or more
```

Same app, a fraction of the size. Compare the layers:

```bash
docker history demo-shop:1.0
docker history demo-shop:single
```

## 6.4 Run and test

```bash
docker run -d --name shop -p 8080:8080 demo-shop:1.0
docker ps
docker logs -f shop        # wait for "Started DemoShopApplication", then Ctrl+C
curl http://localhost:8080/health
curl http://localhost:8080/api/products
```

In your laptop's browser, open:

```
http://<PUBLIC-IP>:8080
```

You should see **Demo Shop** with three products. Check the health status:

```bash
docker ps
```

The `STATUS` column shows `Up ... (health: starting)` at first, then `(healthy)` after the first successful check.

## Exercise 6

1. Build `demo-shop:1.0` and compare its size with `demo-shop:single`.
2. Run `docker history demo-shop:1.0`. Which layer is largest? (Answer: the base JRE.)
3. Run `docker exec shop whoami`. What user is it? (Answer: `app`, not root.)
4. Open the shop in your browser.
5. Try `docker exec shop mvn -v`. What happens? (Answer: `not found`, because Maven isn't in the final image. That's the multi-stage benefit.)

---

# Part 7: Build cache: why order matters

## 7.1 See the cache work

Rebuild without changing anything:

```bash
docker build -t demo-shop:1.0 .
```

Every step says `CACHED` and it finishes in seconds.

Now change the source code:

```bash
sed -i 's/Demo Shop/My Demo Shop/' src/main/resources/static/index.html
docker build -t demo-shop:1.1 .
```

Watch the output:
- `COPY pom.xml` and `mvn dependency:go-offline` show **CACHED**, so there's no re-download.
- Only the `COPY src` step and everything after it runs again.

Run the new version on another port:

```bash
docker run -d --name shop11 -p 8081:8080 demo-shop:1.1
```

Open `http://<PUBLIC-IP>:8081` (allow port 8081 in the security group first, or stop the first container and reuse 8080).

## 7.2 Why this works

Docker rebuilds from the **first changed layer onward**. Dependencies change rarely and source code changes constantly, so the Dockerfile copies `pom.xml` first. If you did `COPY . .` at the top, every code edit would re-download all dependencies.

**Rule:** put the things that change **least** at the top, and the things that change **most** at the bottom.

## Exercise 7

1. Rebuild with no changes and confirm every step is `CACHED`.
2. Edit the page and rebuild. Which steps still say `CACHED`?
3. Edit `pom.xml` (for example, change `<version>1.0.0</version>` to `1.0.1`) and rebuild. What re-runs? (Answer: the dependency step and everything after it, since the first layer changed.)

---

# Part 8: Configure the container with environment variables

The same image should work in different environments. Spring Boot reads environment variables, so `SERVER_PORT` changes its port.

```bash
docker rm -f shop shop11
docker run -d --name shop9090 -p 9090:9090 -e SERVER_PORT=9090 demo-shop:1.0
curl http://localhost:9090/health
```

The app now listens on 9090 *inside* the container, so the mapping is `-p 9090:9090`. (The healthcheck still calls 8080 and would mark this container unhealthy. That's a good reason to keep ports consistent in real projects.)

Clean up: `docker rm -f shop9090`.

**Never bake secrets (passwords, tokens, keys) into an image.** Anyone who gets the image can read them. Pass them at run time with `-e` or a secrets tool.

---

# Part 9: Docker Hub: push and pull

## 9.1 Create an account and a token

1. Sign up at **hub.docker.com** and note your **username**. This guide writes it as `<dockerhub-username>`.
2. Create an **access token** instead of using your password: open **Account settings > Personal access tokens** (menu names may vary slightly), click **Generate new token**, give it a description like `ec2-lab`, set **Read & Write** access, and copy the token. It's shown only once.

Treat the token like a password. Never put it in a file in your repo or paste it into a chat.

## 9.2 Log in from EC2

This keeps the token out of your shell history:

```bash
read -s -p "Docker Hub token: " DHTOKEN; echo
echo "$DHTOKEN" | docker login -u <dockerhub-username> --password-stdin
unset DHTOKEN
```

Expected: `Login Succeeded`.

## 9.3 Tag the image with your Docker Hub name

Docker Hub requires image names in the form `<username>/<repository>:<tag>`.

```bash
docker tag demo-shop:1.0 <dockerhub-username>/demo-shop:1.0
docker images | grep demo-shop
```

Both names now point to the **same image** (same IMAGE ID). A tag is just a label.

## 9.4 Push

```bash
docker push <dockerhub-username>/demo-shop:1.0
```

You'll see layers uploading. Layers that Docker Hub already has (like the base JRE) show `Layer already exists`.

Also publish a `latest` tag:

```bash
docker tag demo-shop:1.0 <dockerhub-username>/demo-shop:latest
docker push <dockerhub-username>/demo-shop:latest
```

## 9.5 Verify on Docker Hub

Open `https://hub.docker.com/r/<dockerhub-username>/demo-shop` in your browser. You should see the repository with tags `1.0` and `latest`. A repository created by a push is public by default. You can change this under the repository's **Settings**, though free plans limit private repositories.

## 9.6 Pull and run it as a stranger would

Delete all local copies, then run straight from Docker Hub:

```bash
docker rm -f shop 2>/dev/null
docker rmi demo-shop:1.0 demo-shop:1.1 demo-shop:single \
  <dockerhub-username>/demo-shop:1.0 <dockerhub-username>/demo-shop:latest

docker run -d --name shop -p 8080:8080 <dockerhub-username>/demo-shop:1.0
```

Docker finds nothing locally, **pulls** the image from Docker Hub, and starts it. Open `http://<PUBLIC-IP>:8080` to confirm. This proves the image is self-contained and could run on any machine, including your Kubernetes cluster later.

## 9.7 Log out when you're done

```bash
docker logout
```

`docker login` saves credentials in `~/.docker/config.json`. On a shared or throwaway server, log out. If a token was ever exposed, delete it under Docker Hub's token settings and create a new one.

## 9.8 Optional: GitHub Container Registry instead

You could push to GitHub's registry (`ghcr.io`) instead. Create a GitHub **personal access token** with `write:packages`, then:

```bash
echo "$GHTOKEN" | docker login ghcr.io -u <github-username> --password-stdin
docker tag demo-shop:1.0 ghcr.io/<github-username>/demo-shop:1.0
docker push ghcr.io/<github-username>/demo-shop:1.0
```

Docker Hub is the simplest to start with.

## Exercise 9

1. Push `demo-shop:1.0` to your Docker Hub repo.
2. Confirm in the browser that the tag appears.
3. Remove every local copy, then run the image from Docker Hub. Watch the pull messages.
4. Question: why did the second push of `latest` upload almost nothing? (Answer: it's the same image, and tags are just labels pointing to the same layers.)

---

# Part 10: Tagging strategy

| Tag | Use | Problem |
|---|---|---|
| `latest` | The newest push | It moves. You can't tell which version you're running |
| `1.0`, `1.1` | A version number | Good. You know exactly what runs |
| `abc1234` | A Git commit ID | Best for traceability in CI/CD |

Good habits:
- Publish a **version tag** every time, and use it when deploying (in Kubernetes, `image: <user>/demo-shop:1.1`, not `latest`).
- Never overwrite an existing version tag with different content.
- Use `latest` only as a convenience.

Tag with the commit ID, if your project is a Git repo:

```bash
docker tag demo-shop:1.1 <dockerhub-username>/demo-shop:$(git rev-parse --short HEAD)
```

---

# Part 11: Using your own demo shop instead of the sample

Adapt the multi-stage Dockerfile to your own Maven project by checking these:

| Check | How | Change in Dockerfile |
|---|---|---|
| **Java version** | `<java.version>` or `maven.compiler.source` in `pom.xml` | Use matching images, such as `maven:3.9-eclipse-temurin-17` and `eclipse-temurin:17-jre-alpine` |
| **Jar name** | Build once and run `ls target/*.jar`, or set `<finalName>` in `pom.xml` | Update the `COPY --from=build /build/target/<name>.jar app.jar` line |
| **Port** | `server.port` in `application.properties` (the default is 8080) | Update `EXPOSE`, `-p`, and the healthcheck |
| **Runnable jar** | The app must be a Spring Boot *executable* jar (`spring-boot-maven-plugin` in `pom.xml`). A plain jar gives `no main manifest attribute` | Add the plugin, or run it with a different `java -cp ...` command |
| **WAR instead of a jar** | `<packaging>war</packaging>` | Use `FROM tomcat:10-jre21` for the final stage and `COPY --from=build /build/target/*.war /usr/local/tomcat/webapps/ROOT.war` |
| **Health endpoint** | Does `/health` exist? Spring's `/actuator/health` needs the actuator dependency | Change the `HEALTHCHECK` URL or remove the line |
| **Multi-module Maven project** | Several folders with their own `pom.xml` | Copy all `pom.xml` files first, then the sources |

Get your project onto the EC2 instance in one of two ways:

```bash
git clone https://github.com/<github-username>/<repo>.git
```

or from your laptop, in PowerShell:

```powershell
scp -i "C:\Users\ADMIN\.ssh\docker-lab.pem" -r "C:\path\to\demo-shop" ec2-user@<PUBLIC-IP>:~/
```

Put a `.dockerignore` with `target/` and `.git/` in its root before building.

---

# Part 12: Save everything to GitHub

Add the project and these notes to your `devops` repo. On your laptop:

```powershell
cd C:\Users\ADMIN\Devops
# copy the demo-shop folder (without target/) and docker-part2.md into your repo
git status
git add -v "WEEKLY plan/Docker/docker-part2.md"
git add -v demo-shop
git status
git commit -m "Add Docker part 2 notes and demo-shop Dockerfile"
git push origin main
```

Before committing:
- Add `target/` to `.gitignore`, because the built jar and Maven output don't belong in Git.
- Make sure **no tokens, `.pem` files, or `.env` files** are in the folder. `git status` should show only source files and notes.

To copy files from EC2 back to your laptop, in PowerShell:

```powershell
scp -i "C:\Users\ADMIN\.ssh\docker-lab.pem" -r ec2-user@<PUBLIC-IP>:~/demo-shop C:\Users\ADMIN\Devops\
```

Delete `target/` from the copy if it came along.

---

# Part 13: Cleanup and cost

```bash
docker rm -f $(docker ps -aq)
docker system df
docker system prune -a
docker logout
```

Then in the EC2 console, **stop the instance** when you finish studying, and **terminate** it (and delete any extra EBS volumes) when the module is done. A running instance and an unused volume both keep costing money. If you made a swap file, it disappears with the instance.

---

# Common problems

| Problem | Cause and fix |
|---|---|
| Build ends with `Killed` or exit code `137` | Out of memory during Maven. Add swap (Part 2.3) or use a `t3.small` |
| `COPY failed: file not found in build context` | The file isn't inside the folder you built from, or `.dockerignore` excludes it. Run `docker build` from the project root and check spelling |
| `COPY --from=build ... target/demo-shop.jar: not found` | The jar has a different name. Build, then check `ls target/`, or set `<finalName>` in `pom.xml` |
| `no main manifest attribute, in app.jar` | Not a Spring Boot executable jar. Add `spring-boot-maven-plugin` |
| `UnsupportedClassVersionError` | The runtime Java is older than the one used to compile. Match both stages (for example 17 and 17, or 21 and 21) |
| `mvn dependency:go-offline` fails | Some plugins can't be pre-fetched. Delete those two lines (`COPY pom.xml`, `RUN mvn ... go-offline`) and use `COPY . .` then `RUN mvn -B package -DskipTests`. It still works, with less caching |
| Maven can't download dependencies | The EC2 instance has no internet access. Check its subnet, route table and security group outbound rules |
| `port is already allocated` | Another container uses 8080. Run `docker ps`, then `docker rm -f <name>` or choose another host port |
| Container exits straight after start | Check `docker logs <name>`. Common causes: wrong jar name, port clash, or a Java version error |
| Browser can't reach the app | Security group missing the port, or you used `https://`. Test `curl localhost:8080` on the server first |
| `unauthorized: incorrect username or password` on login | Use the **access token**, not your account password, and the exact Docker Hub **username** |
| `denied: requested access to the resource is denied` on push | Not logged in, or the image isn't named `<your-username>/...`. Run `docker login`, then `docker tag` with your username and push again |
| `toomanyrequests` when pulling | Docker Hub limits anonymous pulls. Log in with `docker login`, or wait |
| `no space left on device` | `docker system df`, then `docker system prune -a`, or add an EBS disk |
| Container shows `unhealthy` | The `HEALTHCHECK` URL or port is wrong, or the app hasn't started yet. Check `docker logs` and `docker inspect --format '{{json .State.Health}}' shop` |

---

# Command cheat sheet

| Command | Purpose |
|---|---|
| `docker build -t name:tag .` | Build an image from the Dockerfile in this folder |
| `docker build -f Dockerfile.single -t name:tag .` | Build using a specific Dockerfile |
| `docker build --build-arg KEY=value -t name:tag .` | Pass a build-time `ARG` |
| `docker build --no-cache -t name:tag .` | Ignore the cache and rebuild everything |
| `docker history <image>` | Show an image's layers and sizes |
| `docker run -e KEY=value ...` | Set an environment variable at run time |
| `docker tag <src> <user>/<repo>:<tag>` | Add a name to an image |
| `docker login -u <user> --password-stdin` | Log in to Docker Hub with a token |
| `docker push <user>/<repo>:<tag>` | Upload an image |
| `docker pull <user>/<repo>:<tag>` | Download an image |
| `docker logout` | Remove saved credentials |
| `docker inspect <name>` | Full details of a container or image |
| `docker system df` | Disk usage |
| `docker system prune -a` | Remove unused images, containers, networks |

---

# Self-check questions

1. What is the difference between `RUN` and `CMD`? *(`RUN` executes at build time and is saved in the image. `CMD` runs when a container starts.)*
2. What is a multi-stage build, and why use one? *(Several `FROM` stages: build with big tools, copy only the result into a small final image. It gives a smaller, safer image.)*
3. What does `COPY --from=build` do? *(Copies files from the earlier stage named `build` into the current stage.)*
4. Why copy `pom.xml` before the source code? *(To cache the dependency download layer, so code changes don't trigger a re-download.)*
5. Does `EXPOSE 8080` make the port reachable from outside? *(No. It only documents the port. You must publish it with `-p`.)*
6. What is the difference between `ARG` and `ENV`? *(`ARG` exists only at build time. `ENV` also exists at run time and can be overridden with `-e`.)*
7. Why run the container as a non-root user? *(If the app is compromised, the attacker has fewer privileges.)*
8. What must an image name look like to push it to Docker Hub? *(`<username>/<repository>:<tag>`.)*
9. Why use an access token instead of your password? *(It can be limited and revoked without changing your account password.)*
10. Why avoid deploying with only the `latest` tag? *(It moves, so you can't tell which version is running or roll back reliably.)*

---

# Day checklist

- [ ] EC2 instance running, Docker works, swap added, 3 GB or more free
- [ ] Wrote and built a basic Dockerfile (nginx) and understood each instruction
- [ ] Tried `ARG` vs `ENV` and overrode `CMD`
- [ ] Created the demo shop project (or adapted my own Maven project)
- [ ] Built the single-stage image and noted its size
- [ ] Built the multi-stage image and compared sizes
- [ ] Ran the shop container and opened it in the browser on port 8080
- [ ] Saw the cache work and saw which layers rebuild on a change
- [ ] Passed a setting with `-e` at run time
- [ ] Created a Docker Hub account and access token
- [ ] Logged in, tagged and pushed `demo-shop:1.0` (and `latest`)
- [ ] Deleted local copies and ran the image straight from Docker Hub
- [ ] Logged out and kept the token out of GitHub
- [ ] Pushed the notes and project to my `devops` GitHub repo
- [ ] Stopped the EC2 instance when finished

**Next step:** deploy this image to your Kubernetes cluster by referencing `<dockerhub-username>/demo-shop:1.0` in a Deployment.
