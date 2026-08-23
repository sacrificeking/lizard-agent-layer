# Skill Packages

Each skill directory contains harness-facing instructions and machine-facing lifecycle metadata:

```text
skills/<name>/
  SKILL.md
  skill.json
  references/   # optional
  scripts/      # optional
  assets/       # optional
  tests/        # optional
```

`SKILL.md` keeps only the Codex-compatible `name` and `description` frontmatter. `skill.json` declares the package version, compatibility, dependencies, maximum permissions, provenance, conflicts, migration sources, and conservative disable/recovery/removal behavior.

## Validate a package

```powershell
./scripts/skill-lifecycle.ps1 -TargetRoot C:\work\project -SkillName git-safety -Action Validate
```

Validation checks every repository package and the dependency graph. It does not write to the target.

## Preview and approve a lifecycle change

```powershell
$plan = 'D:\reviewed-plans\git-safety-disable.json'
./scripts/skill-lifecycle.ps1 -TargetRoot C:\work\project -SkillName git-safety -Action Disable -CanonicalPlanPath $plan
$sha256 = (Get-FileHash -LiteralPath $plan -Algorithm SHA256).Hash.ToLowerInvariant()
./scripts/skill-lifecycle.ps1 -TargetRoot C:\work\project -SkillName git-safety -Action Disable -Apply -ApprovedPlanPath $plan -ApprovedPlanSha256 $sha256 -HumanApproved
```

The plan must remain outside the target. Calculate or obtain its digest independently after review. `Install`, `Update`, `Migrate`, `Disable`, `Recover`, and `Remove` use the same flow.

## Lifecycle guarantees

- Preview does not mutate the target.
- Apply revalidates source files, target content, physical removal identities, and target-root identity after acquiring the transaction lock.
- Update is idempotent; an unchanged package and state commit zero target mutations.
- Migration is allowed only from a version listed in `migration.from_versions`.
- Disable and remove refuse modified or unknown package content.
- Disable retains exact file hashes for recovery. Recovery requires the exact reviewed package version and content.
- Remove retains a state tombstone but no installed-file claim.
- Dependencies must be active at a compatible version; active conflicts block before plan creation.
- Any mutation failure rolls back through the shared transaction journal.

Normal profile installation also validates package metadata, copies it into primary and mirror locations, records version/hash/dependencies/permissions in `.agent/skills/_manifest.jsonl`, and exposes integrity failures through strict Doctor. Profile-installed primary and mirror copies remain one layer-managed unit and must be changed with the normal layer update flow. The standalone lifecycle command intentionally does not modify harness mirrors or adopt a profile installation.
