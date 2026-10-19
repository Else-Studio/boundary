# Boundary Framework

Boundary is a core reactive framework for building tri-platform (web, mobile, desktop) Flutter applications. It focuses on consistent reactivity, platform-agnostic navigation, and accessibility.

## Getting Started

To learn how to configure a new project and build your first features with the Boundary framework, please refer to the [Getting Started Guide](file:///Users/kuan/Cham/Work/vh/vh-core/boundary/GETTING_STARTED.md).

## Core Principles

- **Three-Layer Reactive Architecture:** Dumb views subscribing to controller streams and dispatching actions to controllers.
- **Action-Only Side Effects:** State mutations and side effects are initiated via `dispatch(Action)`.
- **Platform-Agnostic Routing:** Navigation is triggered via `ConfigurationBase` subclasses mapping to specific routes.
