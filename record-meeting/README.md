# record-meeting

Captures system audio (speakers/headphone output) during a meeting using PipeWire. Produces a 16kHz mono WAV file ready for whisper transcription.

## Usage

```
record-meeting
```

Press Ctrl-C to stop. The recording is saved to the current working directory with a timestamped filename.

## Output

`YYYY-MM-DD_HHMM_meeting.wav` (in the current directory)

## Dependencies

- `pw-record` (part of `pipewire-utils` or `pipewire` package)
- PipeWire running as the audio server with a monitor source available

### Install dependencies (Debian/Ubuntu)

```
sudo apt install -y pipewire pipewire-utils
```

## Install

```
./install.sh
```

Copies `record-meeting` to `~/bin/`.
