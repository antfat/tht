#!/bin/bash

# === Проверка и установка Java и unzip ===
echo "[INFO] Проверяем наличие Java..."
if ! command -v java &> /dev/null; then
    echo "[INFO] Java не найдена. Устанавливаем default-jdk..."
    apt update
    apt install default-jdk -y
else
    echo "[INFO] Java уже установлена"
fi

echo "[INFO] Проверяем наличие unzip..."
if ! command -v unzip &> /dev/null; then
    echo "[INFO] unzip не найден. Устанавливаем unzip..."
    apt install unzip -y
else
    echo "[INFO] unzip уже установлен"
fi

# === Проверка/создание папки work ===
WORK_DIR="/root/work"
if [ -d "$WORK_DIR" ]; then
    echo "[INFO] Папка $WORK_DIR существует. Очищаем..."
    rm -rf "$WORK_DIR"/*
else
    echo "[INFO] Создаём папку $WORK_DIR..."
    mkdir -p "$WORK_DIR"
fi

cd "$WORK_DIR" || exit

# === Скачивание и подготовка майнера ===
echo "[INFO] Скачиваем майнер..."
wget -q https://tht.mine-n-krush.org/miners/JavaThoughtMinerStratum.zip

echo "[INFO] Распаковываем..."
unzip -o JavaThoughtMinerStratum.zip
rm JavaThoughtMinerStratum.zip

echo "[INFO] Переименовываем JAR в worker.jar..."
mv jtminer-0.8-Stratum-jar-with-dependencies.jar worker.jar

# === Удаляем файл .bat ===
rm mine.bat

# === Создание скрипта запуска процессов на лету ===
LAUNCH_SCRIPT="$WORK_DIR/autostart_multi_worker.sh"
cat > "$LAUNCH_SCRIPT" <<'EOF'
#!/bin/bash

# === Конфигурация ===
JAR_PATH="/root/work/worker.jar"
MEMORY="16G"
USER="3yyyV2CswMqcpYR2AT4LCtyr3R1HvcCGgt"
WORKER_NAME="r040"
FULL_USER="$USER.$WORKER_NAME"
POOL="tht.mine-n-krush.org"
PASS="x"
PORT=5001
THREADS_PER_WORKER=6
LOG_DIR="/root/worker_logs"
RESTART_DELAY=10    # Задержка между перезапусками (сек)

mkdir -p "$LOG_DIR"

# === Определяем количество доступных ядер CPU ===
TOTAL_CORES=$(nproc)

# === Считаем, сколько процессов нужно ===
WORKER_COUNT=$((TOTAL_CORES / THREADS_PER_WORKER))
REMAINING=$((TOTAL_CORES % THREADS_PER_WORKER))
if [ $REMAINING -gt 0 ]; then
    WORKER_COUNT=$((WORKER_COUNT + 1))
fi

# === Функция запуска одного worker ===
start_worker() {
    local id=$1
    local threads=$2
    local log_file="$LOG_DIR/worker_$id.log"

    while :; do
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting worker $id with $threads threads..." | tee -a "$log_file"
        java -Xmx$MEMORY -jar "$JAR_PATH" \
            -u "$FULL_USER" \
            -h "$POOL" \
            -p "$PASS" \
            -t "$threads" \
            -P $PORT >> "$log_file" 2>&1
        EXIT_CODE=$?
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Worker $id stopped (exit code: $EXIT_CODE). Restarting in $RESTART_DELAY seconds..." | tee -a "$log_file"
        sleep $RESTART_DELAY
    done
}

# === Запуск процессов в фоне ===
for ((i=1; i<=$WORKER_COUNT; i++)); do
    if [ $i -eq $WORKER_COUNT ] && [ $REMAINING -gt 0 ]; then
        THREADS=$REMAINING
    else
        THREADS=$THREADS_PER_WORKER
    fi
    start_worker $i $THREADS &
done

wait
EOF

chmod +x "$LAUNCH_SCRIPT"

# === Автоматический запуск сразу же в фоне ===
echo "[INFO] Запускаем worker.jar процессы в фоне..."
nohup "$LAUNCH_SCRIPT" > /dev/null 2>&1 &

echo "[INFO] Все процессы запущены. Логи находятся в /root/worker_logs/"
