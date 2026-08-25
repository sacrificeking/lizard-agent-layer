---
name: frontend-engineering
description: Universal frontend architecture, component hierarchy, UI state management, bundle discipline, responsive layout, type safety, and accessibility across React, Angular, Vue, Svelte, Next.js, and Nuxt.
---

# Frontend Engineering

## Rules

- Maintain clear separation between container state, presentation components, and domain business logic.
- Ensure strict TypeScript/type safety across all component props, event handlers, and API data layers.
- Guard against layout shift (CLS), unnecessary re-renders, and memory leaks in reactive component subscriptions.
- Adhere to accessible semantic markup (WCAG 2.1 AA), keyboard navigation, and proper ARIA labeling.
- Enforce clean bundle discipline: avoid accidental inclusion of server-only modules, heavy unoptimized dependencies, or private environment variables in client bundles.
- Run frontend typecheck and unit/component tests before declaring UI changes complete.
