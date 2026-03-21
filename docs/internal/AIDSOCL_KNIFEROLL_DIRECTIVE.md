# MISSION DIRECTIVE: Terminal-Kniferoll Interactive & Passive Architect

**Target Entity:** Specialized Agentic Employee (Architect/Engineer Persona)
**Context:** AIDSOCL (Agentic Intelligence DevSecOps Command Lab) Ecosystem

## 1. The AIDSOCL Context & Architectural Ethos
The AIDSOCL ecosystem is an advanced, AI-driven DevSecOps lab and hybrid-cloud infrastructure (codenamed "lcars-core" and "terminal-kniferoll"). 
**Core Ethos:**
- **Disposability First:** Every node, vessel, and endpoint must be fully reconstructible from infrastructure-as-code.
- **GitHub is SSoT (Single Source of Truth):** No manual or local changes persist without being synchronized and pushed back to the main repository.
- **Zero-Knowledge Privacy:** Secrets are encrypted via SOPS/Age.
- **Universal Awareness:** The system performs Deep Environmental Scans on wake to autonomously map its OS, virtualization status, and network connectivity.
- **Agentic Delegation:** AI hivemind projects work continuously to maintain, provision, and self-heal the lab.

## 2. Your Objective: The Dual-Mode Launch System
You are tasked with rewriting the terminal-kniferoll bootstrapper/entrypoint (`install.sh`) to operate strictly in two primary modes upon launch. It must first prompt the user: **"Select Execution Mode: [1] Interactive (Custom) or [2] Passive (Automated AIDSOCL Sync)"**.

### Mode 1: Interactive Mode (The Custom Tailor)
- **Goal:** Allow the user granular control over all installations and configurations.
- **Features:**
  - Provide a conversational, helpful CLI experience.
  - Offer suggestions on tools based on detected OS (e.g., "We see you are on CachyOS, would you like to install yay/paru tools?").
  - Prompt for all tooling payloads (Shell, Projector, Antigravity IDE, Rust CLI tools, etc.).

### Mode 2: Passive Mode (The Psychic Synchronizer)
- **Goal:** Total autonomous alignment with the AIDSOCL ecosystem.
- **Features:**
  - **Incredible Ascertainment:** Silently and deeply scan the system (OS, hardware, network).
  - **Ecosystem Alignment:** Automatically figure out what needs to be done to bring the user's shell and tooling into 100% compliance with the AIDSOCL baseline.
  - **Psychic SCM Sync:** Automatically check the upstream GitHub repository for terminal-kniferoll and lcars-core. If local is out of date, fetch, re-sync, and apply updates.
  - **No-Prompt Execution:** Make high-confidence decisions without asking the user, leveraging the architectural ethos to ensure all necessary tools and customizations are perfectly deployed.

## 3. Execution Steps
1. Ingest `terminal-kniferoll/install.sh`, `terminal-kniferoll/install_linux.sh`, and `lcars-core/scripts/lcars_awareness.sh`.
2. Implement the Mode Prompt at the very start of `install.sh`.
3. Refactor the deployment logic to branch into Interactive or Passive pipelines.
4. Integrate a self-update and auto-sync mechanism for Passive Mode using git.
5. Validate the changes against the Disposability and Idempotency mandates.
