# 📜 Starfleet Directive: UX Optimization Protocol for Terminal-Kniferoll

**Target Entity**: Autonomous Engineering Agent (Gemini-class or higher)
**Mission Objective**: Enhance the performance, resilience, and user experience of the `terminal-kniferoll` deployment suite.

## 📡 Operational Context
This repository is a core dependency of the `lcars-core` ecosystem, providing the foundational terminal environment for nodes across the Starfleet hybrid cloud. Current implementation benchmarks identify opportunities for deployment acceleration and enhanced display resilience.

## 🛠 Required Enhancements

### 1. Parallel Deployment Engine (`install_linux.sh`)
- **Action**: Implement a non-blocking, parallel package installation phase.
- **Logic**: For supported package managers (`pacman`, `apt`), utilize background processes or parallel execution to install the `SHARED TOOLING PAYLOAD` simultaneously.
- **Constraint**: Maintain idempotency and clear, atomic logging to prevent terminal output interleaving. Ensure the user can still monitor progress via a centralized status bar or sequential log flush.

### 2. Adaptive Scene Intelligence (`projector.py`)
- **Action**: Integrate real-time terminal dimension awareness into the orchestration loop.
- **Implementation**:
    - Update the `Scene` dataclass to include optional `min_width` and `min_height` fields.
    - Before executing a scene, utilize `shutil.get_terminal_size()` to verify the current buffer.
    - **Logic**: If dimensions are insufficient, skip the scene and proceed to the next valid candidate. This eliminates "Terminal size too small" failures and ensures the projector remains "always-on" regardless of window resizing.

### 3. Integrated Scene Architect (TUI)
- **Action**: Develop a Terminal User Interface (TUI) for interactive configuration and "on-the-fly" adjustments.
- **Framework**: Leverage modern libraries (e.g., `Textual` or `Blessed`).
- **Features**:
    - **Visual Scene Manager**: Toggle scenes on/off via a checklist.
    - **Live Duration Tuning**: Interactive sliders or input fields to adjust scene duration and daemon states.
    - **Instant Preview**: Ability to "Test Run" a single scene from the menu before committing to the rotation.
- **Persistence**: Automatically serialize changes back to `~/.config/projector/config.json`.

## 🛡 Security & Fleet Integrity
- **No Regressions**: Maintain functional parity for macOS (`install_mac.sh`) and Windows (`install_windows.ps1`).
- **Zero Secrets**: Rigorously preserve the `PRIVATE_*` environment variable masking and Zscaler proxy detection.
- **Idempotency**: All enhancements must be safe to execute on top of existing installations without data loss.
