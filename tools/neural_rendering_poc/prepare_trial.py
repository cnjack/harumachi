#!/usr/bin/env python3
"""Add only a diagnostic PNG entry point to a local macOS overlay checkout."""
import argparse
from pathlib import Path
import shutil

parser = argparse.ArgumentParser()
parser.add_argument("checkout", type=Path)
args = parser.parse_args()
sources = args.checkout / "Sources/NeuralScreenMac"
app = sources / "App.swift"
text = app.read_text()
anchor = '        if CommandLine.arguments.contains("--video-test")'
addition = '''        if CommandLine.arguments.contains("--scene-trial") {
            Task {
                do { try await SceneTrial.run(); exit(0) }
                catch { fputs("ERROR: \\(error.localizedDescription)\\n", stderr); exit(1) }
            }
            CFRunLoopRun()
            return
        }
'''
if 'CommandLine.arguments.contains("--scene-trial")' not in text:
    if text.count(anchor) != 1:
        raise SystemExit("Upstream App.swift changed; inspect it before adapting the diagnostic entry point")
    app.write_text(text.replace(anchor, addition + anchor, 1))
shutil.copyfile(Path(__file__).with_name("SceneTrial.swift"), sources / "SceneTrial.swift")
print("Diagnostic adapter installed; RenderEngine and model implementation unchanged")
