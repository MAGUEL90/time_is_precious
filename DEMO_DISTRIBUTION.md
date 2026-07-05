# DEMO DISTRIBUTION — Time is Precious

Last updated: 2026-06-07

## Purpose
Define where the playable demo should be tested and distributed, and what role each platform should have.

The demo should not be uploaded everywhere at once. Distribution should expand in stages as the build becomes more stable, readable, and presentable.

## Primary Demo Hub
### 1. One Percent Studio Website
The One Percent Studio website should become the main branded home for the browser demo.

Primary role:
- Direct browser testing under the studio's own identity.
- Central location for the latest approved web build.
- Main destination linked from social media and development content.
- Controlled testing before wider platform distribution.

Minimum website requirements:
- Clear `Play Demo` button.
- Current demo version and build date.
- Short controls and objective explanation.
- Known issues section.
- Feedback form or bug report link.
- Basic device and browser compatibility note.
- Clear label when a build is experimental.
- Simple analytics for demo starts, completion, and major drop-off points where possible.

The website should be treated as the source of truth for the current browser demo.

## Secondary Platforms
### 2. itch.io
Role:
- Early public or limited-access testing.
- Browser build mirror.
- Optional downloadable build.
- Easy sharing with indie game communities and testers.

Use itch.io after the core loop can be completed without developer intervention.

### 3. Steam Playtest
Role:
- Controlled testing with players already connected to Steam.
- Testing before releasing a formal Steam demo.
- Gathering feedback from a more store-oriented audience.

Do not prioritize Steam Playtest until the vertical slice has clear onboarding, stable controls, readable UI, and a meaningful end point.

### 4. Steam Demo
Role:
- Public release-facing demo connected to the future Steam store page.
- Wishlist conversion and broader launch preparation.

The Steam demo should represent the intended quality direction, not an unstable technical prototype.

### 5. Game Jolt
Role:
- Optional community-facing mirror.
- Additional feedback and discovery among indie game players.

Use only after the demo has clear presentation, screenshots, instructions, and a reliable web or downloadable build.

### 6. CrazyGames
Role:
- Later browser discovery channel.
- Potential access to a larger casual web-game audience.

This is not an early prototype target. Consider it only after web performance, loading time, controls, onboarding, and retention are strong enough for external platform review.

## Audience Channels — Not Hosting Platforms
These channels should send players toward the One Percent Studio website or the currently preferred test platform:
- One Percent Studio social media.
- Discord community or private tester group.
- Relevant Reddit communities, following each community's self-promotion rules.
- Development logs and short-form progress content.
- Email list or tester registration form when available.

Do not maintain separate uncontrolled builds for every audience channel. Keep one approved demo version and point traffic toward it.

## Recommended Rollout Order
### Stage A — Internal Test
Host a private or unlisted build on the One Percent Studio website.

Goal:
- Confirm the full core loop works.
- Catch blocking bugs.
- Validate browser loading and controls.

### Stage B — Small External Test
Use:
- One Percent Studio website.
- itch.io as a secondary mirror or restricted test page.

Goal:
- Test onboarding and clarity with players who did not build the game.
- Collect structured feedback.

### Stage C — Community Test
Add Game Jolt only when the build is stable enough for broader community feedback.

Goal:
- Increase tester variety.
- Observe whether the game is understandable without direct explanation.

### Stage D — Steam Playtest
Start after a vertical slice exists and the team is preparing for store-facing testing.

Goal:
- Validate retention, session quality, hardware compatibility, and player expectations.

### Stage E — Public Demo Expansion
Use:
- One Percent Studio website.
- itch.io.
- Steam Demo.
- CrazyGames only if the browser version meets platform-quality expectations.

Goal:
- Public discovery.
- Wishlist and audience growth.
- Launch preparation.

## Demo Readiness Checklist
Before any wider external test:
- [ ] The player can complete the intended demo loop without developer help.
- [ ] The demo has a clear beginning, objective, and end point.
- [ ] Controls are visible and understandable.
- [ ] Critical UI information is readable.
- [ ] The build does not require debug tools.
- [ ] The build has a visible version number.
- [ ] Known issues are documented.
- [ ] Feedback can be submitted easily.
- [ ] Browser loading and basic compatibility have been tested.
- [ ] The same approved build is used across active testing channels where possible.

## Recommended Current Decision
For the current technical prototype stage:

1. Prepare the One Percent Studio website as the future primary browser-demo hub.
2. Keep itch.io as the first external mirror.
3. Do not upload to every platform yet.
4. Plan for Steam Playtest after the vertical slice is stable.
5. Treat Game Jolt and CrazyGames as later expansion channels, not immediate priorities.

## Codex Instruction
When demo distribution work begins, Codex should:
- Keep this document synchronized with `ROADMAP.md`.
- Avoid adding platform-specific build pipelines before the core playable loop is stable.
- Prefer one reproducible web export process over separate manual builds.
- Document versioning, export steps, deployment requirements, and known browser limitations.
- Keep the One Percent Studio website as the primary demo destination unless the project direction is explicitly changed.
