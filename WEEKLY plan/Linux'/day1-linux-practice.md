# Day 1: Linux Practice on EC2 (Amazon Linux)

**Server:** Amazon Linux EC2, login user `ec2-user`
**Time:** about 2 hours
**Rule:** type every command yourself and read the output.

## Connect

```powershell
ssh -i C:\Users\ADMIN\.ssh\<your-key>.pem ec2-user@<public-ip>
```

The public IP changes every time the instance is stopped and started. Copy the new one from the console.

---

## Part 1: Know your server (10 min)

```bash
whoami                      # your username (ec2-user)
hostname                    # server name
cat /etc/os-release         # OS version
uname -a                    # kernel info
uptime                      # time since boot
date                        # current date and time
sudo dnf check-update       # optional: list available updates
```

**Exercise:** write down the OS version and kernel version.

---

## Part 2: Files and directories (20 min)

### Navigate
```bash
pwd                         # where am I
ls                          # list files
ls -la                      # long format plus hidden files
cd /                        # root of the filesystem
ls                          # look at the main directories
cd ~                        # back to home
cd /var/log && pwd          # go to logs, confirm location
cd -                        # jump back to the previous folder
cd ..                       # up one level
```

### Create a practice area
```bash
mkdir devops-practice
cd devops-practice
mkdir -p lab/logs lab/scripts lab/backup    # nested folders in one go
touch notes.txt todo.txt
ls -R                                       # recursive listing
```

### Write and read files
```bash
echo "Hello DevOps" > notes.txt             # overwrite
echo "Day 1 on EC2" >> notes.txt            # append
cat notes.txt
nano todo.txt                               # type text, Ctrl+O, Enter, Ctrl+X
cat -n todo.txt                             # with line numbers
```

### Copy, move, delete
```bash
cp notes.txt lab/backup/notes-copy.txt
mv todo.txt lab/todo-renamed.txt
rm lab/backup/notes-copy.txt
rm -r lab/backup                            # delete a folder (no recycle bin!)
```

### View parts of big files
```bash
head -n 5 /etc/passwd
tail -n 5 /etc/passwd
less /etc/services                          # arrows to scroll, / to search, q to quit
wc -l /etc/passwd                           # count lines
```

### Find things
```bash
find ~ -name "notes.txt"
find /etc -name "*.conf" 2>/dev/null | head
which ls
ls /etc /var/log /home /tmp /usr/bin        # know the key directories
```

**Exercise:** build `lab/projects/web/` and `lab/projects/api/`, put a file in each, then verify with `ls -R lab`.

---

## Part 3: Permissions and users (20 min)

```bash
ls -l notes.txt
# -rw-r--r--. 1 ec2-user ec2-user 16 Oct  5 17:52 notes.txt
```

Read it as: file type, owner (`rw-`), group (`r--`), others (`r--`). The trailing `.` is an SELinux label and can be ignored for now.

| Number | Meaning |
|---|---|
| 4 | read |
| 2 | write |
| 1 | execute |

```bash
chmod 600 notes.txt                         # owner read/write only
ls -l notes.txt
chmod 644 notes.txt                         # owner rw, others read
chmod 755 lab/scripts                       # folder: owner full, others read/enter

echo 'echo "script works"' > lab/scripts/hello.sh
./lab/scripts/hello.sh                      # fails: permission denied
chmod +x lab/scripts/hello.sh
./lab/scripts/hello.sh                      # now it runs
```

### Users and sudo (Amazon Linux commands)
```bash
id                                          # your user and groups
sudo whoami                                 # prints root
tail -n 3 /etc/passwd                       # user list
sudo useradd testuser                       # create a user
sudo passwd testuser                        # set a password
sudo su - testuser                          # switch to it
whoami
exit                                        # back to ec2-user
ls -ld /home/testuser
sudo userdel -r testuser                    # delete user and home folder
```

**Exercise:** create `secret.txt`, set it to `600`, then run `sudo cat secret.txt`. Explain why sudo works regardless of permissions.

---

## Part 4: Processes, disk, memory (20 min)

```bash
ps aux | head                               # snapshot of processes
ps aux | grep sshd                          # filter
top                                         # live view, q to quit

sudo dnf install -y htop
htop                                        # nicer view, q to quit

sleep 300 &                                 # background process
jobs
ps aux | grep sleep
kill <PID>                                  # use the PID from ps
ps aux | grep sleep                         # gone

df -h                                       # disk space per filesystem
du -sh ~/devops-practice                    # folder size
sudo du -sh /var/log/* 2>/dev/null | sort -h | tail -n 5   # biggest log items
free -h                                     # memory
nproc                                       # CPU count
lscpu | head -n 15
```

**Exercise:** write down total RAM, free disk space on `/`, and CPU count. Compare with the instance type you chose in the console.

---

## Part 5: Services with systemctl (15 min)

```bash
sudo dnf install -y nginx
sudo systemctl status nginx                 # q to exit; nginx may be inactive at first
sudo systemctl start nginx
sudo systemctl status nginx                 # look for "active (running)"
sudo systemctl stop nginx
sudo systemctl start nginx
sudo systemctl restart nginx
sudo systemctl enable nginx                 # start at boot
systemctl is-enabled nginx
systemctl list-units --type=service --state=running | head -n 15
```

### Logs of a service
```bash
sudo journalctl -u nginx -n 20              # last 20 lines for nginx
sudo journalctl -u sshd -n 10
sudo ls /var/log/nginx
sudo tail -n 5 /var/log/nginx/access.log
```

**Exercise:** stop nginx, run `curl localhost` and watch it fail. Start nginx and run `curl localhost` again.

---

## Part 6: Text processing and logs (20 min)

Pipes (`|`) send one command's output into the next command. This is the most important skill in this part.

### Create a practice log
```bash
cd ~/devops-practice
cat > app.log << 'EOF'
2026-10-05 10:00:01 INFO  Server started
2026-10-05 10:00:05 ERROR Database connection failed
2026-10-05 10:01:10 INFO  User login
2026-10-05 10:02:20 ERROR Timeout on payment service
2026-10-05 10:03:30 WARN  High memory usage
2026-10-05 10:04:40 ERROR Database connection failed
EOF
```

### Practice
```bash
grep ERROR app.log                          # only error lines
grep -i error app.log                       # ignore case
grep -c ERROR app.log                       # count
grep -v INFO app.log                        # everything except INFO
grep -n "Database" app.log                  # with line numbers
grep ERROR app.log > errors.txt             # save to a file
awk '{print $3}' app.log | sort | uniq -c   # count of each log level
awk '{print $2, $4, $5}' app.log            # pick columns
sort app.log | uniq -c | sort -rn | head    # most repeated lines
cut -d' ' -f1 app.log | sort -u             # unique dates
```

### Live follow (needs two SSH windows)
```bash
# Window 1
tail -f ~/devops-practice/app.log

# Window 2
echo "$(date '+%F %T') ERROR Disk almost full" >> ~/devops-practice/app.log
```
Watch the new line appear in window 1, then press Ctrl+C.

### Real server logs
```bash
sudo journalctl -u sshd | grep -i "failed" | tail -n 5     # failed SSH attempts
sudo awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head
```

On Amazon Linux 2023, `/var/log/secure` may not exist because logs go to the journal. On Amazon Linux 2 you can use `sudo grep -i failed /var/log/secure | tail -n 5`.

**Exercise:** count how many times each error message appears in `app.log`.

---

## Part 7: Networking (25 min)

```bash
ip a                                        # interfaces and IPs (private IP like 172.31.x.x)
ip route                                    # routing table, default gateway
cat /etc/resolv.conf                        # DNS server
curl ifconfig.me                            # your PUBLIC IP; compare with the console
ping -c 4 8.8.8.8                           # connectivity
ping -c 4 google.com                        # connectivity plus DNS

sudo dnf install -y bind-utils traceroute
nslookup google.com
dig google.com +short
traceroute -n 8.8.8.8

curl -I https://example.com                 # HTTP headers
curl -s localhost | head                    # nginx page
ss -tulnp                                   # listening ports and owning processes
ss -tulnp | grep :80                        # nginx
ss -tulnp | grep :22                        # sshd
```

### Exercise: security group test
1. Run `ss -tulnp | grep :80` to confirm nginx is listening.
2. Open `http://<public-ip>` in your browser. If port 80 is allowed in the security group, you see the nginx page.
3. Remove the port 80 rule from the security group and refresh. The page hangs even though nginx is still running.
4. Add the rule back.

Write down in your own words why the page failed.

---

## Part 8: Packages and archives (10 min)

```bash
dnf list installed | wc -l
dnf search htop | head
sudo dnf install -y tree unzip zip
tree ~/devops-practice

tar -czf backup.tar.gz lab                  # create a compressed archive
ls -lh backup.tar.gz
mkdir restore && tar -xzf backup.tar.gz -C restore
tree restore
zip -r backup.zip lab
```

---

## Part 9: Final mini-lab (15 min)

Do these without looking at the notes:

1. Create `~/lab-final/` with folders `logs` and `scripts`.
2. Copy `app.log` into `logs`.
3. Save all ERROR lines to `logs/errors.txt` and show the count.
4. Create `scripts/check.sh` that prints the date, disk usage of `/`, and free memory. Make it executable and run it.
5. Show which process is listening on port 80 and its PID.
6. Write down your private IP, public IP and default gateway.
7. Create a compressed backup of `~/lab-final`.

Example for step 4:
```bash
cat > ~/lab-final/scripts/check.sh << 'EOF'
#!/bin/bash
echo "Date: $(date)"
echo "Disk usage:"
df -h /
echo "Memory:"
free -h
EOF
chmod +x ~/lab-final/scripts/check.sh
~/lab-final/scripts/check.sh
```

---

## Day 1 checklist

- [ ] SSH into EC2 from PowerShell
- [ ] Navigate, create, copy, move and delete files
- [ ] Read and change permissions (`chmod 600`, `644`, `755`, `+x`)
- [ ] Create a user and use `sudo`
- [ ] Use `ps`, `top`, `df`, `free`, `kill`
- [ ] Start, stop and enable a service with `systemctl`; read its `journalctl` logs
- [ ] Use `grep`, `awk`, `sort`, `uniq`, pipes and redirects
- [ ] Use `ip a`, `ss`, `curl`, `ping`, `dig`
- [ ] Opened and blocked port 80 via the security group and explained why
- [ ] Mini-lab done

## Amazon Linux vs Ubuntu quick reference

| Task | Ubuntu | Amazon Linux |
|---|---|---|
| Install a package | `sudo apt install -y <pkg>` | `sudo dnf install -y <pkg>` |
| DNS tools | `dnsutils` | `bind-utils` |
| Auth log | `/var/log/auth.log` | `journalctl -u sshd` (or `/var/log/secure` on AL2) |
| Add user | `sudo adduser <name>` | `sudo useradd <name>` |
| Delete user | `sudo deluser --remove-home <name>` | `sudo userdel -r <name>` |
| SSH username | `ubuntu` | `ec2-user` |

## Wrap up

- Write your own notes in `day1-notes.md`: commands that surprised you, errors you hit, and how you fixed them.
- **Stop the instance** in the console (Instance state, then Stop) so you only pay for the disk.
