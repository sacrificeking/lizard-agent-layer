# Profiles

Profiles describe how much agent infrastructure a target project should receive.

## minimal

For small scripts, libraries, or experiments. Installs git safety and research audit skills only.

## standard

For normal product repositories. Adds release, dependency upgrade, git safety, and research audit workflows.

## supabase-react-finance

For high-risk React/Vite/Supabase finance applications. Adds frontend, design system, Supabase, edge functions, data quality, release, git safety, dependency, and research audit skills.

## Profile fields

- `projectSize`: `small`, `medium`, or `large`
- `riskLevel`: `low`, `medium`, or `high`
- `memoryMode`: `curated`, `private-episodic`, or `off`
- `harnesses`: tools that should read the generated layer
- `skills`: reusable skills copied into the target project
- `verification`: project-specific checks agents should prefer before finalizing work
