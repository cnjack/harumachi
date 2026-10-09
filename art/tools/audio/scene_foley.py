"""Short, dry ceramic and tea sounds for the actual tabletop animation cues.

Four deterministic variations prevent identical repeated ticks. No external recordings.
"""
from pathlib import Path
import json
from synth_core import SR, tt, butter, fade, peak_norm, write, np


def build(destination):
    destination = Path(destination)
    report = {}
    for kind in ("dish_place", "cup_sip"):
        for variant in range(4):
            random = np.random.default_rng(202610080 + variant)
            t = tt(int(SR * (.28 if kind == "dish_place" else .38)))
            if kind == "dish_place":
                result = .20 * np.sin(2*np.pi*(110+variant*3)*t) * np.exp(-t/.034)
                for frequency, amplitude, decay in [(1660,.12,.036),(2430,.075,.027),(3540,.04,.018)]:
                    result += amplitude*np.sin(2*np.pi*frequency*(1+variant*.009)*t)*np.exp(-t/decay)
                result += .06*butter(random.standard_normal(len(t)),"band",[500,4500])*np.exp(-t/.018)
            else:
                envelope=np.sin(np.pi*np.clip(t/.32,0,1))**1.8
                breath=butter(random.standard_normal(len(t)),"band",[480,1850])
                result=.08*breath*envelope*(.72+.28*np.sin(2*np.pi*(29+variant)*t))
                result+=.018*np.sin(2*np.pi*(710+variant*11)*t)*envelope*np.exp(-t/.12)
            result=peak_norm(fade(result,.002,.035),-10)
            name=f"fx_{kind}_{variant}.wav"
            write(str(destination/name),result,ogg=False)
            report[name]={"seconds":round(len(t)/SR,3),"peak_db":-10,"variant":variant}
            if variant==0:write(str(destination/f"fx_{kind}.wav"),result,ogg=False)
    return report


if __name__ == "__main__":
    root=Path(__file__).resolve().parents[3]
    report=build(root/"game/assets/audio/sfx")
    print(json.dumps(report,indent=2))
