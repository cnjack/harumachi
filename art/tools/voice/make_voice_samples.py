"""Voice casting samples for 晴町日常 (Qwen3-TTS 1.7B CustomVoice / Base, 8-bit, via mlx-audio).

    cd /Users/jack/workpath/opensource/mlx-audio
    uv run python "<repo>/art/tools/voice/make_voice_samples.py" <out_dir>

Each character gets a few candidate voices:
  - "custom": a CustomVoice speaker plus a style instruction;
  - "designed": a CustomVoice take is pitch/formant shifted with ffmpeg (asetrate + atempo) to move the
    timbre (older, younger), then the Base model clones that shifted take so the new lines keep natural
    prosody instead of sounding resampled.
Every clip is transcribed with Qwen3-ASR and the character error rate is recorded in samples.json.
"""
import json, os, re, subprocess, sys, time
import numpy as np
from scipy.io import wavfile

OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "voice_samples")
os.makedirs(OUT, exist_ok=True)
FF = "/opt/homebrew/bin/ffmpeg"
SR = 24000

# (character, display name, description, lines)
CHARS = [
    ("mio", "澪", "社区活动联络人，二十出头，开朗、做事利落", [
        "早上好！今天也要加油哦。……啊，我是说我自己。每天早上都要这么给自己打一下气。",
        "集市之后，好几户人家来问下次什么时候办。你看，大家其实一直都在等一个理由。"]),
    ("ren", "莲", "年轻面包师，二十四五岁，热情、有点冒失", [
        "今天的第一炉是菠萝包。你闻到了吗？整条街都是黄油味。",
        "我在试做加了柚子皮的司康，第三次失败了。第四次一定行。……应该吧。"]),
    ("haru", "春", "退休园丁，七十多岁的奶奶，慈祥、慢悠悠", [
        "你看这丛紫阳花，今年开得特别蓝。土里埋了几根旧铁钉，颜色就会变蓝。这是我家老头子教我的。",
        "膝盖说要下雨了……可是天空说不会。我信天空。"]),
    ("tanaka", "田中爷爷", "七十四岁的农园管理员，话少、低沉", [
        "……早。土湿的时候最好翻，你来得正是时候。",
        "别急。菜和人一样，催不得。"]),
    ("aoi", "小葵", "十岁的小女孩，春的孙女，好奇、爱说话", [
        "早上好！奶奶说早起的孩子有牵牛花看，我今天看到了三朵！",
        "河里有小鱼！田中爷爷说不能下去抓，会被河童拉走的。……河童是真的吗？"]),
    ("sora", "空（主角独白）", "刚搬来的年轻人，片头和章节开头的内心独白", [
        "奶奶的房子还是老样子。推开门的时候，好像还能闻到那年夏天的蚊香味。",
        "晴町的夏天，原来一直在这里等我。"]),
    ("narrator", "旁白", "片头、回忆和地点描写", [
        "晴川从山里流下来，绕过晴町，一直流到很远的海边。",
        "末班车早就开走了。站牌下的长椅上，落着一片叶子。"]),
    ("kazuko", "和子阿姨（新：晴町商店店主）", "五十多岁，嗓门大、热心肠", [
        "欢迎光临！番茄种子今天刚到货，要不要看看？",
        "哎呀，又是你呀！来来来，这包盐送你，别客气。"]),
]
JA = {  # one Japanese line per character, as an alternative casting direction
    "mio": "おはよう！今日も頑張ろうね。……あ、自分に言ったの。",
    "ren": "今日の一番窯はメロンパン。バターの匂い、わかる？",
    "haru": "膝は雨が降るって言うけど……空は降らないって。私は空を信じるよ。",
    "tanaka": "……おはよう。土が湿ってる時がいちばん耕しやすい。",
    "aoi": "おはよう！早起きしたら、朝顔が三つも咲いてたよ！",
    "sora": "晴町の夏は、ずっとここで僕を待っていたんだ。",
}
# candidate voices: (id, label, kind, speaker, instruct, shift_semitones, tempo)
CAST = {
    "mio": [("A", "Vivian · 开朗", "custom", "Vivian", "开朗、亲切、充满活力的年轻女性，语速稍快，带着笑意。", 0, 1.0),
            ("B", "Serena · 温柔", "custom", "Serena", "温柔清澈的年轻女性，说话轻快、有礼貌。", 0, 1.0),
            ("J", "Ono Anna · 日语", "custom_ja", "Ono_Anna", "明るく元気な若い女性。", 0, 1.0)],
    "ren": [("A", "Aiden · 爽朗", "custom", "Aiden", "爽朗、热情的年轻男性，语气轻松，有点得意。", 0, 1.0),
            ("B", "Ryan · 腼腆", "custom", "Ryan", "温和、有点腼腆的年轻男性，说话带笑。", 0, 1.0),
            ("C", "Dylan · 京味", "custom", "Dylan", "年轻男性，普通话，开朗随和。", 0, 1.0),
            ("J", "Aiden · 日语", "custom_ja", "Aiden", "明るい若い男性。", 0, 1.0)],
    "haru": [("A", "Serena · 老奶奶", "custom", "Serena", "慈祥的老奶奶，语速缓慢，声音温暖，略带沙哑。", 0, 1.0),
             ("B", "Serena 降调重塑", "designed", "Serena", "慈祥的老奶奶，语速缓慢，声音温暖。", -2.5, 0.94),
             ("C", "Vivian 降调重塑", "designed", "Vivian", "温和的老奶奶，慢慢地说话，带着笑意。", -3.0, 0.92),
             ("J", "Ono Anna 降调 · 日语", "designed_ja", "Ono_Anna", "優しいおばあちゃん、ゆっくり話す。", -2.5, 0.94)],
    "tanaka": [("A", "Uncle Fu · 寡言", "custom", "Uncle_Fu", "年迈的老爷爷，话少，声音低沉缓慢，句子之间有停顿。", 0, 1.0),
               ("B", "Uncle Fu 降调重塑", "designed", "Uncle_Fu", "年迈的老爷爷，话少，低沉缓慢。", -1.5, 0.95),
               ("C", "Uncle Fu · 温和", "custom", "Uncle_Fu", "温和、朴实的老爷爷，慢慢地教人做事。", 0, 1.0),
               ("J", "Uncle Fu · 日语", "custom_ja", "Uncle_Fu", "無口な老人、低い声でゆっくり。", 0, 1.0)],
    "aoi": [("A", "Vivian · 小女孩", "custom", "Vivian", "天真活泼的十岁小女孩，声音清脆，语气兴奋。", 0, 1.0),
            ("B", "Vivian 升调重塑", "designed", "Vivian", "天真活泼的小女孩，声音清脆，语气兴奋。", 3.5, 1.04),
            ("C", "Sohee 升调重塑", "designed", "Sohee", "活泼可爱的小女孩，说话很快。", 3.0, 1.03),
            ("J", "Ono Anna 升调 · 日语", "designed_ja", "Ono_Anna", "元気な十歳の女の子。", 3.5, 1.04)],
    "sora": [("A", "Aiden · 沉静", "custom", "Aiden", "平静、带点怀念的年轻男性内心独白，语速缓慢，轻声。", 0, 1.0),
             ("B", "Ryan · 温暖", "custom", "Ryan", "温暖、轻柔的年轻男性，像在回忆往事。", 0, 1.0),
             ("J", "Ryan · 日语", "custom_ja", "Ryan", "静かで懐かしそうな若い男性の独白。", 0, 1.0)],
    "narrator": [("A", "Serena · 讲故事", "custom", "Serena", "平静、温柔的旁白，语速缓慢，像在讲故事。", 0, 1.0),
                 ("B", "Uncle Fu · 老人讲古", "custom", "Uncle_Fu", "温和的老人讲故事，缓慢，有画面感。", 0, 1.0),
                 ("C", "Vivian · 清透", "custom", "Vivian", "清透、安静的女声旁白，像电影开头。", 0, 1.0)],
    "kazuko": [("A", "Vivian · 热心大婶", "custom", "Vivian", "五十多岁的热心大婶，嗓门大，热情爽快。", 0, 1.0),
               ("B", "Serena 降调重塑", "designed", "Serena", "热情爽快的中年大婶，说话很快。", -1.5, 1.0)],
}
REF_ZH = "我今天去河边走了走，风很舒服，花也开得很好。"


def to_np(a):
    return np.array(a, dtype=np.float32).reshape(-1)


def save(path, a):
    wavfile.write(path, SR, a.astype(np.float32))


def shift(src, dst, semis, tempo):
    f = 2 ** (semis / 12.0)
    at = tempo / f
    chain = []
    while at > 2.0:
        chain.append("atempo=2.0"); at /= 2.0
    while at < 0.5:
        chain.append("atempo=0.5"); at /= 0.5
    chain.append(f"atempo={at:.5f}")
    af = f"asetrate={int(SR * f)},aresample={SR}," + ",".join(chain)
    subprocess.run([FF, "-loglevel", "error", "-y", "-i", src, "-af", af, "-ar", str(SR), dst], check=True)


def cer(ref, hyp):
    strip = lambda s: re.sub(r"[\s，。！？、…—\-,.!?「」“”‘’：；:;（）()]", "", s)
    r, h = strip(ref), strip(hyp)
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1]))
            prev, d[j] = d[j], cur
    return d[len(h)] / max(1, len(r))


def main():
    from mlx_audio.tts.utils import load_model
    cv = load_model("mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit")
    base = load_model("mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit")
    only = sys.argv[2].split(",") if len(sys.argv) > 2 else None
    rows = []
    for cid, name, desc, lines in CHARS:
        if only and cid not in only:
            continue
        for vid, label, kind, spk, ins, semis, tempo in CAST[cid]:
            ja = kind.endswith("_ja")
            texts = [JA[cid]] if ja else lines
            lang = "Japanese" if ja else "Chinese"
            files = []
            t0 = time.time()
            if kind.startswith("custom"):
                for k, tx in enumerate(texts):
                    r = list(cv.generate_custom_voice(text=tx, speaker=spk, language=lang, instruct=ins))
                    p = f"{OUT}/{cid}_{vid}_{k}.wav"
                    save(p, np.concatenate([to_np(x.audio) for x in r]))
                    files.append(p)
            else:
                # 1) a CustomVoice take of a neutral reference sentence, 2) shift it, 3) clone it with Base
                ref_text = texts[0] if ja else REF_ZH
                r = list(cv.generate_custom_voice(text=ref_text, speaker=spk, language=lang, instruct=ins))
                raw = f"{OUT}/_ref_{cid}_{vid}_raw.wav"
                save(raw, np.concatenate([to_np(x.audio) for x in r]))
                ref = f"{OUT}/_ref_{cid}_{vid}.wav"
                shift(raw, ref, semis, tempo)
                for k, tx in enumerate(texts):
                    r = list(base.generate(text=tx, ref_audio=ref, ref_text=ref_text, lang_code=lang.lower()))
                    p = f"{OUT}/{cid}_{vid}_{k}.wav"
                    save(p, np.concatenate([to_np(x.audio) for x in r]))
                    files.append(p)
            rows.append({"char": cid, "name": name, "desc": desc, "voice": vid, "label": label, "kind": kind,
                         "speaker": spk, "instruct": ins, "shift_semitones": semis, "tempo": tempo,
                         "language": lang, "texts": texts, "files": [os.path.basename(f) for f in files],
                         "gen_s": round(time.time() - t0, 1)})
            print("done", cid, vid, rows[-1]["gen_s"], flush=True)
            json.dump(rows, open(f"{OUT}/samples.json", "w"), ensure_ascii=False, indent=1)
    del cv, base
    from mlx_audio.stt import load as load_stt
    asr = load_stt("mlx-community/Qwen3-ASR-0.6B-8bit")
    for row in rows:
        row["asr"], row["cer"], row["dur_s"] = [], [], []
        for f, tx in zip(row["files"], row["texts"]):
            res = asr.generate(f"{OUT}/{f}", language=row["language"])
            row["asr"].append(res.text)
            row["cer"].append(round(cer(tx, res.text), 3))
            sr, a = wavfile.read(f"{OUT}/{f}")
            row["dur_s"].append(round(len(a) / sr, 2))
        print("asr", row["char"], row["voice"], row["cer"], flush=True)
    json.dump(rows, open(f"{OUT}/samples.json", "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
