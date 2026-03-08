#!/usr/bin/env python3
import os
import sys
import time
import json
import signal
import argparse
import platform
import subprocess
from pathlib import Path
from dataclasses import dataclass, asdict

# ==========================================
# PHASE 1: DATA MODELS & CONFIGURATION
# ==========================================
@dataclass
class Scene:
    command: str
    duration: int
    is_daemon: bool

def get_config_dir() -> Path:
    system = platform.system()
    if system == "Windows":
        base_dir = Path.home() / "AppData" / "Roaming"
    else: 
        base_dir = Path.home() / ".config"
    
    config_dir = base_dir / "projector"
    try:
        config_dir.mkdir(parents=True, exist_ok=True)
    except PermissionError:
        print(f"[-] FATAL: Permission denied creating directory at {config_dir}")
        sys.exit(1)
    return config_dir

def generate_default_config(config_path: Path) -> None:
    if config_path.exists():
        return

    default_scenes = [
        Scene(command="weathr", duration=30, is_daemon=True),
        Scene(command="fastfetch | lolcat", duration=10, is_daemon=False),
        Scene(command="btop", duration=30, is_daemon=True),
        Scene(command="cbonsai --live --life 40", duration=20, is_daemon=False),
        Scene(command="cmatrix -s", duration=30, is_daemon=True)
    ]

    config_data = {"scenes": [asdict(scene) for scene in default_scenes]}
    try:
        with open(config_path, "w", encoding="utf-8") as f:
            json.dump(config_data, f, indent=4)
        print(f"[+] Default configuration matrix deployed to {config_path}")
    except IOError as e:
        print(f"[-] FATAL: Failed to write configuration matrix: {e}")
        sys.exit(1)

def load_config(config_path: Path) -> list[Scene]:
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            return [Scene(**scene) for scene in data.get("scenes", [])]
    except Exception as e:
        print(f"[-] FATAL: Config parsing failed: {e}")
        sys.exit(1)

# ==========================================
# PHASE 2: SUBPROCESS WRANGLER
# ==========================================
class SceneExecutor:
    def __init__(self):
        self.current_process = None
        self.is_posix = os.name == 'posix'
        
        signal.signal(signal.SIGINT, self._handle_termination)
        signal.signal(signal.SIGTERM, self._handle_termination)

    def _handle_termination(self, signum, frame):
        self.kill_current()
        sys.stdout.write("\033[?25h") 
        sys.stdout.flush()
        sys.exit(0)

    def execute(self, scene: Scene):
        kwargs = {'shell': True}
        if self.is_posix:
            kwargs['preexec_fn'] = os.setsid

        self.current_process = subprocess.Popen(scene.command, **kwargs)

        try:
            if scene.is_daemon:
                time.sleep(scene.duration)
                self.kill_current()
            else:
                self.current_process.wait(timeout=scene.duration)
                # Brief pause so non-daemon output is actually readable before clearing
                time.sleep(2) 
        except subprocess.TimeoutExpired:
            self.kill_current()
        except KeyboardInterrupt:
            self.kill_current()
            sys.exit(0)

    def kill_current(self):
        if not self.current_process or self.current_process.poll() is not None:
            return

        try:
            if self.is_posix:
                os.killpg(os.getpgid(self.current_process.pid), signal.SIGTERM)
            else:
                self.current_process.terminate()
            self.current_process.wait(timeout=2)
        except Exception:
            self.current_process.kill()

# ==========================================
# PHASE 3: ORCHESTRATOR & DISPLAY LOOP
# ==========================================
def clear_screen():
    """Wipes the terminal buffer instantly via ANSI escapes."""
    sys.stdout.write("\033[2J\033[H")
    sys.stdout.flush()

def main():
    parser = argparse.ArgumentParser(description="Terminal Multiplexer & Aesthetic Projector")
    parser.add_argument("--config", type=str, help="Override default configuration path")
    args = parser.parse_args()

    # Initialization
    config_dir = get_config_dir()
    config_path = Path(args.config) if args.config else config_dir / "config.json"
    
    generate_default_config(config_path)
    scenes = load_config(config_path)
    
    if not scenes:
        print("[-] FATAL: Configuration matrix is empty.")
        sys.exit(1)

    executor = SceneExecutor()

    # The Infinite Loop
    try:
        while True:
            for scene in scenes:
                clear_screen()
                executor.execute(scene)
    except KeyboardInterrupt:
        # Failsafe for the main loop
        executor._handle_termination(None, None)

if __name__ == "__main__":
    main()
