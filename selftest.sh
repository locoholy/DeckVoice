#!/bin/bash
# Самопроверка DeckVoice. Ничего не меняет, sudo не нужен.
G='\033[32m'; R='\033[31m'; Y='\033[33m'; N='\033[0m'
ok(){ echo -e "  ${G}OK${N}   $1"; }
bad(){ echo -e "  ${R}FAIL${N} $1"; F=$((F+1)); }
warn(){ echo -e "  ${Y}--${N}   $1"; }
F=0
RUNTIME="$HOME/.local/share/deck-voice"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo
echo "=== 1. Рантайм ==="
if [ -f "$RUNTIME/models/ggml-small.bin" ]; then
    ok "модель small на месте ($(du -h "$RUNTIME/models/ggml-small.bin" | cut -f1))"
else
    bad "нет $RUNTIME/models/ggml-small.bin"
fi
[ -d "$RUNTIME/pylib" ] && ok "python-библиотеки ($(du -sh "$RUNTIME/pylib" | cut -f1))" || bad "нет $RUNTIME/pylib"

echo
echo "=== 2. Python и whisper ==="
if PYTHONPATH="$RUNTIME/pylib" /usr/bin/python3 -c "import numpy, pywhispercpp" 2>/dev/null; then
    ok "pywhispercpp и numpy импортируются"
else
    bad "импорт не проходит → PYTHONPATH=$RUNTIME/pylib python3 -c 'import pywhispercpp'"
fi

echo
echo "=== 3. Вставка текста ==="
if pgrep -x ydotoold >/dev/null; then ok "ydotoold работает"; else bad "ydotoold не запущен → systemctl --user start ydotoold"; fi
[ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/.ydotool_socket" ] && ok "сокет ydotool на месте" || bad "нет сокета ydotool"
[ -x "$HOME/.local/bin/ydotool" ] && ok "клиент ydotool на месте" || bad "нет ~/.local/bin/ydotool"

if qdbus6 org.kde.klipper /klipper getClipboardContents >/dev/null 2>&1 \
   || qdbus org.kde.klipper /klipper getClipboardContents >/dev/null 2>&1; then
    ok "Klipper отвечает (это замена wl-copy, его в SteamOS нет)"
else
    bad "Klipper не отвечает — текст будет некуда положить"
fi

echo
echo "=== 4. Обратная связь ==="
if qdbus6 org.kde.plasmashell /org/kde/osdService showText "audio-input-microphone" "DeckVoice: самопроверка" 2>/dev/null \
   || qdbus org.kde.plasmashell /org/kde/osdService showText "audio-input-microphone" "DeckVoice: самопроверка" 2>/dev/null; then
    ok "оверлей Plasma работает — сейчас мелькнул по центру экрана"
else
    warn "оверлей Plasma недоступен, останутся звук и уведомление"
fi

SRV=$(gdbus call --session --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.GetServerInformation 2>/dev/null)
[ -n "$SRV" ] && ok "сервер уведомлений отвечает" || bad "сервер уведомлений не отвечает"

# notify-send без -p не даст переписывать попап, и они снова начнут копиться
notify-send --help 2>&1 | grep -q -- "--print-id" \
    && ok "notify-send умеет replace-id (попапы не будут копиться)" \
    || bad "notify-send без --print-id — обнови libnotify"

MISS=0
for f in listen-start listen-stop done oops; do
    [ -r "$RUNTIME/sounds/$f.ogg" ] || MISS=$((MISS+1))
done
if [ "$MISS" -eq 0 ]; then
    ok "своя звуковая тема на месте (короткие сигналы)"
else
    warn "нет $MISS из 4 своих звуков → $HERE/bin/deck-voice-sounds"
fi
command -v paplay >/dev/null && ok "paplay есть" || warn "нет paplay — сигналов не будет"

# Наследие: критические уведомления по спеке не гаснут никогда
# Комментарии отбрасываем: в коде есть пояснение про этот самый баг
if grep -v '^[[:space:]]*#' "$HERE/bin/deck-dictation" 2>/dev/null | grep -q -- "-u critical"; then
    bad "в коде остался notify-send -u critical — такие попапы не гаснут сами"
fi

echo
echo "=== 5. Движок распознавания ==="
KEYF="$HOME/.config/deck-voice/cloud.key"
if [ -r "$KEYF" ] || [ -n "${DECKVOICE_CLOUD_KEY:-}" ]; then
    ok "ключ облака на месте"
    if [ -r "$KEYF" ]; then
        PERM=$(stat -c%a "$KEYF")
        [ "$PERM" = "600" ] && ok "права на ключ 600" \
            || warn "права на ключ $PERM — стоит chmod 600 $KEYF"
    fi
    if "$HERE/bin/deck-dictation" cloud-test >/dev/null 2>&1; then
        ok "облако отвечает (deck-dictation cloud-test — подробности)"
    else
        bad "облако не отвечает → deck-dictation cloud-test"
    fi
else
    warn "ключа облака нет — работает только локальный whisper (~9 с)"
fi
command -v ffmpeg >/dev/null && ok "ffmpeg есть (сжатие в flac перед отправкой)" \
    || bad "нет ffmpeg — облачный путь не соберёт запрос"
[ -f "$RUNTIME/models/ggml-small.bin" ] && ok "локальный запас на месте" \
    || warn "локальной модели нет — без сети работать будет нечему"

echo
echo "=== 6. Значок в лотке ==="
if pgrep -f "bin/deck-voice-tray" >/dev/null 2>&1; then
    ok "значок запущен (индикатор режима вместо всплывашек)"
    python3 -c "import gi; from gi.repository import Gio, GLib" 2>/dev/null \
        && ok "python-gobject на месте" || bad "нет python-gobject — значок не поднимется"
else
    warn "значок не запущен → $HERE/bin/deck-voice-tray &"
fi
[ -f "$HOME/.config/autostart/deck-voice-tray.desktop" ] \
    && ok "значок в автозапуске" || warn "значка нет в автозапуске → ./install.sh"

echo
echo "=== 7. Микрофон ==="
S=$(pactl get-default-source 2>/dev/null)
[ -n "$S" ] && ok "источник: $S" || bad "источник по умолчанию не определён"
command -v parecord >/dev/null && ok "parecord есть" || warn "parecord нет, будет pw-record"

echo
echo "=== 8. Установка ==="
[ -x "$HOME/.local/bin/deck-dictation" ] && ok "команда deck-dictation доступна" || bad "не установлено → ./install.sh"
DESK=$(ls "$HOME/.local/share/applications/" 2>/dev/null | grep -E "^deck-(voice|dictation)-toggle\\.desktop$" | head -1)
if [ -n "$DESK" ]; then ok "ярлык на месте: $DESK"; else warn "ярлыка нет"; fi
[ -f "$HOME/.config/deck-voice/config" ] && ok "конфиг: ~/.config/deck-voice/config" || warn "конфига нет, работают умолчания"

if grep -q "deck-voice-toggle.desktop\|deck-dictation" "$HOME/.config/kglobalshortcutsrc" 2>/dev/null; then
    ok "горячая клавиша назначена"
else
    warn "горячая клавиша не назначена — Параметры системы → Горячие клавиши"
fi

echo
echo "=== 9. Чтобы не мешало ==="
for junk in vocalinux.desktop voice-type.desktop; do
    if [ -f "$HOME/.config/autostart/$junk" ]; then
        bad "$junk всё ещё в автозапуске — лишний процесс"
    else
        ok "$junk из автозапуска убран"
    fi
done

echo
echo "=== 10. Последний запуск ==="
L="$HOME/.local/state/deck-voice/current.log"
if [ -f "$L" ]; then
    grep -E "TIME|ERROR|распознано" "$L" | tail -6 | sed 's/^/       /'
else
    warn "логов ещё нет — нажми кнопку и продиктуй что-нибудь"
fi

echo
[ "$F" -eq 0 ] && echo -e "${G}Всё в порядке.${N}" || echo -e "${R}Проблем: $F${N}"
echo
