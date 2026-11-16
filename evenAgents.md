### Agent Roles & Operational Scopes

#### A. Orchestrator Agent (The Director)
* **Objective:** Enforce global logic consistency across execution states. Prevent code fragmentation.
* **Responsibilities:** Coordinates tasks between discovery, dependency checking, and refactoring. Inspects code adjustments against strict continuous background execution requirements.

#### B. Codebase Discovery Agent (The Reader)
* **Objective:** Extract structural code paths, data flow models, and existing API behaviors from the project's core `lib/` directory.
* **Responsibilities:** Scans `main.dart`, Bluetooth state wrappers, and notification layers. Maps out how information moves from `SpeechToText` to the hardware layer.

#### C. Dependency Alignment Agent (The Auditor)
* **Objective:** Modernize and verify the system's `pubspec.yaml` file to ensure background capability and localization stability.
* **Responsibilities:** Injects and updates background processing hooks, permission declarations, and version locks for speech tracking.

#### D. State Machine Refactoring Agent (The Engineer)
* **Objective:** Implement the bulletproof logic loop inside `lib/pages/live_caption_page.dart`.
* **Responsibilities:** Handles low-level lifecycle bindings, continuous microphone re-arming, inactivity cleanups, and the simplified Vietnamese ASCII fallback conversion.
