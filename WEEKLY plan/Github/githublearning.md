# GitHub Learning Notes

My notes on Git and GitHub as part of my DevOps learning path.
Commands are written for **PowerShell on Windows**, run from the repo root (`C:\Users\ADMIN\Devops`).

## Table of Contents

1. [Day 2: Git in depth](#day-2-git-in-depth)
   - [Step 0: Check your setup](#step-0-check-your-setup)
   - [Step 1: Push a local folder to GitHub](#step-1-push-a-local-folder-to-github)
   - [Step 2: .gitignore](#step-2-gitignore)
   - [Step 3: Branches](#step-3-branches)
   - [Step 4: Pull requests](#step-4-pull-requests)
   - [Step 5: Merging locally](#step-5-merging-locally)
   - [Step 6: Merge conflicts](#step-6-merge-conflicts)
   - [Step 7: Verify](#step-7-verify-everything)
2. [Quick: push a new file or folder](#quick-push-a-new-file-or-folder)
3. [Command cheat sheet](#command-cheat-sheet)
4. [Common problems](#common-problems)
5. [Warnings and messages explained](#warnings-and-messages-explained)
6. [Checklist](#day-2-checklist)

---

# Day 2: Git in depth

**Goal:** push the local `devops` folder to a GitHub repo called `devops`, then create and merge a branch.
**Topics:** branches, merge, pull requests, `.gitignore`.

## Step 0: Check your setup

```powershell
git --version
git config --global user.name
git config --global user.email
```

All three should print something. If name or email is blank:

```powershell
git config --global user.name "Your Name"
git config --global user.email "your-github-email@example.com"
```

Use the same email as your GitHub account so commits link to your profile.

## Step 1: Push a local folder to GitHub

### 1.1 Create the remote repo

1. On github.com click **+** (top right), then **New repository**.
2. Repository name: `devops`.
3. Choose Public or Private.
4. Leave **Add a README**, **.gitignore** and **license** unchecked. A non-empty remote causes push conflicts with existing local content.
5. Click **Create repository** and copy the HTTPS URL.

### 1.2 Check the local folder

```powershell
cd C:\Users\ADMIN\Devops
git status
git remote -v
```

- `fatal: not a git repository` means run `git init`.
- Empty `git remote -v` output means no remote is connected yet.
- If it points to the wrong repo: `git remote set-url origin <new-url>`.

### 1.3 Connect and push

```powershell
git branch -M main
git remote add origin https://github.com/<your-username>/devops.git
git add .
git commit -m "Initial commit: devops folder"
git push -u origin main
```

| Command | What it does |
|---|---|
| `git branch -M main` | Renames the current branch to `main` |
| `git remote add origin <url>` | Gives the GitHub URL the nickname `origin` |
| `git add .` | Stages everything in the folder |
| `git commit -m "..."` | Saves a snapshot locally |
| `git push -u origin main` | Uploads it; `-u` links local `main` to `origin/main`, so later `git push` is enough |

### 1.4 Verify

Refresh the GitHub page. Your files and folders should appear.

---

## Step 2: .gitignore

`.gitignore` tells Git which files to never track: secrets, logs, temp files.

### 2.1 Create it

```powershell
notepad .gitignore
```

Example contents:

```
# Secrets and keys
*.pem
*.key
.env

# Logs and temp files
*.log
*.tmp

# OS / editor files
Thumbs.db
.vscode/

# Terraform
.terraform/
*.tfstate
*.tfstate.backup
```

This matters for AWS and Terraform work: `.pem` key files and `.tfstate` files can contain secrets that must never reach GitHub.

### 2.2 Test it

```powershell
echo "test" > debug.log
git status
```

`debug.log` should **not** be listed. Clean up with `del debug.log`.

### 2.3 Commit and push

```powershell
git add .gitignore
git commit -m "Add .gitignore"
git push
```

### 2.4 If a file was already committed

`.gitignore` cannot hide files that are already tracked. Untrack them:

```powershell
git rm --cached secret.pem
git commit -m "Stop tracking secret.pem"
git push
```

`--cached` removes it from Git but keeps it on disk.
If a real secret was ever pushed, treat it as leaked and **rotate it**, because it stays in the history.

---

## Step 3: Branches

A branch is an independent line of work, so you can experiment without touching `main`.

### 3.1 Create and switch

```powershell
git switch -c feature/day2-git-notes
git branch
```

The `*` marks the current branch:

```
* feature/day2-git-notes
  main
```

`git switch -c` is the modern form of `git checkout -b`.

### 3.2 Make changes

```powershell
notepad "WEEKLY plan\day2-git-notes.md"
git status
git add "WEEKLY plan/day2-git-notes.md"
git commit -m "Add day2 git notes"
```

Make a second small commit (edit, add, commit). Two commits make the history more interesting later.

### 3.3 See that branches are isolated

```powershell
git switch main
dir "WEEKLY plan"
```

The new file is gone because it only exists on the feature branch.

```powershell
git switch feature/day2-git-notes
dir "WEEKLY plan"
```

The file is back.

### 3.4 Push the branch

```powershell
git push -u origin feature/day2-git-notes
```

GitHub now has two branches (see the branch dropdown on the repo page).

---

## Step 4: Pull requests

### 4.1 Open the PR

1. On the repo page click the yellow **Compare & pull request** banner (or **Pull requests** tab, then **New pull request**).
2. Set **base: main** and **compare: feature/day2-git-notes**.
3. Add a title (`Add day 2 git notes`) and a short description.
4. Click **Create pull request**.

### 4.2 Review it

1. Open the **Files changed** tab. Green lines are additions, red lines are deletions.
2. Hover over a line, click the blue **+**, and add a comment. This is how teammates review code.
3. On the **Conversation** tab, check for "This branch has no conflicts".

### 4.3 Merge

1. Click **Merge pull request**, then **Confirm merge**.
2. Click **Delete branch**.

Merge types (dropdown next to the button):

| Type | Result |
|---|---|
| **Merge commit** | Keeps all commits and adds a merge commit |
| **Squash and merge** | Combines all commits into one |
| **Rebase and merge** | Replays commits onto `main` without a merge commit |

### 4.4 Sync your local copy

```powershell
git switch main
git pull
git branch -d feature/day2-git-notes
git fetch --prune
```

- `git pull` brings the merged result into local `main`.
- `git branch -d` deletes the local branch (it refuses if not merged, a safety check).
- `git fetch --prune` clears stale references to branches deleted on GitHub.

---

## Step 5: Merging locally

Merging without a PR:

```powershell
git switch -c feature/local-merge-demo
notepad "WEEKLY plan\merge-demo.md"
git add .
git commit -m "Add merge demo file"
git switch main
git merge feature/local-merge-demo
git push
git branch -d feature/local-merge-demo
```

Since `main` did not change meanwhile, the output says **Fast-forward** (Git just moves the pointer).

To see a real **merge commit**:

1. Make a commit on `main`.
2. Make a different commit on the feature branch.
3. Merge. Git opens an editor for the merge message; save and close it.

---

## Step 6: Merge conflicts

A conflict happens when two branches change the same lines differently. Git cannot pick a winner, so you decide.

### 6.1 Base file

```powershell
git switch main
echo "Line 1: original" > conflict-test.md
git add conflict-test.md
git commit -m "Add conflict-test file"
```

### 6.2 Change it on a branch

```powershell
git switch -c feature/conflict
echo "Line 1: changed on branch" > conflict-test.md
git add .
git commit -m "Change line 1 on branch"
```

### 6.3 Change the same line on main

```powershell
git switch main
echo "Line 1: changed on main" > conflict-test.md
git add .
git commit -m "Change line 1 on main"
```

### 6.4 Trigger the conflict

```powershell
git merge feature/conflict
```

```
CONFLICT (content): Merge conflict in conflict-test.md
Automatic merge failed; fix conflicts and then commit the result.
```

`git status` shows `both modified: conflict-test.md`.

### 6.5 Resolve it

```powershell
notepad conflict-test.md
```

```
<<<<<<< HEAD
Line 1: changed on main
=======
Line 1: changed on branch
>>>>>>> feature/conflict
```

- Above `=======` is the current branch (`main`).
- Below it is the incoming branch.

Edit to the final text you want and **delete all three marker lines**. Save.

### 6.6 Finish the merge

```powershell
git add conflict-test.md
git commit -m "Resolve merge conflict in conflict-test.md"
git push
git branch -d feature/conflict
```

Stuck mid-conflict? `git merge --abort` returns to the state before the merge.
VS Code also shows **Accept Current / Accept Incoming / Accept Both** buttons.

---

## Step 7: Verify everything

```powershell
git log --oneline --graph --all
```

You should see branches splitting off and merging back. On GitHub check:

- **Commits** shows the history.
- **Pull requests > Closed** shows the merged PR.
- `.gitignore` is in the file list.

---

# Quick: push a new file or folder

```powershell
git status
git add "path/to/file-or-folder"
git commit -m "Describe the change"
git push origin main
```

- Paths with spaces need double quotes, e.g. `"WEEKLY plan/day1-linux-practice.md"`.
- Git does not track **empty folders**. Add a placeholder: `touch folder/.gitkeep` (Git Bash) or create any file inside.
- `git add .` stages all changes in the repo.
- If `main` errors, run `git branch` to check the name (it may be `master`).
- Tip: avoid spaces and special characters (like a stray `'`) in folder names. Prefer names like `weekly-plan/linux`.

---

# Command cheat sheet

| Command | Purpose |
|---|---|
| `git status` | Show changed, staged and untracked files |
| `git add <path>` | Stage changes |
| `git commit -m "msg"` | Save staged changes locally |
| `git push` / `git push -u origin <branch>` | Upload commits |
| `git pull` | Fetch and merge remote changes |
| `git fetch` | Download remote changes without merging |
| `git branch` / `git branch -a` | List local / all branches |
| `git switch <branch>` | Move to a branch |
| `git switch -c <branch>` | Create and move to a branch |
| `git merge <branch>` | Merge a branch into the current one |
| `git merge --abort` | Cancel a conflicted merge |
| `git branch -d <branch>` | Delete a merged local branch |
| `git diff` | See unstaged changes |
| `git log --oneline --graph --all` | Visualize history |
| `git rm --cached <file>` | Stop tracking a file but keep it on disk |
| `git remote -v` | Show connected remotes |

---

# Common problems

| Problem | Fix |
|---|---|
| `remote origin already exists` | `git remote set-url origin <url>` |
| `Updates were rejected` / `failed to push some refs` | `git pull --rebase origin main`, then push again |
| Login prompt rejects your password | Use a Personal Access Token or sign in via the browser prompt (passwords are no longer accepted for HTTPS pushes) |
| Committed to the wrong branch | `git log` to find the commit, `git switch correct-branch`, then `git cherry-pick <commit-id>` |
| `git branch -d` says not fully merged | Merge it first, or use `-D` only if you want to discard it |
| `git status` shows nothing for a new folder | The folder is empty; add a file or `.gitkeep` |

---

# Warnings and messages explained

**`warning: LF will be replaced by CRLF the next time Git touches it`**
Harmless. Windows uses CRLF line endings, Git stores LF internally, and Git converts automatically. To silence it:

```powershell
git config --global core.autocrlf true
```

---

# Day 2 checklist

- [ ] `devops` repo on GitHub contains my local folder
- [ ] `.gitignore` added, tested with `debug.log`, and pushed
- [ ] Branch created, 2 commits made, pushed
- [ ] PR created, reviewed in **Files changed**, merged, branch deleted
- [ ] Local `main` pulled; local feature branch deleted
- [ ] Local fast-forward merge done
- [ ] Conflict created, resolved, and committed
- [ ] `git log --oneline --graph --all` checked
