#!/bin/bash
# Установка DeckVoice. sudo не нужен — всё в домашнем каталоге.
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
RUNTIME="$HOME/.local/share/deck-voice"

echo "Ставлю из $SRC"

mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications" "$HOME/.config/deck-voice"

ln -sf "$SRC/bin/deck-dictation" "$HOME/.local/bin/deck-dictation"
echo "  запуск:   ~/.local/bin/deck-dictation"

sed "s|Exec=.*|Exec=$SRC/bin/deck-dictation|" "$SRC/desktop/deck-voice-toggle.desktop" \
  > "$HOME/.local/share/applications/deck-voice-toggle.desktop"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo "  ярлык:    ~/.local/share/applications/deck-voice-toggle.desktop"

if [ ! -f "$HOME/.config/deck-voice/config" ]; then
    cp "$SRC/config/deck-voice.conf.example" "$HOME/.config/deck-voice/config"
    echo "  конфиг:   ~/.config/deck-voice/config (из примера)"
fi

mkdir -p "$HOME/.config/systemd/user"
cp -n "$SRC/systemd/ydotoold.service" "$HOME/.config/systemd/user/" 2>/dev/null || true
systemctl --user daemon-reload
systemctl --user enable --now ydotoold.service 2>/dev/null || true
echo "  ydotoold: $(systemctl --user is-active ydotoold.service)"

echo
if [ -f "$RUNTIME/models/ggml-small.bin" ] && [ -d "$RUNTIME/pylib" ]; then
    echo "Рантайм на месте: $RUNTIME"
else
    echo "ВНИМАНИЕ: нет рантайма в $RUNTIME"
    echo "  нужны: models/ggml-small.bin и pylib/ (python-библиотеки с pywhispercpp)"
fi

echo
echo "Готово. Проверка:  $SRC/selftest.sh"
echo "Горячую клавишу назначь в Параметры системы → Горячие клавиши → «🎤 Голос»"
