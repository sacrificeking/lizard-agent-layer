# Visual Architecture & Systems Blueprint

> **lizard-agent-layer** is a vendor-neutral, portable governance and execution infrastructure for AI coding agents. It overlays standard development environments with strict security, deterministic workflows, long-term memory, and cryptographic verification.

---

## 1. High-Level System Topology

The system maintains a strict boundary between the **Reusable Source Layer** and the **Target Projects**:

```mermaid
flowchart TB
    subgraph SOURCE["lizard-agent-layer (Source Framework)"]
        PROFILES["Profiles\n(minimal, standard, supabase-react-finance)"]
        PACKS["Packs\n(frontend, security, supabase, loops, etc.)"]
        SKILLS["Skills & Contracts\n(21 Versioned Packages)"]
        PROTOCOLS["Protocols\n(Permissions, Secret Handling, Release Gates)"]
        ADAPTERS["Harness Adapters\n(Cursor, Copilot, Claude, Gemini, Codex)"]
        SAFEFS_CORE["SafeFS & Trust Engine\n(Handle-bound I/O, Cryptographic Envelopes)"]
    end

    subgraph INSTALLER["Transactional Install & Update Engine"]
        ANALYZER["Target Analyzer\n(Read-only inspection)"]
        PLANNER["Canonical Plan Generator\n(JSON + SHA-256 binding)"]
        TX_ENGINE["Write-Ahead Transaction Engine\n(Locks, Journals, Rollback)"]
    end

    subgraph TARGET["Target Project (Your Repository)"]
        subgraph AGENT_CORE[".agent/ Core"]
            PROFILE_CFG["project-profile.json"]
            MEM[".agent/memory/\n(Preferences, Decisions, Lessons)"]
            PROT[".agent/protocols/\n(Security, Governance Rules)"]
            SKL[".agent/skills/\n(Installed Packages & Manifest)"]
            ROUTING[".agent/routing/\n(Policies & Audit Receipts)"]
        end

        subgraph HARNESS_WIRING["IDE Harness Files (Translated Guidance)"]
            CURSOR[".cursor/rules/lizard-agent-layer.mdc"]
            COPILOT[".github/copilot-instructions.md"]
            CLAUDE["CLAUDE.md"]
            GEMINI["GEMINI.md"]
            CODEX["AGENTS.md"]
        end

        APP_CODE["Application Source Code\n(src/, tests/, package.json - 100% Preserved)"]
    end

    SOURCE --> INSTALLER
    INSTALLER -->|Deterministic Projection| TARGET
    AGENT_CORE -.->|Feeds Context To| HARNESS_WIRING
    HARNESS_WIRING -->|Guides AI Assistance Over| APP_CODE

    classDef sourceStyle fill:#1e293b,stroke:#38bdf8,stroke-width:2px,color:#f8fafc;
    classDef installerStyle fill:#334155,stroke:#f59e0b,stroke-width:2px,color:#f8fafc;
    classDef targetStyle fill:#0f172a,stroke:#10b981,stroke-width:2px,color:#f8fafc;
    class SOURCE sourceStyle;
    class INSTALLER installerStyle;
    class TARGET targetStyle;
```

---

## 2. The 4 Security & Governance Pillars

```mermaid
graph LR
    subgraph P1["1. Handle-Bound SafeFS"]
        A1["Windows: NtCreateFile\nUnix: openat/renameat"]
        A2["Descriptor-relative operations"]
        A3["Prevents Symlink/Junction swaps & Race Conditions"]
        A1 --> A2 --> A3
    end

    subgraph P2["2. Zero-Trust Signatures"]
        B1["Asymmetric Keys (RS256 / Ed25519)"]
        B2["Challenge Nonce & Replay Protection"]
        B3["Implementer vs. Verifier Role Separation"]
        B1 --> B2 --> B3
    end

    subgraph P3["3. Transactional Engine"]
        C1["Write-Ahead Journals (.tmp/tx-*)"]
        C2["Target-Level Process Locking"]
        C3["Automatic Rollback on Interruption"]
        C1 --> C2 --> C3
    end

    subgraph P4["4. Records & Retention"]
        D1["3 Memory Modes: curated / episodic / off"]
        D2["Cryptographic Legal Holds"]
        D3["Verifiable Deletion Receipts (ADR-0023)"]
        D1 --> D2 --> D3
    end

    classDef pillar fill:#1e1e2e,stroke:#cba6f7,stroke-width:2px,color:#cdd6f4;
    class P1,P2,P3,P4 pillar;
```

---

## 3. Staged Execution & Anti-Hallucination Pipeline

Every AI interaction in a project configured with `lizard-agent-layer` follows the **10-80-10 Staged Execution Pipeline** to prevent impulsive or unsafe code changes:

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Developer / User
    participant AI as AI Coding Agent (Cursor / Copilot / Claude)
    participant Core as .agent/ Governance Core
    participant Guard as Secret & Path Guard
    participant Verifier as Constrained Verifier
    participant Memory as .agent/memory/

    Dev->>AI: "Implement feature / Fix bug"
    AI->>Core: Read project-profile, protocols & skills
    AI->>Memory: Consult DECISIONS.md & LESSONS.md
    
    rect rgb(30, 41, 59)
        note over AI,Guard: STAGE 1: Clarify & Plan (10% Token Budget)
        AI->>AI: Analyze existing architecture & types
        AI->>Dev: Propose structured, reviewable plan
    end
    
    Dev-->>AI: Plan Approved
    
    rect rgb(15, 23, 42)
        note over AI,Guard: STAGE 2: Execute with Constraints (80% Token Budget)
        AI->>Guard: Validate file paths & secret boundaries
        Guard-->>AI: Access authorized (Handle-bound SafeFS)
        AI->>AI: Make modular code edits
    end

    rect rgb(30, 41, 59)
        note over AI,Verifier: STAGE 3: Independent Verification (10% Token Budget)
        AI->>Verifier: Run test suites & linter
        Verifier-->>AI: Verification Evidence (PASS / FAIL)
        AI->>Memory: Record new lessons / decisions (if applicable)
        AI->>Dev: Present verified results with proof
    end
```

---

## 4. Multi-Harness Adapter & Non-Clobbering Sidecar Architecture

When `lizard-agent-layer` is installed in a repository with existing configuration files, it **never overwrites** developer files without explicit force. It deploys sidecars and merge guidance:

```mermaid
flowchart TD
    INSTALL[Installer evaluates target directory]
    
    CHECK_EXISTS{Target file exists?}
    INSTALL --> CHECK_EXISTS

    CHECK_EXISTS -->|No| WRITE_NATIVE[Write primary harness file\ne.g., .github/copilot-instructions.md]
    CHECK_EXISTS -->|Yes| CHECK_OWNERSHIP{Layer-Owned & Unmodified?}
    
    CHECK_OWNERSHIP -->|Yes| REFRESH[Deterministically Refresh Metadata]
    CHECK_OWNERSHIP -->|No| WRITE_SIDECAR[Create isolated sidecar\ne.g., .github/copilot-instructions.lizard-agent-layer.md]
    
    WRITE_SIDECAR --> GEN_MERGE[Generate metadata-only merge suggestion\nscripts/merge-suggestions.ps1]
    GEN_MERGE --> HUMAN_DECIDE[Human reviews and decides merge]

    classDef safe fill:#064e3b,stroke:#34d399,stroke-width:2px,color:#ecfdf5;
    classDef warn fill:#78350f,stroke:#fbbf24,stroke-width:2px,color:#fffbeb;
    class WRITE_NATIVE,REFRESH safe;
    class WRITE_SIDECAR,GEN_MERGE,HUMAN_DECIDE warn;
```

---

## 5. Lifecycle State Machine: Install, Update & Uninstall

```mermaid
stateDiagram-v2
    [*] --> Unmanaged: Target Repository

    state "Preview Mode (Safe Inspection)" as Preview {
        Unmanaged --> PlanGenerated: analyze-target.ps1\ninstall.ps1 -WritePlan
        PlanGenerated --> PlanApproved: Human reviews JSON & SHA-256
    }

    state "Active Management" as Active {
        PlanApproved --> Installed: install.ps1 -Apply -HumanApproved
        Installed --> Healthy: doctor.ps1 -Strict (PASS)
        Healthy --> Updating: update-target.ps1 -WritePlan
        Updating --> Healthy: update-target.ps1 -Apply
    }

    state "Decommissioning" as Decom {
        Healthy --> UninstallPlan: uninstall.ps1 -WritePlan
        UninstallPlan --> ExportArchive: Mode: export-then-complete
        ExportArchive --> Removed: uninstall.ps1 -Apply
        UninstallPlan --> Removed: Mode: complete / managed-only
    }

    Removed --> Unmanaged: Deletion Receipt Generated (0 Residue)
```

---

## 6. Directory Structure & File Map Reference

```text
lizard-agent-layer/
├── adapters/                  # Harness shims (Cursor, Copilot, Claude, Gemini, Codex)
├── changes/                   # Versioned change records linking ADRs to path impacts
├── docs/
│   ├── adr/                   # 23 Architecture Decision Records (ADR-0001 to ADR-0023)
│   ├── audits/                # Static security audits & remediation ledgers
│   ├── getting-started.md     # Comprehensive 6-section operations guide
│   └── visual-architecture.md # This visual architecture document
├── packages/ / packs/         # Reusable feature packs (frontend, supabase, security, etc.)
├── profiles/                  # Pre-configured project shapes (minimal, standard, finance)
├── protocols/                 # Shared governance rules (secrets, release gates, handoff)
├── registry/                  # Contracts, quality rubrics, and drift baselines
├── retention-policies/        # Records retention and legal hold policies
├── routing-policies/          # Staged model routing and fallback policies
├── schemas/                   # 25+ JSON Schema contracts (Draft 2020-12)
├── scripts/
│   ├── native/                # C# P/Invoke SafeFS backends (Windows/Unix handles)
│   ├── Lizard.*.psm1          # Core PowerShell modules (SafeFs, Trust, Plan, Records, etc.)
│   ├── install.ps1            # Transactional target installer
│   ├── update-target.ps1      # Drift-aware target updater
│   ├── uninstall.ps1          # Cryptographically verified uninstaller
│   └── doctor.ps1             # Strict health & integrity validator
├── skills/                    # 21 Reusable skill packages with skill.json metadata
├── templates/                 # Target project seeds & memory structures
└── tests/
    ├── adversarial/           # 14 Adversarial attack & tamper tests
    ├── integration/           # 16 End-to-end lifecycle integration tests
    ├── schema/                # Schema mutation and contract tests
    └── unit/                  # 13 Unit test suites for primitives
```

---

## 7. Summary: Why This Architecture Protects Your Team

1. **Zero Hallucination Leaks:** AI assistants cannot overwrite code or leak secrets because file mutations are checked against strict SafeFS boundaries.
2. **Zero Vendor Lock-In:** The same engineering standards work seamlessly across Cursor, Copilot, Claude Code, Codex, and Gemini.
3. **Audit-Ready Evidence:** Every model decision, loop run, and verification command produces cryptographically signed, replay-protected receipts.
4. **Idempotent & Reversible:** Every operation can be dry-run previewed, audited, safely updated, or completely removed with zero leftover residue.
