# 2-Week DevOps Learning Plan

**Author:** Tharun Kumar
**Background:** Windows Networking Engineer (LTIMindtree)
**Time budget:** 2 weeks x 20 hrs/week = 40 hrs
**Goal:** Job-ready DevOps foundations plus one end-to-end portfolio project

> Realistic target: not "pro" in 40 hours, but solid fundamentals and a project I can demo and explain in interviews.

---

## Key Skills (in order of market demand)

1. Linux and shell basics
2. Git and GitHub
3. Docker
4. CI/CD (GitHub Actions, Jenkins basics)
5. Terraform (Infrastructure as Code)
6. AWS core services (EC2, VPC, IAM, S3, ELB)
7. Kubernetes (EKS)
8. Monitoring (Prometheus and Grafana)
9. Basic scripting (Bash or Python)

**My edge:** networking knowledge (VPC, subnets, routing, security groups, DNS, load balancers) maps directly to cloud networking.

---

## Weekly Time Split

| Days | Hours/day | Total |
|---|---|---|
| Mon - Fri | 2 | 10 |
| Sat | 5 | 5 |
| Sun | 5 | 5 |
| **Week total** | | **20** |

---

## Week 1: Foundations, Containers, CI/CD

| Day | Hrs | Focus | Practice | Done |
|---|---|---|---|---|
| Mon | 2 | Linux basics: files, permissions, processes, `grep`, `curl`, `systemctl` (WSL2 or EC2 Linux) | Navigate, edit, chmod files; read logs | [ ] |
| Tue | 2 | Bash scripting: variables, loops, conditions | Script that checks disk space and service status | [ ] |
| Wed | 2 | Git in depth: branches, merge, pull requests, `.gitignore` | Push local `devops` folder to GitHub repo `devops`; create and merge a branch | [ ] |
| Thu | 2 | Docker part 1: images, containers, ports, volumes | Run nginx in a container and map a port | [ ] |
| Fri | 2 | Docker part 2: Dockerfile, multi-stage builds, Docker Hub | Dockerize the demo shop (Maven build) and push the image | [ ] |
| Sat | 5 | Docker Compose, then CI with GitHub Actions | On push: Maven build, Docker build, push to Docker Hub | [ ] |
| Sun | 5 | Jenkins basics (install, Jenkinsfile, pipeline job) and revision | Rebuild the same pipeline in Jenkins; document in README | [ ] |

**Week 1 checkpoint:** a push to GitHub automatically builds and publishes my Docker image.

---

## Week 2: Cloud, Terraform, Kubernetes, Monitoring

| Day | Hrs | Focus | Practice | Done |
|---|---|---|---|---|
| Mon | 2 | AWS core: IAM (users, roles, policies), EC2, S3, CLI | IAM user with least privilege, `aws configure`, upload to S3 | [ ] |
| Tue | 2 | Terraform part 1: providers, resources, variables, outputs, state | Finish VPC script: VPC, subnets, IGW, route tables | [ ] |
| Wed | 2 | Terraform part 2: modules, remote state (S3), plan/apply workflow | Add EC2 instance and security group to the VPC | [ ] |
| Thu | 2 | Kubernetes concepts: pods, deployments, services, ConfigMaps, namespaces | Practice locally with minikube or kind using `kubectl` | [ ] |
| Fri | 2 | Kubernetes part 2: Ingress, scaling, rolling updates, debugging (`describe`, `logs`) | Deploy shop image locally, scale it, do a rolling update | [ ] |
| Sat | 5 | EKS: create cluster in `myvpc` (Terraform or `eksctl`), deploy the app | Deploy the shop (or love site) as pods behind a LoadBalancer or Ingress | [ ] |
| Sun | 5 | Prometheus and Grafana (install via Helm), dashboards, repo cleanup | CPU/memory dashboard; final README with architecture diagram | [ ] |

**Week 2 checkpoint:** infrastructure from Terraform, app running on Kubernetes, monitoring in place.

---

## Rules I Follow

- **Control AWS cost.** EKS control plane is about $0.10/hr, plus worker nodes and NAT gateway. Run `terraform destroy` or delete the cluster after every session. Practice Kubernetes locally first; use EKS only on Saturday of Week 2.
- **70% hands-on, 30% reading.** Type every command myself.
- **One repo as portfolio.** Commit daily with a clear README.
- **Keep a "broke and fixed" log** (see below). Troubleshooting stories are what interviewers ask about.

---

## Resources

- Docker: official "Get Started" docs
- Kubernetes: kubernetes.io tutorials, killercoda.com (free browser labs)
- Terraform: HashiCorp Developer tutorials for AWS
- YouTube: TechWorld with Nana, KodeKloud intro videos

---

## After Two Weeks (Weeks 3-4)

1. Helm and ArgoCD (GitOps)
2. Ansible
3. AWS certification (Cloud Practitioner, then Solutions Architect Associate or CKA path)
4. Security scanning (Trivy, SonarQube)
5. Mock interviews and a resume that combines networking experience with this project

---

## Suggested Repo Structure

```
devops/
├── README.md              <- this plan
├── week1/
│   ├── linux/
│   ├── docker/
│   └── ci-cd/
├── week2/
│   ├── terraform/
│   ├── kubernetes/
│   └── monitoring/
└── notes/
    └── troubleshooting-log.md
```

---

## Troubleshooting Log

| Date | Problem | Cause | Fix |
|---|---|---|---|
| | | | |

---

## Push This to GitHub (PowerShell)

```powershell
cd C:\Users\ADMIN\Devops
git init
git add README.md
git commit -m "Add 2-week DevOps learning plan"
git branch -M main
git remote add origin https://github.com/<your-username>/devops.git
git push -u origin main
```

If the repo already exists and has a remote, skip `git init` and `git remote add`, and just run `git add`, `git commit`, `git push`.
