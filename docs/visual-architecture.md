# Visual Architecture & Systems Blueprint

> **lizard-agent-layer** is a vendor-neutral, portable governance and execution infrastructure for AI coding agents. It overlays standard development environments with strict security, deterministic workflows, long-term memory, and cryptographic verification.

---

## 1. High-Level System Topology

```text
┌──────────────────────────────────────────────────────────────────────────────────┐
│                      LIZARD-AGENT-LAYER (Source Framework)                       │
│                                                                                  │
│  📁 profiles/        --> (minimal, standard, supabase-react-finance)             │
│  📁 packs/           --> (frontend, security, supabase, loop-engineering, etc.)  │
│  📁 skills/          --> (21 Reusable packages with versioned skill.json)        │
│  📁 protocols/       --> (Permissions, Secret-Handling, Release-Gates, Handoff)  │
│  📁 adapters/        --> (Cursor, GitHub Copilot, Claude Code, Gemini, Codex)    │
│  📁 schemas/         --> (25+ Draft 2020-12 Validation Contracts)                │
│  📁 scripts/         --> (SafeFS Handle Engine, Zero-Trust Signatures, Recovery) │
└────────────────────────────────────────┬─────────────────────────────────────────┘
                                         │
                                         │  Preview / Apply Plan
                                         ▼
┌──────────────────────────────────────────────────────────────────────────────────┐
│                    TRANSACTIONAL INSTALL & UPDATE ENGINE                         │
│                                                                                  │
│   [ Target Analyzer ] ──► [ Canonical Plan (SHA-256) ] ──► [ Write-Ahead Journal] │
└────────────────────────────────────────┬─────────────────────────────────────────┘
                                         │
                                         │  Deterministic Projection
                                         ▼
┌──────────────────────────────────────────────────────────────────────────────────┐
│                        TARGET PROJECT (Your Repository)                          │
│                                                                                  │
│  ┌────────────────────────────────────────────────────────────────────────────┐  │
│  │ 📁 .agent/ Core (Shared Across All AI Tools)                               │  │
│  │                                                                            │  │
│  │  ├── project-profile.json   --> Active profile & pack configuration        │  │
│  │  ├── 📁 memory/             --> Structured semantic decisions & lessons    │  │
│  │  ├── 📁 protocols/          --> Security rules & staged execution policy   │  │
│  │  ├── 📁 skills/             --> Installed skill packages & manifest        │  │
│  │  └── 📁 routing/            --> Execution receipts & policy controls       │  │
│  └─────────────────────────────────────┬──────────────────────────────────────┘  │
│                                        │                                         │
│                                        │ Translates rules into IDE configs       │
│                                        ▼                                         │
│  ┌────────────────────────────────────────────────────────────────────────────┐  │
│  │ 📁 IDE Harness Wiring (Native IDE Instructions)                            │  │
│  │                                                                            │  │
│  │  • .cursor/rules/lizard-agent-layer.mdc  (Cursor IDE)                      │  │
│  │  • .github/copilot-instructions.md       (GitHub Copilot)                  │  │
│  │  • CLAUDE.md                             (Claude Code)                     │  │
│  │  • GEMINI.md                             (Gemini CLI)                      │  │
│  │  • AGENTS.md                             (Codex / Generic Agents)          │  │
│  └─────────────────────────────────────┬──────────────────────────────────────┘  │
│                                        │                                         │
│                                        │ Enforces safety & quality over          │
│                                        ▼                                         │
│  ┌────────────────────────────────────────────────────────────────────────────┐  │
│  │ 📁 Your Application Source Code (100% Preserved)                           │  │
│  │                                                                            │  │
│  │  • src/        • package.json    • tests/       • docs/                    │  │
│  └────────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. The 4 Security & Governance Pillars

```text
┌──────────────────────────────────────┐  ┌──────────────────────────────────────┐
│       1. HANDLE-BOUND SAFEFs         │  │     2. ZERO-TRUST SIGNATURES         │
├──────────────────────────────────────┤  ├──────────────────────────────────────┤
│ • Windows: NtCreateFile / Native     │  │ • RS256 / Ed25519 Asymmetric Keys    │
│ • Unix: openat / renameat / unlinkat │  │ • Nonce Challenges & Replay Ledgers  │
│ • Descriptor-relative mutations      │  │ • Strict Implementer vs. Verifier    │
│ • Immune to Junction / Symlink Swaps │  │   role separation                    │
│ • Prevents race conditions & escape  │  │ • Rejects synthetic PASS evidence    │
└──────────────────────────────────────┘  └──────────────────────────────────────┘
                   ▲                                         ▲
                   │                                         │
                   ▼                                         ▼
┌──────────────────────────────────────┐  ┌──────────────────────────────────────┐
│       3. TRANSACTIONAL ENGINE        │  │      4. RECORDS & RETENTION          │
├──────────────────────────────────────┤  ├──────────────────────────────────────┤
│ • Write-Ahead Journals (.tmp/tx-*)   │  │ • 3 Modes: curated, episodic, off    │
│ • Target-level process locks         │  │ • Cryptographic Active Legal Holds   │
│ • Automatic rollback on error        │  │ • Export Archive verification        │
│ • Reversible recovery tooling        │  │ • Deletion Receipts (ADR-0023)       │
│ • 0 Leftover residue on abort        │  │ • GDPR / Compliance deletion proof   │
└──────────────────────────────────────┘  └──────────────────────────────────────┘
```

---

## 3. Staged Execution & Anti-Hallucination Pipeline (10-80-10)

```text
DEVELOPER                  AI CODING AGENT               .agent/ GOVERNANCE          CONSTRAINED VERIFIER
    │                             │                              │                            │
    │ 1. "Implement feature"      │                              │                            │
    ├────────────────────────────►│                              │                            │
    │                             │ 2. Load Profile & Memory     │                            │
    │                             ├─────────────────────────────►│                            │
    │                             │ 3. Check DECISIONS & LESSONS │                            │
    │                             │◄─────────────────────────────┤                            │
    │                             │                              │                            │
    │   ┌─────────────────────────┴────────────────────────────┐ │                            │
    │   │ STAGE 1: PLAN & CLARIFY (10% Token Budget)           │ │                            │
    │   │ • Inspect existing code & types                      │ │                            │
    │   │ • Formulate structured, testable plan                │ │                            │
    │   └─────────────────────────┬────────────────────────────┘ │                            │
    │                             │                              │                            │
    │ 4. Review Plan Proposal     │                              │                            │
    │◄────────────────────────────┤                              │                            │
    │ 5. Plan Approved            │                              │                            │
    ├────────────────────────────►│                              │                            │
    │                             │                              │                            │
    │   ┌─────────────────────────┴────────────────────────────┐ │                            │
    │   │ STAGE 2: CONSTRAINED EXECUTION (80% Token Budget)    │ │                            │
    │   │ • Guard against secret leaks (.env, credentials)     │ │                            │
    │   │ • Perform atomic, handle-bound file edits            │ │                            │
    │   │ • Maintain modular architecture discipline           │ │                            │
    │   └─────────────────────────┬────────────────────────────┘ │                            │
    │                             │                              │                            │
    │                             │ 6. Request Test Execution    │                            │
    │                             ├──────────────────────────────┼───────────────────────────►│
    │                             │                              │ 7. Run Test & Lint Suite   │
    │                             │                              │    (No inherited shell)    │
    │                             │ 8. Verified PASS / Evidence  │                            │
    │                             │◄─────────────────────────────┼────────────────────────────┤
    │                             │                              │                            │
    │   ┌─────────────────────────┴────────────────────────────┐ │                            │
    │   │ STAGE 3: INDEPENDENT VERIFICATION (10% Token Budget) │ │                            │
    │   │ • Record lessons in .agent/memory/ (if applicable)   │ │                            │
    │   │ • Assemble signed verification proof                 │ │                            │
    │   └─────────────────────────┬────────────────────────────┘ │                            │
    │                             │                              │                            │
    │ 9. Present Verified Result  │                              │                            │
    │◄────────────────────────────┤                              │                            │
```

---

## 4. Multi-Harness Adapter & Non-Clobbering Sidecar Flowchart

```text
                 [ Installer Evaluates Target File ]
                                  │
                                  ▼
                     /─────────────────────────\
                    <   Target File Exists?     >
                     \─────────────────────────/
                                  │
                 ┌────────────────┴────────────────┐
                 │ NO                              │ YES
                 ▼                                 ▼
    ┌───────────────────────────┐     /─────────────────────────\
    │ Write Primary Native File │    <  Layer-Owned & Unmodified?>
    │ (e.g. AGENTS.md / CLAUDE) │     \─────────────────────────/
    └───────────────────────────┘                  │
                                   ┌───────────────┴───────────────┐
                                   │ YES                           │ NO
                                   ▼                               ▼
                      ┌───────────────────────────┐   ┌───────────────────────────┐
                      │ Deterministically Refresh │   │ Write Isolated Sidecar    │
                      │ Layer Metadata Files      │   │ (e.g. .github/copilot-    │
                      └───────────────────────────┘   │ instructions.lizard.md)   │
                                                      └─────────────┬─────────────┘
                                                                    │
                                                                    ▼
                                                      ┌───────────────────────────┐
                                                      │ Generate Merge Suggestion │
                                                      │ (scripts/merge-           │
                                                      │  suggestions.ps1)         │
                                                      └─────────────┬─────────────┘
                                                                    │
                                                                    ▼
                                                      ┌───────────────────────────┐
                                                      │ 🧑 Human Reviews & Merges │
                                                      └───────────────────────────┘
```

---

## 5. Lifecycle State Machine

```text
┌─────────────┐       install.ps1 (dry-run)        ┌───────────────────┐
│  UNMANAGED  │ ─────────────────────────────────► │  PLAN GENERATED   │
│  REPOSITORY │                                    │  (.tmp/plan.json) │
└─────────────┘                                    └─────────┬─────────┘
       ▲                                                     │
       │                                                     │ Human Approval (SHA-256)
       │                                                     ▼
       │  uninstall.ps1                            ┌───────────────────┐
       │  -Mode complete                           │   LAYER ACTIVE    │
       │  (0 Residue Proof)                        │   & INSTALLED     │
       │                                           └─────────┬─────────┘
       │                                                     │
       │                                                     ▼
       │      update-target.ps1                    ┌───────────────────┐
       └────────────────────────────────────────── │  HEALTHY / AUDITED│
              (Preserves user edits)               │  (doctor.ps1 OK)  │
                                                   └───────────────────┘
```

---

## 6. Directory Structure & File Map Reference

```text
lizard-agent-layer/
├── adapters/                  # Harness translation shims (Cursor, Copilot, Claude, Gemini, Codex)
├── changes/                   # Versioned change records linking ADRs to path impacts
├── docs/
│   ├── adr/                   # 23 Architecture Decision Records (ADR-0001 to ADR-0023)
│   ├── getting-started.md     # Comprehensive 6-section operations guide
│   └── visual-architecture.md # This visual architecture blueprint
├── packs/                     # Reusable feature packs (frontend, supabase, security, loops)
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
