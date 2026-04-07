# transcribe

Local speech-to-text transcription using whisper.cpp. Accepts any audio or video format that ffmpeg can handle and outputs a text file.

## Usage

```
transcribe <audio_file> [model_size]
```

Models: tiny, base, small, medium (default), large. Larger models are slower but more accurate.

## Output

`<input_basename>.txt` in the current working directory.

## Dependencies

Build-time (for compiling whisper.cpp):

- `git`
- `g++` or `clang++`
- `make`

Runtime:

- `ffmpeg` (audio format conversion)
- whisper.cpp (cloned and built by install.sh)

### Install dependencies (Debian)

```
sudo apt install -y git g++ make ffmpeg
```

## Install

```
./install.sh [model_size]
```

Clones whisper.cpp, builds it, downloads the specified model, and installs `transcribe` to `~/bin/`. Run it again with a different model size to add more models.
