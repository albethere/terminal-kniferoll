#!/usr/bin/env python3
import os
import sys
import time
import json
import signal
import argparse
import platform
import subprocess
import threading
from pathlib import Path
from dataclasses import dataclass, asdict

# ==========================================
# PHASE 1: DATA MODELS & CONFIGURATION
# ==========================================
@dataclass
class Scene:
    name: str
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
    config_dir.mkdir(parents=True, exist_ok=True)
    return config_dir

def generate_default_config(config_path: Path) -> None:
    if config_path.exists():
        return

    default_scenes = [
        Scene(name="Weather", command="weathr", duration=30, is_daemon=True),
        Scene(name="System Dashboard", command="fastfetch | lolcat", duration=10, is_daemon=False),
        Scene(name="Resource Monitor", command="btop", duration=30, is_daemon=True),
        Scene(name="Digital Bonsai", command="cbonsai --live --life 40", duration=20, is_daemon=False),
        Scene(name="Matrix Rain", command="cmatrix -s -u 10", duration=30, is_daemon=True),
        Scene(name="Network Pulse", command="trip -n 1.1.1.1", duration=15, is_daemon=True)
    ]

    config_data = {"scenes": [asdict(scene) for scene in default_scenes]}
    with open(config_path, "w", encoding="utf-8") as f:
        json.dump(config_data, f, indent=4)

def load_config(config_path: Path) -> list[Scene]:
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            scenes = []
            for scene_data in data.get("scenes", []):
                # Ensure compatibility with older config formats
                if "name" not in scene_data:
                    scene_data["name"] = scene_data.get("command", "Unnamed Scene")
                scenes.append(Scene(**scene_data))
            return scenes
    except Exception as e:
        print(f"[-] Config parsing failed: {e}")
        sys.exit(1)

# ==========================================
# PHASE 2: SUBPROCESS WRANGLER
# ==========================================
class SceneExecutor:
    def __init__(self):
        self.current_process = None
        self.stop_event = threading.Event()
        self.skip_event = threading.Event()
        self.is_posix = os.name == 'posix'
        self.current_duration_multiplier = 1.0
        
        signal.signal(signal.SIGINT, self._handle_termination)
        signal.signal(signal.SIGTERM, self._handle_termination)

    def _handle_termination(self, signum, frame):
        self.stop_event.set()
        self.kill_current()
        sys.stdout.write("\033[?25h") 
        sys.stdout.flush()
        sys.exit(0)

    def execute(self, scene: Scene):
        self.skip_event.clear()
        kwargs = {'shell': True}
        if self.is_posix:
            kwargs['preexec_fn'] = os.setsid

        self.current_process = subprocess.Popen(scene.command, **kwargs)

        target_duration = scene.duration * self.current_duration_multiplier
        start_time = time.time()
        
        while time.time() - start_time < target_duration:
            if self.stop_event.is_set() or self.skip_event.is_set():
                break
            if self.current_process.poll() is not None and not scene.is_daemon:
                time.sleep(2) 
                break
            time.sleep(0.1)

        self.kill_current()

    def kill_current(self):
        if not self.current_process or self.current_process.poll() is not None:
            return
        try:
            if self.is_posix:
                os.killpg(os.getpgid(self.current_process.pid), signal.SIGTERM)
            else:
                self.current_process.terminate()
            self.current_process.wait(timeout=1)
        except Exception:
            try:
                self.current_process.kill()
            except:
                pass

# ==========================================
# PHASE 3: ORCHESTRATOR & INTERACTION
# ==========================================
def clear_screen():
    sys.stdout.write("\033[2J\033[H")
    sys.stdout.flush()

def interaction_handler(executor, scenes):
    import termios
    import tty

    def getch():
        fd = sys.stdin.fileno()
        old_settings = termios.tcgetattr(fd)
        try:
            tty.setraw(sys.stdin.fileno())
            ch = sys.stdin.read(1)
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
        return ch

    while not executor.stop_event.is_set():
        ch = getch()
        if ch == '\r' or ch == '\n' or ch == ' ':
            executor.skip_event.set()
        elif ch == '+':
            executor.current_duration_multiplier *= 1.2
            print(f"\r[+] Speed: {1/executor.current_duration_multiplier:.2f}x", end="")
        elif ch == '-':
            executor.current_duration_multiplier /= 1.2
            print(f"\r[+] Speed: {1/executor.current_duration_multiplier:.2f}x", end="")
        elif ch == 'q':
            executor._handle_termination(None, None)

def main():
    parser = argparse.ArgumentParser(description="Terminal Projector v2026")
    parser.add_argument("--config", type=str, help="Override config path")
    args = parser.parse_args()

    config_dir = get_config_dir()
    config_path = Path(args.config) if args.config else config_dir / "config.json"
    generate_default_config(config_path)
    scenes = load_config(config_path)
    
    executor = SceneExecutor()
    threading.Thread(target=interaction_handler, args=(executor, scenes), daemon=True).start()

    clear_screen()
    print("\033[1;35m================================================================\033[0m")
    print("\033[1;38;5;214m  ■■■■■■■  \033[1;38;5;75mT E R M I N A L   P R O J E C T O R   2 0 2 6\033[0m")
    print("\033[1;35m================================================================\033[0m")
    print("\n[Controls] SPACE: Skip | +/-: Adjust Speed | Q: Exit")
    print(f"[Loading] {len(scenes)} scenes queued...")
    time.sleep(2)

    try:
        while True:
            for scene in scenes:
                clear_screen()
                executor.execute(scene)
    except KeyboardInterrupt:
        executor._handle_termination(None, None)

if __name__ == "__main__":
    main()
