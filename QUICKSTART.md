# Developer Quickstart & Visual Setup Guide

> **Goal:** Upgrade your existing project with enterprise-grade AI coding discipline, security protocols, and long-term memory in **under 2 minutes**—with zero AI or prompt-engineering knowledge required.

---

## 1. The 30-Second Mental Model

Think of `lizard-agent-layer` as a **standardized operating system for your AI coding assistant**:

```text
┌─────────────────────────────────────────────────────────────┐
│                 YOUR EXISTING PROJECT                       │
│    (src/, package.json, tests/ - 100% untouched!)           │
└──────────────────────────────┬──────────────────────────────┘
                               │
            + 1 Command or Copy-Paste Prompt
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                 + LIZARD AGENT LAYER                        │
│                                                             │
│  📁 .agent/protocols/  --> "Never leak secrets, test first" │
│  📁 .agent/memory/     --> "Remember past design decisions" │
│  📁 .cursor / .github  --> "Tell Cursor / Copilot to obey"  │
└─────────────────────────────────────────────────────────────┘
                               │
                               ▼
       🚀 Result: High-Quality, Predictable, Safe Code
```

---

## 2. Option A: The Copy-Paste AI Prompt (Easiest)

You don't even need to type terminal commands. Simply open **GitHub Copilot Chat**, **Cursor Composer**, **Claude Code**, or your IDE chat, and paste this prompt:

### 📋 Copy-Paste Prompt for Your AI Assistant:

```text
You are an expert software engineer. Please install and configure lizard-agent-layer for this repository:

1. Reference the official repository: https://github.com/sacrificeking/lizard-agent-layer
   (Clone it to a temporary directory or check if already available locally).
2. Read `INSTALL.md` in lizard-agent-layer to understand the safety protocols.
3. Inspect my current repository structure and recommend the best profile (e.g., standard, minimal, or supabase-react-finance) and IDE harnesses (e.g., cursor, github-copilot, codex, claude-code).
4. Run a safe preview first using `scripts/install.ps1 -TargetPath "<this-repo-path>" -Profile <profile> -Harnesses <harnesses>`.
5. Show me the planned changes and ask for my confirmation before applying.
```

The AI will inspect your project, present a clear summary of what it will install, and ask for your "OK" before writing any files.

---

## 3. Option B: The 10-Second Terminal 1-Liner (Fastest)

If you prefer running directly from PowerShell in your project folder, run this single command (it automatically fetches the latest version from GitHub):

### For Cursor & VS Code (Copilot / Codex):
```powershell
if (-not (Test-Path "$HOME/.lizard-agent-layer")) { git clone https://github.com/sacrificeking/lizard-agent-layer.git "$HOME/.lizard-agent-layer" } else { git -C "$HOME/.lizard-agent-layer" pull --quiet }
pwsh -File "$HOME/.lizard-agent-layer/scripts/install.ps1" -TargetPath "." -Profile standard -Harnesses cursor,github-copilot,codex -Apply -HumanApproved
```

### For Full-Stack React / Supabase / Finance Apps:
```powershell
if (-not (Test-Path "$HOME/.lizard-agent-layer")) { git clone https://github.com/sacrificeking/lizard-agent-layer.git "$HOME/.lizard-agent-layer" } else { git -C "$HOME/.lizard-agent-layer" pull --quiet }
pwsh -File "$HOME/.lizard-agent-layer/scripts/install.ps1" -TargetPath "." -Profile supabase-react-finance -Harnesses cursor,claude-code,gemini -Packs frontend-product,supabase-react,security-hardening -Apply -HumanApproved
```

*(Tip: To preview first without making changes, omit `-Apply -HumanApproved`).*

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
├── src/                          (Your code remains 100% untouched)
├── package.json
├── README.md
│
├── .agent/                       <-- The Agent Brain & Governance
│   ├── memory/                   (Remembers architecture decisions & lessons)
│   ├── protocols/                (Rules: Staged Execution, Secret Handling, Git Safety)
│   └── skills/                   (Specialized engineering workflows)
│
├── .cursor/rules/                <-- Configured for Cursor IDE (if selected)
│   └── lizard-agent-layer.mdc
└── .github/                      <-- Configured for GitHub Copilot (if selected)
    └── copilot-instructions.md
```

---

## 5. How You Work With It Daily

**You don't need to learn any new tools or commands.** Open your project in Cursor, VS Code, or your favorite editor, and chat with your AI as usual.

### The Concrete Difference in Daily Coding:

| Scenario | ❌ Without Agent Layer | ✅ With Lizard Agent Layer |
| :--- | :--- | :--- |
| **New Feature Request** | AI rushes to write 400 lines of spaghetti code, breaking existing utils. | AI creates a clear 3-step plan first, verifies types, and asks for approval before modifying code. |
| **API Keys & Secrets** | AI might accidentally hardcode test tokens into `.env` or client files. | AI strictly follows `secret-handling.md`, refusing to put secrets in frontend code. |
| **Bug Fixing** | AI guesses solutions and forgets what worked yesterday. | AI consults `.agent/memory/` to check past architecture decisions and lessons. |
| **Testing** | AI writes code and stops without running tests. | AI executes tests and proves verification evidence before declaring a task complete. |

---

## 6. Maintenance & Health Checks

Keep your project in top shape with these simple commands:

| Action | Command | Purpose |
| :--- | :--- | :--- |
| **Health Check** | `pwsh -File .\scripts\doctor.ps1 -TargetPath "C:\YourProject" -Strict` | Checks that all rules, manifests, and memory files are healthy. |
| **Update Layer** | `pwsh -File .\scripts\update-target.ps1 -TargetPath "C:\YourProject" -Apply -HumanApproved` | Safely updates rules when a new layer version is released. |
| **Clean Uninstall** | `pwsh -File .\scripts\uninstall.ps1 -TargetPath "C:\YourProject" -Mode complete -Apply -HumanApproved` | Removes the `.agent` layer completely without touching your code. |
