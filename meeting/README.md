# meeting

Record a meeting from both your microphone and the system audio output, then
transcribe it locally with whisper.cpp into one chronological, speaker-labeled
transcript.

The two sources are captured as separate channels — your mic on the left,
system audio (remote participants) on the right — so the transcript can label
who said what. Most of the time `[MIC]` is you and `[SYS]` is everyone else.
When you join a meeting from another device (your phone, say), one channel is
silent and that recording is transcribed unlabeled.

## Usage

```
meeting record                              Record until Ctrl-C, then transcribe.
meeting transcribe [--split] <file> [model] Transcribe an existing recording.
meeting help                                Show usage.
```

`meeting record` captures both sources, packs them into one stereo WAV, and
offers to transcribe immediately. `meeting transcribe --split` is what it calls
under the hood; run it yourself to re-transcribe an old recording or to try a
different model. Models: tiny, base, small, medium (default), large.

## Output

`<basename>.txt` in the current working directory. Split transcripts are
labeled `[MIC]` / `[SYS]` and interleaved in time order.

## How hallucinations are kept out

An open-but-idle mic channel is mostly silence, and whisper invents filler text
("Okay. Okay.") and locks into repetition loops on near-silent audio. Three
whisper settings prevent this: VAD (voice activity detection) strips non-speech
before decoding, `-mc 0` disables prior-text conditioning so it can't loop, and
`-sns` suppresses non-speech tokens like `[ Silence ]`. The VAD model is
downloaded by `install.sh`.

## Dependencies

Build-time (compiling whisper.cpp): `git`, `cmake`, `g++` or `clang++`.
Runtime: `ffmpeg` (audio handling), `pw-record` (recording, from PipeWire),
and whisper.cpp (built by `install.sh`).

### Install dependencies (Debian)

```
sudo apt install -y git cmake g++ ffmpeg pipewire pipewire-bin wireplumber
```

## Install

```
./install.sh [model_size]
```

Clones and builds whisper.cpp, downloads the transcription model and the silero
VAD model, and installs `meeting` to `~/bin/`. Re-run with a different model
size to add more models.

> **Disk note:** the `medium` model is ~1.5 GB and the build adds a few hundred
> MB more. Make sure the target has a couple of GB free before installing.

## Uninstall

```
./uninstall.sh
```

Removes `~/bin/meeting`, then asks whether to also delete the built
`whisper.cpp/` tree and downloaded models (~2 GB; kept by default, since
rebuilding and redownloading are slow). The shared `~/bin` PATH entry in
`.bashrc` is left alone.
