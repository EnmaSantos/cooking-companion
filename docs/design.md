# Product and UX design

## User and problem

A home cook moves between recipes, pantry, and shopping while preparing meals. The app should answer what can be made, guide cooking without losing one's place, and update stock only after the cook confirms what was used.

## Information architecture

Four tabs serve persistent destinations: Recipes, Pantry, Shopping, and Settings. Recipes has My Recipes and Discover. Cooking is opened from a recipe or resumed from the persistent banner because it is a temporary task tied to one recipe.

## Core flows

1. Discover a TheMealDB recipe → review ingredients and steps → save a local, editable copy → compare against pantry.
2. Add an exact, estimated, or availability-only pantry item → optionally confirm a USDA food match.
3. Start cooking → check ingredients and steps → resume after interruption → review usage → confirm → see updated balance and transaction history.
4. Add missing or low-stock items to shopping → confirm purchased quantity → record the purchase in pantry.

## Design decisions

- **Usage confirmation:** checkboxes are progress markers; only the final review writes inventory changes. This protects against abandoned sessions and ingredient substitutions.
- **Three tracking modes:** eggs can be counted precisely; flour can be estimated from a bag; cinnamon can simply be marked available. The UI labels estimated readiness as likely.
- **Unknown measures:** imported phrases such as “to taste” remain visible and editable. They never support a numeric stock claim.
- **Large cooking controls:** steps and ingredient checks use touch-sized native controls, Dynamic Type, and a kept-awake screen during the session.
- **Source ownership:** Discover content can disappear from the network, so saving creates a local recipe. TheMealDB stays attributed. USDA enrichment is optional and can be changed after confirmation.
- **Shopping placement:** recipe details generate shortages; retailer links sit in Shopping details to keep cooking focused.

## Figma deliverable

The [Cooking Companion product and UX file](https://www.figma.com/design/2VrGZrTryO0BAjVjlaXqpQ) has six pages: Product Definition, User Flows, Wireframes, Components, Prototype, and Decision Log. The prototype starts at **01 Recipes · My Recipes** and links the four tabs, discovery, recipe detail, a saved recipe, cooking, usage review, and shopping. The component page includes reusable action, recipe row, ingredient status variants, tab bar, and cooking checklist components with light/dark color tokens. Inter is used only as a readable Figma canvas fallback because its renderer did not display SF Pro; the native app uses iOS system type.

## Figma-to-SwiftUI comparison

The prototype establishes navigation, hierarchy, status language, and touch target placement. SwiftUI uses native `List`, `Form`, segmented pickers, sheets, tab items, and Dynamic Type in place of the prototype's custom card surfaces. This keeps controls familiar, accessible, and adaptive on iPhone. The prototype illustrates a typical kitchen state; the app also renders empty, offline, loading, and retry states from live data. Recipe photos are remote in discovery and cached in saved recipes. Colors follow the system appearance in the app, while Figma provides light/dark tokens for design review.
