# Developer Quickstart & Visual Setup Guide

> [!NOTE]
> **⚡ Quick Check:**
> - **What is it?** A portable governance and context overlay (`.agent/`) that gives GitHub Copilot, Cursor, Codex, and Claude verified project context, secret handling boundaries, and staged test discipline without modifying your application source code.
> - **Install (AI):** Paste the Prompt from Section 2 into Copilot / Cursor Composer.
> - **Install (CLI):** Run the 2-step command in Section 3 (`pwsh -File install.ps1 ...`).
> - **Update (AI/CLI):** Run `update-target.ps1` (Section 6) to refresh skills without losing project-local memory.
> - **Uninstall (AI/CLI):** Run `uninstall.ps1 -Scope managed-only` (Section 7) for residue-free removal with deletion receipt.

---

## 1. The 30-Second Mental Model

`lizard-agent-layer` installs verified project context and safety protocols for your approved AI coding assistant:

```text
┌─────────────────────────────────────────────────────────────┐
│                 YOUR EXISTING PROJECT                       │
│    (src/, package.json, tests/ - 100% untouched!)           │
│    (Java / Spring, .NET, Python, Node, React / Angular)     │
└──────────────────────────────┬──────────────────────────────┘
                               │
             + 1 Command or Copy-Paste Prompt
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                 + LIZARD AGENT LAYER                        │
│                                                             │
│  📁 .agent/protocols/  --> "Never leak secrets, test first" │
│  📁 .agent/USING.md    --> "Human operator guide for team"  │
│  📁 .agent/memory/     --> "Architecture decisions & rules" │
│  📁 .github / .cursor  --> "Instruct Copilot / Cursor"      │
└─────────────────────────────────────────────────────────────┘
                               │
                               ▼
         🚀 Result: Grounded, Verified, Safe Code Changes
```

---

## 2. Install via AI Prompt (Easiest Method)

Simply open **GitHub Copilot Chat**, **Cursor Composer**, **Claude Code**, or your IDE chat in your repository and paste this prompt:

### 📋 Copy-Paste Installation & Migration Prompt:
```text
You are an expert software engineer. Please install and configure lizard-agent-layer for this repository:

1. Reference the official repository: https://github.com/sacrificeking/lizard-agent-layer
   (Clone it to a temporary directory or check if already available locally).
2. Read `INSTALL.md` in lizard-agent-layer to understand the safety and migration protocols.
3. Inspect this target repository:
   - Check if an existing agent setup is present (e.g., `.cursorrules`, `.cursor/rules/`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md`, etc.).
   - If an existing setup is found: Extract all project-specific rules and architecture decisions into `.agent/memory/` (DECISIONS.md, LESSONS.md) and preserve existing project instructions non-destructively through sidecars.
   - Recommend the best profile (standard, minimal, or enterprise-fullstack) and approved IDE harness (e.g. github-copilot, cursor, or codex).
4. Run a safe preview first using `scripts/install.ps1 -TargetPath "<this-repo-path>" -Profile <profile> -Harnesses <harness> -WritePlan -PlanPath "$HOME/.lizard-agent-layer/.tmp/install-plan.md" -CanonicalPlanPath "$HOME/.lizard-agent-layer/.tmp/install-plan.json"`.
5. Show me the Plan Approval Card and ask for my explicit confirmation (`APPROVE PLAN <plan_id>`) before applying.
```

---

## 3. Install via Terminal Commands (Fastest Method)

Run these commands in PowerShell from your repository root (replace `github-copilot` with `cursor`, `codex`, or your org-approved harness):

### For Standard Development:
```powershell
if (-not (Test-Path "$HOME/.lizard-agent-layer")) { git clone https://github.com/sacrificeking/lizard-agent-layer.git "$HOME/.lizard-agent-layer" } else { git -C "$HOME/.lizard-agent-layer" pull --quiet }

# 1. Generate canonical installation plan (dry-run preview)
pwsh -File "$HOME/.lizard-agent-layer/scripts/install.ps1" -TargetPath "." -Profile standard -Harnesses github-copilot -WritePlan -PlanPath "$HOME/.lizard-agent-layer/.tmp/install-plan.md" -CanonicalPlanPath "$HOME/.lizard-agent-layer/.tmp/install-plan.json"

# 2. Review Plan Approval Card, then apply (summary mode default):
pwsh -File "$HOME/.lizard-agent-layer/scripts/install.ps1" -TargetPath "." -Profile standard -Harnesses github-copilot -Apply -ApprovedPlanPath "$HOME/.lizard-agent-layer/.tmp/install-plan.json" -HumanApproved
```

### For Enterprise Full-Stack (Database / API / Frontend / Security):
```powershell
if (-not (Test-Path "$HOME/.lizard-agent-layer")) { git clone https://github.com/sacrificeking/lizard-agent-layer.git "$HOME/.lizard-agent-layer" } else { git -C "$HOME/.lizard-agent-layer" pull --quiet }

# 1. Generate canonical installation plan (dry-run preview)
pwsh -File "$HOME/.lizard-agent-layer/scripts/install.ps1" -TargetPath "." -Profile enterprise-fullstack -Harnesses github-copilot -Packs frontend-engineering,database-backend,backend-api,security-hardening -WritePlan -PlanPath "$HOME/.lizard-agent-layer/.tmp/install-plan.md" -CanonicalPlanPath "$HOME/.lizard-agent-layer/.tmp/install-plan.json"
```
> **Note:** By default, all profiles use summary mode approval (or opt-in `-PlanApprovalMode digest`). If your organization requires cryptographic signed approval, use `scripts/new-approval.ps1` to mint approval materials. On Windows without PowerShell 7 (`pwsh`), you can run `scripts\lizard.cmd` or `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ...`.

---

## 4. What Happens to Your Project? (Before vs. After)

### Before:
```text
MyProject/
├── src/
├── package.json
└── README.md
```

### After Installation:
```text
MyProject/
├── src/                          (Your application code remains 100% untouched)
├── package.json
├── README.md
│
├── .agent/                       <-- The Agent Brain & Governance
│   ├── USING.md                  (Human operator card for team members)
│   ├── memory/                   (Remembers architecture decisions & lessons)
│   ├── protocols/                (Rules: Staged Execution, Secret Handling, Git Safety)
│   ├── skills/                   (Specialized engineering workflows)
│   └── routing/                  (Audit receipts and policy controls)
│
├── .cursor/rules/                <-- Configured for Cursor IDE (if selected)
│   └── lizard-agent-layer.mdc
└── .github/                      <-- Configured for GitHub Copilot (if selected)
    └── copilot-instructions.md
```

---

## 5. Daily Developer Workflow

You do not need to change how you program. Open Cursor or VS Code and chat with your AI assistant as normal. Refer to `.agent/USING.md` in your repository for operator guidelines.

| Scenario | ❌ Without Agent Layer | ✅ With Lizard Agent Layer |
| :--- | :--- | :--- |
| **New Feature Request** | AI rushes to write 400 lines of spaghetti code, breaking existing utils. | AI creates a clear 3-step plan first, verifies types, and asks for approval before modifying code. |
| **API Keys & Secrets** | AI might accidentally hardcode test tokens into `.env` or client files. | AI strictly follows `secret-handling.md`, refusing to put secrets in frontend code. |
| **Bug Fixing** | AI guesses solutions and forgets what worked yesterday. | AI consults `.agent/memory/` to check past architecture decisions and lessons. |
| **Database Changes** | AI risks running destructive SQL (`DROP TABLE`). | AI enforces `database-engineering` rules with reversible migrations and rollback scripts. |
| **Testing** | AI writes code and stops without running tests. | AI executes tests and proves verification evidence before declaring a task complete. |

---

## 6. How to Update the Layer (When New Versions Release)

Updating preserves all your local memory, decisions, and custom code while updating underlying skills and security protocols.

### 📋 Option A: Copy-Paste Update Prompt for AI Assistant:
```text
You are an expert software engineer. Please safely update lizard-agent-layer for this repository:

1. Reference the official repository: https://github.com/sacrificeking/lizard-agent-layer
   (Pull latest changes to local cache or clone to temporary directory).
2. Read `docs/update-target.md` in lizard-agent-layer.
3. Run a preview update first: `scripts/update-target.ps1 -TargetPath "<this-repo-path>" -OutputDir "$HOME/.lizard-agent-layer/.tmp/update-plan"`.
4. Present the update summary to me and verify that my local memory and project code are 100% preserved.
5. Ask for my confirmation, then apply the approved update plan with `-Apply -ApprovedPlanPath "$HOME/.lizard-agent-layer/.tmp/update-plan/update-plan.json" -ApprovedPlanSha256 <sha256> -HumanApproved`.
```

### 💻 Option B: Terminal Commands for Updates:
```powershell
if (Test-Path "$HOME/.lizard-agent-layer") { git -C "$HOME/.lizard-agent-layer" pull --quiet }
# 1. Preview update
pwsh -File "$HOME/.lizard-agent-layer/scripts/update-target.ps1" -TargetPath "." -OutputDir "$HOME/.lizard-agent-layer/.tmp/update-plan"

# 2. Apply approved update
$updateSha = (Get-FileHash "$HOME/.lizard-agent-layer/.tmp/update-plan/update-plan.json" -Algorithm SHA256).Hash.ToLowerInvariant()
pwsh -File "$HOME/.lizard-agent-layer/scripts/update-target.ps1" -TargetPath "." -OutputDir "$HOME/.lizard-agent-layer/.tmp/update-plan" -Apply -ApprovedPlanPath "$HOME/.lizard-agent-layer/.tmp/update-plan/update-plan.json" -ApprovedPlanSha256 $updateSha -HumanApproved
```

---

## 7. How to Completely Uninstall (100% Residue-Free)

If you ever wish to remove the agent layer, the uninstaller will cleanly remove only layer-owned files, leave your project code 100% intact, and generate a verifiable deletion receipt.

### 📋 Option A: Copy-Paste Uninstall Prompt for AI Assistant:
```text
You are an expert software engineer. Please safely uninstall lizard-agent-layer from this repository:

1. Reference `UNINSTALL.md` in lizard-agent-layer: https://github.com/sacrificeking/lizard-agent-layer
2. Run a preview uninstall plan first: `scripts/uninstall.ps1 -TargetPath "<this-repo-path>" -Scope managed-only -CanonicalPlanPath "$HOME/.lizard-agent-layer/.tmp/uninstall-plan.json"`.
3. Confirm to me that only layer-owned files will be removed and no application source files will be touched.
4. Ask for my explicit confirmation, then apply the verified deletion with `-Apply -ApprovedPlanPath "$HOME/.lizard-agent-layer/.tmp/uninstall-plan.json" -ApprovedPlanSha256 <sha256> -HumanApproved`.
5. Present the external deletion receipt (`uninstall-receipt.json`) as cryptographic proof.
```

### 💻 Option B: Terminal Commands for Clean Uninstall:
```powershell
# 1. Preview uninstall plan (safe, dry-run)
pwsh -File "$HOME/.lizard-agent-layer/scripts/uninstall.ps1" -TargetPath "." -Scope managed-only -CanonicalPlanPath "$HOME/.lizard-agent-layer/.tmp/uninstall-plan.json"

# 2. Apply verified uninstall
$uninstallSha = (Get-FileHash "$HOME/.lizard-agent-layer/.tmp/uninstall-plan.json" -Algorithm SHA256).Hash.ToLowerInvariant()
pwsh -File "$HOME/.lizard-agent-layer/scripts/uninstall.ps1" -TargetPath "." -Scope managed-only -Apply -ApprovedPlanPath "$HOME/.lizard-agent-layer/.tmp/uninstall-plan.json" -ApprovedPlanSha256 $uninstallSha -HumanApproved
```

---

## 8. Diagnostic Health Checks

To verify that your project's agent configuration is healthy and fully compliant:

```powershell
pwsh -File "$HOME/.lizard-agent-layer/scripts/doctor.ps1" -TargetPath "." -Strict
```

