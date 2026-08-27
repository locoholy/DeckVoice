# DeckVoice

Voice typing for the Steam Deck. One button: press, talk, press again — the text
lands in whatever field has focus. Built for **KDE Plasma on Wayland**, where the
usual dictation tools do not work.

**English** · [Русский](README.ru.md)

![SteamOS](https://img.shields.io/badge/SteamOS-holo-1a9fff?style=flat-square)
![Wayland](https://img.shields.io/badge/Plasma-Wayland-5ba32b?style=flat-square)
![Whisper](https://img.shields.io/badge/whisper-cloud_+_local-e5a50a?style=flat-square)
![No root](https://img.shields.io/badge/root-not_required-7a8894?style=flat-square)

---

## This is not a Vocalinux fork

Worth being clear about where it came from. [Vocalinux](https://github.com/jatinkrmalik/vocalinux)
was installed first, but **not a line of its code is used here**. Two things were
kept from it: the Python libraries with `pywhispercpp`, and the downloaded
Whisper models. The program itself is original.

That is also why the runtime moved to its own directory,
`~/.local/share/deck-voice/`. The Vocalinux daemon — 223 MB resident — was
dropped from autostart, since it did nothing.

---

## How it works

```
button (F12 / R1)
   ↓
deck-dictation toggle
   ↓
1st press: parecord → rec.wav (16 kHz, mono)
2nd press: SIGINT to the recorder (so the WAV header gets written)
   ↓
key and network? ──yes──→ ffmpeg → flac → Groq whisper-large-v3-turbo
   │                             ↑                     │
   no / no answer ───────────────┘                     │
   ↓                                                   │
python3 + pywhispercpp → whisper small, ru ───────────→┤
   ↓                                                   ↓
Klipper (D-Bus) puts the text on the clipboard
   ↓
ydotool presses Ctrl+V into the focused window
```

**Why Klipper and not `wl-copy`.** SteamOS has no `wl-clipboard` package and a
read-only root. Klipper is Plasma's own clipboard, already running in the
session, and does the same job:

```bash
qdbus6 org.kde.klipper /klipper setClipboardContents "text"
```

This was the reason for the old “it transcribes but never pastes” bug: `wl-copy`
did not exist, the text never reached the clipboard, and Ctrl+V pasted whatever
had been there before.

**Why the `small` model and not `tiny`.** On Russian, `tiny` hallucinates —
“subtitle editor”, “to be continued”, “applause”: leftovers from training on
YouTube subtitles. `small` (466 MB) is far more accurate. A filter for those
phrases is still in the code, just in case.

---

## Install

```bash
./install.sh      # no sudo
./selftest.sh     # checks everything
```

Bind the hotkey in *System Settings → Shortcuts* to “🎤 Голос”.

The runtime (models and libraries, ~760 MB) is not in the repository; it lives
in `~/.local/share/deck-voice/`.

---

## Configuration

`~/.config/deck-voice/config`, sourced as bash. What is worth touching:

| Setting | Meaning |
|---|---|
| `MODEL` | path to the model; `tiny` is faster but unreliable |
| `LANGUAGE` | recognition language |
| `THREADS` | whisper threads; the Deck has 4 cores, more does not help |
| `MIC_BOOST` | microphone gain, 130% by default; higher clips |
| `REC_LATENCY_MS` | recorder buffer; larger loses the tail of the phrase |
| `PASTE_KEY` | `ctrl-v`, `ctrl-shift-v` or `none` |
| `MIN_PEAK`, `MIN_DURATION` | silence and too-short-press cutoffs |
| `FEEDBACK_SOUND`, `FEEDBACK_OSD`, `FEEDBACK_POPUP` | three feedback layers, see below |
| `SOUND_VOLUME` | signal volume, % |

Every key with comments is in `config/deck-voice.conf.example`.

---

## Recognition engine

Local whisper on the Deck's CPU bottoms out at ~9 seconds, and no small change
fixes that: measured, loading the model takes ~0.9 s and the remaining eight are
the transcription itself. Shrinking the model is not the answer — `tiny` finishes
in 1.4 s but confuses words. So the cloud is now the main path and local is the
fallback.

```
ENGINE=auto     cloud when there is a key and a network; local otherwise
ENGINE=cloud    cloud only
ENGINE=local    local only, the recording never leaves the device
```

**Why Groq.** `whisper-large-v3-turbo` is a *larger* model than the local
`small`, so accuracy goes up rather than down, and it runs on their hardware in
a fraction of a second. The endpoint is OpenAI-compatible, so `CLOUD_URL` and
`CLOUD_MODEL` also accept OpenAI, Mistral Voxtral or a local `whisper-server` —
the code stays the same.

**Punctuation rests on the prompt.** Without a `prompt` parameter, speech
without pauses comes back as one lowercase run-on. Same recording, both ways:

```
no prompt:   да бля чё то пока что пунктуации нет у меня до сих пор а чё
with prompt: Да бля, чё-то пока что пунктуации нет у меня до сих пор. А чё,
```

The prompt is a sample, not an instruction: whisper simply continues in the
style it was given. The flip side is that on a near-silent recording it returns
the prompt itself as if it had been transcribed. So silence is cut *before* the
request, and the response is checked for that echo. The comparison lowercases
with `sed \L`, not `tr` — `tr` works byte-wise, leaves Cyrillic untouched, and
the check silently missed.

**What leaves the device.** The recording itself, compressed to FLAC — lossless
and about half the size of WAV. Silence and accidental taps are discarded
*before* the request: the peak level comes from the same `ffmpeg` call that does
the compression, so the check is free. If you would rather nothing left the
device at all, set `ENGINE="local"` and it works as it always did.

**Fallback.** Any cloud failure — no key, no network, timeout, 401, 429 — is
logged and quietly handed to local whisper. You never end up without text; you
occasionally wait nine seconds instead of one and a half. The overlay says which
engine answered: `☁` cloud, `💻` local, `💻↩` cloud timed out and local covered.

**The key** lives in its own file rather than in the config, so it cannot leak
along with it:

```bash
mkdir -p ~/.config/deck-voice
echo 'gsk_...' > ~/.config/deck-voice/cloud.key
chmod 600 ~/.config/deck-voice/cloud.key
deck-dictation cloud-test     # check that it is accepted
```

A free key: <https://console.groq.com/keys>

---

## Tray icon

A notification is a poor mode indicator: it shouts, covers the window, and
disappears anyway. “Recording” is a *mode*, and modes belong where volume and
Wi-Fi live. So the state is shown by a tray icon:

| Icon | State |
|---|---|
| microphone | idle |
| red dot | recording |
| refresh arrows | transcribing |

Left click does what the hotkey does — start and stop. Right click opens a menu:
engine (auto / cloud only / local only), a cloud check, settings. The tooltip
shows the current engine and which one handled the last dictation.

While the icon is running, recording popups **do not appear at all** — two
indicators for one thing would be noise. Close the icon and the popups come
back: without an indicator, nothing else would report the mode.

**How it is done.** SteamOS has neither PyQt nor AppIndicator, so the icon
registers itself directly over D-Bus as a `StatusNotifierItem`, and the menu is
served through `com.canonical.dbusmenu` — Plasma supports both natively. The
only dependency is `python-gobject`, which is already present.

Two traps worth not stepping into twice:

- **`dbus-python` cannot serve the menu.** `GetLayout` must return an array of
  variants containing structures (`av`), which dbus-python does not marshal at
  all — it guesses types and fails with “Expected a string”. Hence Gio: with
  `GVariant`, signatures are stated explicitly.
- **Properties via `register_object` callbacks silently do not work in
  PyGObject** — methods get called, but any property request fails with “Unable
  to retrieve property”. So `org.freedesktop.DBus.Properties` is implemented
  here by hand, as ordinary methods.

The daemon transcribes nothing itself: it reads state files and calls
`deck-dictation toggle`. If it dies, voice typing keeps working from the hotkey
— the icon is a convenience, not a critical part.

---

## Feedback

Dictation used to leave three notifications behind, and they never went away.
The cause was not a timeout but a single flag: `notify-send -u critical`. By the
freedesktop spec, a notification with `urgency=critical` **never expires** —
`-t` is silently ignored and Plasma holds the popup until it is dismissed by
hand. Three calls per cycle (LISTENING → Processing → Pasted) meant three
permanent popups, on every single press.

There are now three independent layers, fastest to most visible:

| Layer | What it is | When |
|---|---|---|
| tray icon | mode: idle / recording / transcribing | while it runs, recording popups are suppressed |
| sound | a short signal | confirms **the press itself** — it fires before anything can be drawn |
| overlay | the same OSD that shows volume (`org.kde.osdService`) | the result: text and elapsed time. Fades on its own in ~1.8 s |
| popup | an ordinary notification, **exactly one per cycle** | only while work is happening: “Listening” → “Transcribing” |

What actually changed:

- **`urgency` is now `low`/`normal`** — popups obey their timeout again.
- **The popup is rewritten, not multiplied.** `notify-send -p` returns an id,
  it goes into `$XDG_RUNTIME_DIR/deck-voice/notify.id`, and the next call passes
  `-r <id>`. There is always one popup on screen, changing its text in place.
- **The popup is closed programmatically** through `CloseNotification` instead
  of waiting out a timeout. The text appears in the field, the popup goes away
  at that same moment.
- **`transient:true` hint** — notifications no longer pile up in the history.
- **The result is shown by the overlay, not a popup.** The pasted text is
  already visible in the field; keeping it on screen twice is pointless.
- **Own sounds instead of the system set.** The stock KDE sounds do not fit on
  the merits: `Oxygen-Sys-App-Message` runs 1.3 s, `List-End` and `Positive`
  2.1 s each. The sound is still going when everything has long since happened.
  Ours are 92–168 ms: near-pure sines, soft attack, exponential decay. A fifth
  up for “started listening”, the same fifth down for “done” — the direction
  reads without words. They are generated by `bin/deck-voice-sounds`; the
  repository holds the recipe, not the audio, so there are no licensing
  questions, no blobs in history, and pitch or length is one number away.
- **No emoji.** In the system overlay they look foreign and render differently
  across themes. The engine is shown with a stock theme icon instead: a cloud
  for cloud, a chip for local.
- **Insurance against stuck popups.** The working popup gets `WORK_TIMEOUT_MS`
  (3 minutes), and the next run's first act is to kill the previous run's popup
  — so if the script is killed mid-transcription, nothing is left behind.

The layers switch independently. Fully silent: `FEEDBACK_SOUND=0`. No popups,
keeping the sound and the fading overlay: `FEEDBACK_POPUP=0`. `NOTIFY=0` turns
off everything.

---

## Debugging

```bash
deck-dictation status         # what is installed, what runs
deck-dictation logs           # log of the last run
deck-dictation speed          # how long each dictation took
deck-dictation cloud-test     # check the key and the cloud connection
./bin/deck-voice-soundroom    # audition the system sound themes and pick one
deck-dictation test           # check that the model loads
./selftest.sh                 # full environment check
```

Verbose log:

```bash
DECKVOICE_DEBUG=1 deck-dictation
```

Logs go to `~/.local/state/deck-voice/`, a new one per recording, last 5 kept.
Each phase is timed:

```
11:42:03.418 [TIME] whisper: 4212 ms
11:42:03.605 [TIME] paste: 187 ms
11:42:03.607 [TIME] total: 4735 ms
```

The time is also visible without logs: the overlay shows it next to the text
(“…transcribed text · 8.4 s”), and `deck-dictation speed` summarises the history
across all kept logs.

---

## Known rough edges

- **The end of every phrase was cut off — fixed.** By default `parecord` buffers
  about a second of audio and loses it when told to stop: only the WAV header
  was written. Measured: two seconds out of three made it into the file, and
  phrases shorter than two seconds vanished completely (a 44-byte file — the
  header alone). The fix is `--latency-msec=30`: loss dropped to 0.09 s and
  stopped depending on phrase length. The symptom looked like “the microphone
  cannot hear quiet speech”, though gain had nothing to do with it.
- **It will not paste into a terminal.** Konsole does not take Ctrl+V, it wants
  Ctrl+Shift+V. `PASTE_KEY="ctrl-shift-v"` works around it but then breaks
  pasting into ordinary fields. The proper fix is detecting the focused window
  class.
- **Microphone gain above 130% breaks recognition.** A test at 180% clipped
  (`peak=1.0000`) on two recordings out of six and the text drifted: on one
  phrase the normal level produced nine sentences with full stops, the
  overdriven one a single run-on with commas, and a word went missing. Volume
  does not help here, it hurts.
- **Slow: ~9 seconds from “stop” to text (local engine).** Measured on this
  Deck: model load ~0.9 s, everything else is the transcription. So a resident
  process holding the model in memory would save under a second out of nine —
  not the real bottleneck. The real one is model size: on the same recording
  `small` takes 8.4 s and gets it right, `tiny` takes 1.4 s and confuses words.
  Hence `small`. If more speed is needed without losing meaning, the thing to
  try is a quantised `ggml-small-q5_1.bin` (~180 MB), not `tiny`.
- **No GUI fallback.** Speech Note was removed — 3.9 GB and unused. If a GUI
  recogniser is ever wanted: `flatpak install flathub net.mkiol.SpeechNote`

## Next

- [ ] Detect the focused window → pick the right paste combination
- [ ] Quantised `small-q5_1` — faster transcription without losing accuracy
- [ ] Resident process with the model preloaded (saves ~0.9 s)
- [x] Stop notifications from sticking — done, see “Feedback”
- [ ] Automatic punctuation and capitalisation

---

## One thing that is easy to trip over

A KDE shortcut binds **to the name of the desktop file**, not to the command.
On this machine the F12 binding historically sits on
`deck-dictation-toggle.desktop`, so the file kept its old name even though its
contents are new. Rename it and the shortcut is lost, to be assigned again by
hand.

`install.sh` accounts for this: if `kglobalshortcutsrc` already has a binding
for the old name, it writes the entry into that file rather than creating a
second one.

## License

MIT — see [LICENSE](LICENSE).
