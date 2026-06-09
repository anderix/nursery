# diarize

**Experimental.** A test harness for speaker diarization — labeling *who* spoke,
not just what was said. It exists to answer one question before any of this goes
near the `meeting` tool: **is sherpa-onnx diarization good enough on real meeting
audio?** Until that's proven, this stays a standalone sibling tool.

It transcribes a single audio stream with whisper and, in parallel, runs
[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) speaker diarization, then
aligns the two timelines so every transcript line gets an anonymous speaker tag:

```
[SPEAKER_00] So where did we land on the timeline?
[SPEAKER_01] I think we said end of the month.
[SPEAKER_00] Right, end of the month.
```

It does **not** identify people by name, and it makes **no** assumption about who
is on which channel. Speakers are anonymous clusters; naming is a later phase.

## Why sherpa-onnx (not pyannote)

Same diarization quality, but pure C++/ONNX — no pip, no PyTorch, no HuggingFace
token. The installer pulls a prebuilt static binary and two small ONNX models
(tens of MB, not gigabytes).

## Dependencies

`curl`, `tar`, `ffmpeg`, and a built whisper — which it **reuses from the sibling
`meeting` tool**. Install and build that first:

```
../meeting/install.sh
```

## Install

```
./install.sh
```

Downloads the prebuilt static sherpa-onnx binary (resolved from the latest
GitHub release), the pyannote segmentation model, and an English speaker-
embedding model, then installs `diarize` to `~/bin/`.

> If a model download 404s, the release asset was renamed. Check the
> [sherpa-onnx releases](https://github.com/k2-fsa/sherpa-onnx/releases) and set
> `SEG_TARBALL_URL` / `EMB_MODEL_URL` when re-running `install.sh`.

## Usage

```
diarize [--speakers N] [--channel mic|sys|mix] <audio_file> [model_size]
```

- `--speakers N` — number of distinct speakers. **Strongly recommended**: blind
  clustering frequently miscounts. Give it whenever you know the truth.
- `--channel mic|sys|mix` — which part of the audio to analyze (default `mix`).
  `mic` = left, `sys` = right, `mix` = downmix to mono. Use `sys` to test a past
  call's remote participants — the most natural multi-speaker single channel you
  already have.
- `model_size` — whisper model (default `medium`), reused from `meeting`.

Output: `<basename>.diarized.txt` in the current directory.

Example — test the remote side of a past call you know had three people:

```
diarize --speakers 3 --channel sys 2026-06-01_1304_meeting.wav
```

## Known limitations (it's a proof of concept)

Alignment is coarse: each whisper line is tagged with whichever speaker was
active at the line's **start time**. A speaker change mid-line is missed. Doing
it properly needs word-level timestamps from whisper — deferred until/unless
diarization quality justifies it. The sherpa CLI flags and output format target
current sherpa-onnx; the tool echoes the exact command it runs and preserves raw
sherpa output on a parse failure, so drift is easy to spot.

## Uninstall

```
./uninstall.sh
```

Removes `~/bin/diarize`, then asks whether to delete the downloaded sherpa-onnx
binary and models. The reused whisper build (owned by `meeting`) and the shared
`~/bin` PATH entry are left alone.
