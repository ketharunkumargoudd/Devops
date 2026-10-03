# Demo Shopping Website on Kubernetes (AWS + Terraform + Docker + Maven + Prometheus/Grafana)

End-to-end DevOps project: provision an AWS EC2 server with **Terraform**, build the app with **Maven**, package it with **Docker**, push the image to **Docker Hub**, deploy it to a **Kubernetes** cluster (k3s), and monitor it with **Prometheus + Grafana**.

## Architecture

```
Your laptop ──terraform──▶ AWS EC2 (Ubuntu 22.04, t3.large)
                              ├─ Docker      (build images)
                              ├─ Maven + JDK (build app)
                              └─ k3s         (Kubernetes)
                                   ├─ namespace shop        → shop pods (NodePort 30080)
                                   └─ namespace monitoring  → Prometheus (30090), Grafana (32000)

Source code ─mvn/docker build─▶ Docker Hub ─image pull─▶ Kubernetes
```

## Repo layout

```
.
├── Dockerfile                  # multi-stage: Maven build -> JRE runtime
├── k8s/shop.yaml               # Namespace + Deployment + Service
├── monitoring/values.yaml      # Helm values for kube-prometheus-stack
├── monitoring/shop-servicemonitor.yaml   # optional app metrics scraping
├── terraform/                  # EC2, security group, key pair, bootstrap script
│   ├── main.tf  variables.tf  outputs.tf  user_data.sh
└── README.md
```

Your application source (`pom.xml`, `src/`) goes in the repo root next to the `Dockerfile`.

> **Why k3s?** It is real, certified Kubernetes, but light enough to run on one EC2 box together with Prometheus and Grafana. Once comfortable, the same manifests work on EKS or kubeadm.

---

## Prerequisites (on your laptop)

| Tool | Check |
|---|---|
| AWS account + IAM user with programmatic access | `aws sts get-caller-identity` |
| AWS CLI | `aws --version` |
| Terraform >= 1.5 | `terraform -version` |
| Git + GitHub account | `git --version` |
| Docker Hub account | https://hub.docker.com |
| SSH key pair | `ls ~/.ssh/id_rsa.pub` (create with `ssh-keygen -t rsa -b 4096`) |

Configure AWS credentials:

```bash
aws configure      # access key, secret key, region (e.g. ap-south-1), output json
```

> **Cost note:** t3.large costs roughly a few US cents per hour. Run `terraform destroy` when you finish a session so you are not billed while idle.

---

## Step 1 - Create the GitHub repo and clone it

1. On GitHub create a new repo, e.g. `shop-k8s-devops`.
2. Locally:
   ```bash
   git clone https://github.com/<your-user>/shop-k8s-devops.git
   cd shop-k8s-devops
   ```
3. Copy this project's files into it, and add your application code (`pom.xml`, `src/`).

## Step 2 - Provision EC2 with Terraform

```bash
cd terraform
curl ifconfig.me            # note your public IP
```

Create `terraform.tfvars` (this file is git-ignored):

```hcl
my_ip_cidr = "203.0.113.10/32"     # YOUR IP/32
aws_region = "ap-south-1"
```

Run:

```bash
terraform init
terraform plan
terraform apply            # type 'yes'
```

Outputs show the public IP, SSH command, and URLs. What gets created:

- Key pair from `~/.ssh/id_rsa.pub`
- Security group: SSH (22), K8s API (6443) and NodePorts (30000-32767), all limited to **your IP only**
- Ubuntu 22.04 EC2 (t3.large, 30 GB) whose `user_data.sh` installs Docker, JDK 17, Maven, k3s and Helm

Wait ~3-5 minutes, then connect:

```bash
ssh -i ~/.ssh/id_rsa ubuntu@<public_ip>
ls ~/BOOTSTRAP_DONE                 # exists when bootstrap finished
tail -f /var/log/cloud-init-output.log   # if it is not there yet
```

Verify the tools (log out and back in once so the docker group applies):

```bash
docker --version
mvn -version
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes            # STATUS should be Ready
helm version
```

## Step 3 - Get the code onto the server and build with Maven

```bash
git clone https://github.com/<your-user>/shop-k8s-devops.git
cd shop-k8s-devops
mvn clean package -DskipTests
ls target/*.jar              # (or *.war)
```

Run the build on the EC2 box (or locally) at least once to confirm Maven works before Docker is involved.

## Step 4 - Build the Docker image

The included `Dockerfile` is multi-stage (Maven builds the jar, then a small JRE image runs it).

```bash
docker build -t <dockerhub-user>/shop-app:1.0 .
docker images
docker run -d -p 8081:8080 --name shop-test <dockerhub-user>/shop-app:1.0
curl -I http://localhost:8081      # test, then:
docker rm -f shop-test
```

**If your app is a WAR for Tomcat** replace stage 2 with:

```dockerfile
FROM tomcat:10.1-jdk17
COPY --from=build /app/target/*.war /usr/local/tomcat/webapps/ROOT.war
EXPOSE 8080
```

## Step 5 - Push the image to a registry

### Option A: Docker Hub (simplest, recommended)

```bash
docker login
docker push <dockerhub-user>/shop-app:1.0
```

Keep the repo **public** so Kubernetes can pull it without credentials.

### Option B: GitHub Container Registry (ghcr.io)

```bash
echo <GITHUB_PAT> | docker login ghcr.io -u <github-user> --password-stdin   # PAT needs write:packages
docker tag <dockerhub-user>/shop-app:1.0 ghcr.io/<github-user>/shop-app:1.0
docker push ghcr.io/<github-user>/shop-app:1.0
```

If the package is private, create a pull secret and add `imagePullSecrets` to the Deployment:

```bash
kubectl create secret docker-registry regcred -n shop \
  --docker-server=ghcr.io --docker-username=<github-user> --docker-password=<GITHUB_PAT>
```

> Git itself stores source code, not Docker images. Images go to a *registry* (Docker Hub or ghcr.io); the Git repo holds your code and these manifests.

## Step 6 - Deploy to Kubernetes

Edit `k8s/shop.yaml` and replace `YOUR_DOCKERHUB_USER/shop-app:1.0` with your image, then:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl apply -f k8s/shop.yaml
kubectl get pods -n shop -w
kubectl get svc -n shop
```

Open in a browser: `http://<public_ip>:30080`

Useful debugging commands:

```bash
kubectl describe pod <pod> -n shop
kubectl logs <pod> -n shop
kubectl get events -n shop --sort-by=.lastTimestamp
```

**Releasing a new version:**

```bash
docker build -t <user>/shop-app:1.1 . && docker push <user>/shop-app:1.1
kubectl set image deployment/shop shop=<user>/shop-app:1.1 -n shop
kubectl rollout status deployment/shop -n shop
kubectl rollout undo deployment/shop -n shop     # roll back if needed
```

## Step 7 - Monitoring with Prometheus + Grafana

Edit `monitoring/values.yaml` and change the Grafana admin password. Then:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f monitoring/values.yaml
kubectl get pods -n monitoring -w       # wait until all Running
```

Access:

- Grafana: `http://<public_ip>:32000` (user `admin`, password from `values.yaml`)
- Prometheus: `http://<public_ip>:30090`

In Grafana open **Dashboards** and use the pre-installed ones, for example:

- *Kubernetes / Compute Resources / Namespace (Pods)* - choose namespace `shop` to see CPU/memory of your app
- *Kubernetes / Compute Resources / Node (Pods)* and *Node Exporter / Nodes* - server health

Try a quick load and watch the graphs:

```bash
for i in $(seq 1 500); do curl -s -o /dev/null http://localhost:30080/; done
```

## Step 8 - (Optional) Application-level metrics

If your app is Spring Boot, add to `pom.xml`:

```xml
<dependency>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
<dependency>
  <groupId>io.micrometer</groupId>
  <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

and in `application.properties`:

```properties
management.endpoints.web.exposure.include=health,prometheus
```

Rebuild and push the image, redeploy, then:

```bash
kubectl apply -f monitoring/shop-servicemonitor.yaml
```

In Prometheus **Status > Targets**, a `shop` target should appear. Query for example `http_server_requests_seconds_count` or `jvm_memory_used_bytes`, and import Grafana dashboard ID **4701** (JVM Micrometer).

## Step 9 - Push everything to GitHub

From your laptop (or the server) inside the repo:

```bash
git add .
git status                    # make sure no .tfstate, .pem or tfvars are listed
git commit -m "Add Terraform, Docker, Kubernetes and monitoring setup"
git push origin main
```

Never commit: `terraform.tfstate`, `terraform.tfvars`, private keys, passwords, access tokens. The `.gitignore` covers these. If a secret is ever pushed, rotate it immediately.

## Step 10 - Clean up

```bash
cd terraform
terraform destroy             # removes EC2, security group, key pair
```

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `terraform apply` auth error | Re-run `aws configure`; check `aws sts get-caller-identity` |
| Cannot SSH / site not loading | Your IP changed. Update `my_ip_cidr` and `terraform apply` again |
| `kubectl` says connection refused / permission denied | `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml` |
| Pod `ImagePullBackOff` | Wrong image name/tag, or private repo without pull secret |
| Pod `CrashLoopBackOff` | `kubectl logs <pod> -n shop`; check app port is really 8080 |
| Prometheus pods Pending / OOMKilled | Instance too small; use t3.large or bigger |
| Docker permission denied | Log out/in after bootstrap so the `docker` group applies |

## Next steps (once this works)

1. Add a **GitHub Actions** workflow that runs `mvn package`, builds and pushes the image on every push, then updates the Deployment.
2. Add an **Ingress** with a domain name and HTTPS (cert-manager).
3. Move to **EKS** using Terraform modules; store Terraform state in S3 with DynamoDB locking.
4. Add **Alertmanager** rules (pod restarts, high CPU) and Slack/email notifications.
