#!/bin/bash
# Установка DeckVoice. sudo не нужен — всё в домашнем каталоге.
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
RUNTIME="$HOME/.local/share/deck-voice"

echo "Ставлю из $SRC"

mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications" "$HOME/.config/deck-voice"

ln -sf "$SRC/bin/deck-dictation" "$HOME/.local/bin/deck-dictation"
echo "  запуск:   ~/.local/bin/deck-dictation"

# К имени файла ярлыка привязывается горячая клавиша KDE. Если привязка уже
# есть на старом имени — пишем в него, иначе потеряется сочетание клавиш.
DESKTOP_NAME="deck-voice-toggle.desktop"
if grep -q "deck-dictation-toggle.desktop" "$HOME/.config/kglobalshortcutsrc" 2>/dev/null; then
    DESKTOP_NAME="deck-dictation-toggle.desktop"
fi
sed "s|Exec=.*|Exec=$SRC/bin/deck-dictation|" "$SRC/desktop/deck-voice-toggle.desktop" \
  > "$HOME/.local/share/applications/$DESKTOP_NAME"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo "  ярлык:    ~/.local/share/applications/$DESKTOP_NAME"

if [ ! -f "$HOME/.config/deck-voice/config" ]; then
    cp "$SRC/config/deck-voice.conf.example" "$HOME/.config/deck-voice/config"
    echo "  конфиг:   ~/.config/deck-voice/config (из примера)"
fi

# Звуковая тема. Генерируется, а не лежит в репозитории: чужие звуки тянут
# лицензии, а штатные звуки KDE длятся 1,3–2,1 с — для отклика это вечность.
if command -v ffmpeg >/dev/null 2>&1; then
    "$SRC/bin/deck-voice-sounds" >/dev/null 2>&1 \
      && echo "  звуки:    собраны в $RUNTIME/sounds" \
      || echo "  звуки:    собрать не вышло, останутся системные"
else
    echo "  звуки:    нет ffmpeg, останутся системные"
fi

# Значок в лотке. Ставим в автозапуск сеанса, а не в systemd: ему нужны
# и D-Bus сеанса, и уже поднятая оболочка Plasma, а фаза 2 как раз про это.
mkdir -p "$HOME/.config/autostart"
sed "s|Exec=.*|Exec=$SRC/bin/deck-voice-tray|" "$SRC/desktop/deck-voice-tray.desktop" \
  > "$HOME/.config/autostart/deck-voice-tray.desktop"
echo "  значок:   автозапуск включён"
if ! pgrep -f "bin/deck-voice-tray" >/dev/null 2>&1; then
    setsid "$SRC/bin/deck-voice-tray" >/dev/null 2>&1 < /dev/null &
    echo "            запущен сейчас"
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

# Ключ облака держим отдельно от конфига и с правами 600: конфиг не жалко
# показать или закоммитить, ключ — жалко.
KEYF="$HOME/.config/deck-voice/cloud.key"
if [ -f "$KEYF" ]; then
    chmod 600 "$KEYF"
    echo "  ключ:     $KEYF (права 600)"
else
    echo
    echo "Облачный движок выключен — ключа нет, работает локальный whisper (~9 с)."
    echo "  Чтобы включить быстрый режим (~1,5 с и точнее):"
    echo "    1. взять бесплатный ключ на https://console.groq.com/keys"
    echo "    2. echo 'gsk_...' > $KEYF && chmod 600 $KEYF"
    echo "    3. $SRC/bin/deck-dictation cloud-test"
fi

echo
echo "Готово. Проверка:  $SRC/selftest.sh"
echo "Горячую клавишу назначь в Параметры системы → Горячие клавиши → «🎤 Голос»"
