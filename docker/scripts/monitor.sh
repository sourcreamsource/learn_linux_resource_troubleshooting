#!/usr/bin/env bash

# 정의되지 않은 변수를 사용하면 바로 오류로 멈춘다.
set -u

# 감시할 앱 이름을 변수에 저장한다.
APP_NAME="agent-app-leak"

# AGENT_PORT 환경변수가 있으면 그 값을 쓰고, 없으면 15034를 기본값으로 쓴다.
APP_PORT="${AGENT_PORT:-15034}"

# AGENT_LOG_DIR 환경변수가 있으면 그 값을 쓰고, 없으면 /var/log/agent-app을 기본값으로 쓴다.
LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"

# 관제 결과를 저장할 로그 파일 경로를 만든다.
LOG_FILE="$LOG_DIR/monitor.log"

# monitor.log가 10MB 이상 커지면 회전시키기 위해 최대 크기를 byte 단위로 정한다.
MAX_LOG_SIZE=$((10 * 1024 * 1024))

# monitor.log.1부터 monitor.log.10까지 최대 10개 백업 파일을 유지한다.
MAX_LOG_FILES=10

# 화면에 한 줄을 출력하는 공통 함수를 만든다.
print_line() {
    # 함수에 들어온 첫 번째 값을 그대로 출력한다.
    echo "$1"
}

# 로그 파일이 너무 커졌을 때 오래된 로그로 넘기는 함수를 만든다.
rotate_log_if_needed() {
    # 로그 파일이 아직 없으면 회전할 대상이 없으므로 함수를 끝낸다.
    if [ ! -f "$LOG_FILE" ]; then
        # 정상 종료를 의미하는 0을 반환한다.
        return 0
    fi

    # 파일 크기를 담을 지역 변수를 선언한다.
    local size

    # stat -c %s로 로그 파일 크기를 byte 단위 숫자로 구한다.
    size=$(stat -c %s "$LOG_FILE")

    # 로그 파일이 최대 크기보다 작으면 회전하지 않고 끝낸다.
    if [ "$size" -lt "$MAX_LOG_SIZE" ]; then
        # 정상 종료를 의미하는 0을 반환한다.
        return 0
    fi

    # 가장 오래된 백업 로그 파일을 삭제한다.
    rm -f "$LOG_FILE.$MAX_LOG_FILES"

    # 백업 번호를 뒤로 밀기 위한 반복 변수 i를 선언한다.
    local i

    # 가장 끝 번호 바로 앞부터 시작한다.
    i=$((MAX_LOG_FILES - 1))

    # i가 1 이상인 동안 반복한다.
    while [ "$i" -ge 1 ]; do
        # 현재 번호의 백업 파일이 있으면 다음 번호로 이름을 바꾼다.
        if [ -f "$LOG_FILE.$i" ]; then
            # 예: monitor.log.1을 monitor.log.2로 이동한다.
            mv "$LOG_FILE.$i" "$LOG_FILE.$((i + 1))"
        fi

        # 다음 반복을 위해 i 값을 1 줄인다.
        i=$((i - 1))
    done

    # 현재 monitor.log를 monitor.log.1로 이동한다.
    mv "$LOG_FILE" "$LOG_FILE.1"

    # 새 monitor.log 빈 파일을 만든다.
    touch "$LOG_FILE"
}

# agent-app-leak 프로세스 PID를 찾는 함수를 만든다.
find_app_pid() {
    # pgrep -x로 프로세스 이름이 APP_NAME과 정확히 일치하는 PID만 찾는다.
    pgrep -x "$APP_NAME" |
        # Rosetta 환경 등에서 래퍼 프로세스가 같이 뜨는 경우를 고려해 가장 마지막 PID를 사용한다.
        tail -n 1
}

# 방화벽 상태를 확인하는 함수를 만든다.
check_firewall() {
    # ufw 명령어가 있는지 확인한다.
    if command -v ufw >/dev/null 2>&1; then
        # ufw가 active 상태인지 확인한다.
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            # UFW가 켜져 있으면 OK를 출력한다.
            print_line "Firewall UFW... [OK]"
        else
            # UFW가 꺼져 있으면 WARNING을 출력한다.
            print_line "Firewall UFW... [WARNING] inactive"
        fi

        # UFW 확인을 마쳤으므로 함수를 끝낸다.
        return 0
    fi

    # firewall-cmd 명령어가 있는지 확인한다.
    if command -v firewall-cmd >/dev/null 2>&1; then
        # firewalld가 running 상태인지 확인한다.
        if firewall-cmd --state 2>/dev/null | grep -q "running"; then
            # firewalld가 켜져 있으면 OK를 출력한다.
            print_line "Firewall firewalld... [OK]"
        else
            # firewalld가 꺼져 있으면 WARNING을 출력한다.
            print_line "Firewall firewalld... [WARNING] inactive"
        fi

        # firewalld 확인을 마쳤으므로 함수를 끝낸다.
        return 0
    fi

    # UFW와 firewalld가 모두 없으면 방화벽 도구가 없다는 경고를 출력한다.
    print_line "Firewall... [WARNING] ufw/firewalld not found"
}

# 시스템 전체 CPU 사용률을 구하는 함수를 만든다.
get_system_cpu_usage() {
    # top을 한 번 실행하고 idle 값을 빼서 CPU 사용률을 계산한다.
    top -bn1 | awk -F',' '/Cpu/ {
        idle=$4
        gsub(/[^0-9.]/, "", idle)
        printf "%.1f", 100 - idle
    }'
}

# 시스템 전체 메모리 사용률을 구하는 함수를 만든다.
get_system_mem_usage() {
    # free 결과에서 전체 메모리와 사용 중인 메모리로 사용률을 계산한다.
    free | awk '/Mem:/ {
        printf "%.1f", ($3 / $2) * 100
    }'
}

# 루트 파일시스템의 디스크 사용률을 구하는 함수를 만든다.
get_disk_usage() {
    # df / 결과의 두 번째 줄에서 사용률 숫자만 출력한다.
    df / | awk 'NR==2 {
        gsub(/%/, "", $5)
        print $5
    }'
}

# 특정 프로세스의 CPU 사용률을 구하는 함수를 만든다.
get_process_cpu_usage() {
    # 첫 번째 인자로 받은 PID를 지역 변수에 저장한다.
    local pid="$1"

    # ps로 해당 PID의 CPU 사용률만 출력한다.
    ps -p "$pid" -o %cpu= | awk '{print $1}'
}

# 특정 프로세스의 메모리 사용률을 구하는 함수를 만든다.
get_process_mem_usage() {
    # 첫 번째 인자로 받은 PID를 지역 변수에 저장한다.
    local pid="$1"

    # ps로 해당 PID의 메모리 사용률만 출력한다.
    ps -p "$pid" -o %mem= | awk '{print $1}'
}

# 특정 프로세스의 실제 메모리 상주 크기 RSS를 KB 단위로 구하는 함수를 만든다.
get_process_rss_kb() {
    # 첫 번째 인자로 받은 PID를 지역 변수에 저장한다.
    local pid="$1"

    # ps로 해당 PID의 RSS 값만 출력한다.
    ps -p "$pid" -o rss= | awk '{print $1}'
}

# 특정 값이 임계값보다 크면 경고를 출력하는 함수를 만든다.
warn_if_high() {
    # 첫 번째 인자는 자원 이름이다.
    local name="$1"

    # 두 번째 인자는 현재 값이다.
    local value="$2"

    # 세 번째 인자는 임계값이다.
    local limit="$3"

    # 프로세스가 꺼져서 값이 비어 있는 경우 에러 방지
    if [ -z "$value" ]; then
        return 0
    fi

    # awk로 소수점 숫자 비교를 수행한다.
    if awk "BEGIN { exit !($value > $limit) }"; then
        # 현재 값이 임계값보다 크면 경고를 출력한다.
        print_line "[WARNING] $name usage is high: $value%"
    fi
}




# =========================================================
# 로그 디렉토리가 없으면 만든다.
mkdir -p "$LOG_DIR"

# agent-app-leak 프로세스 PID를 찾는다.
PID=$(find_app_pid)

# 현재 시각을 로그에 남기기 좋은 형식으로 저장한다.
NOW=$(date '+%Y-%m-%d %H:%M:%S')

# 관제 결과 제목을 출력한다.
print_line "====== SYSTEM MONITOR RESULT ======"

# 보기 좋게 빈 줄을 출력한다.
print_line ""

# 헬스 체크 영역 제목을 출력한다.
print_line "[HEALTH CHECK]"





# =========================================================
# PID가 비어 있으면 프로세스가 없는 상태로 판단한다.
if [ -z "$PID" ]; then
    # 프로세스 확인 실패를 화면에 출력한다.
    print_line "Checking process '$APP_NAME'... [FAIL]"

    # 프로세스가 죽어 있다는 사실을 로그 파일에 남긴다.
    echo "[$NOW] PROCESS:$APP_NAME STATUS:DOWN" >> "$LOG_FILE"

    # 실패 상태 코드 1로 종료한다.
    exit 1
fi

# 프로세스 확인 성공과 PID를 화면에 출력한다.
print_line "Checking process '$APP_NAME'... [OK] (PID: $PID)"

# ss로 LISTEN 중인 포트 목록에서 앱 포트를 찾는다.
if ss -tuln | awk '{print $5}' | grep -q ":$APP_PORT$"; then
    # 포트가 열려 있으면 상태값을 OK로 저장한다.
    PORT_STATUS="OK"

    # 포트 확인 성공을 화면에 출력한다.
    print_line "Checking port $APP_PORT... [OK]"
else
    # 포트가 닫혀 있으면 상태값을 FAIL로 저장한다.
    PORT_STATUS="FAIL"

    # 포트 확인 실패를 화면에 출력한다.
    print_line "Checking port $APP_PORT... [FAIL]"
fi






# =========================================================
# 방화벽 상태를 확인한다. 
# 이번 과제에서는 방화벽이 필요없으므로 확인하지 않겠다.
# check_firewall


# ------------------------------------
# 시스템 전체 CPU 사용률을 구한다.
SYSTEM_CPU_USAGE=$(get_system_cpu_usage)

# 시스템 전체 메모리 사용률을 구한다.
SYSTEM_MEM_USAGE=$(get_system_mem_usage)

# 루트 파일시스템 디스크 사용률을 구한다.
DISK_USED=$(get_disk_usage)

# 앱 프로세스 CPU 사용률을 구한다.
PROCESS_CPU_USAGE=$(get_process_cpu_usage "$PID")

# 앱 프로세스 메모리 사용률을 구한다.
PROCESS_MEM_USAGE=$(get_process_mem_usage "$PID")

# 앱 프로세스 RSS 값을 KB 단위로 구한다.
PROCESS_RSS_KB=$(get_process_rss_kb "$PID")


# ------------------------------------
# 보기 좋게 빈 줄을 출력한다.
print_line ""

# 자원 관제 영역 제목을 출력한다.
print_line "[RESOURCE MONITORING]"

# 시스템 전체 CPU 사용률을 출력한다.
print_line "System CPU Usage  : $SYSTEM_CPU_USAGE%"

# 시스템 전체 메모리 사용률을 출력한다.
print_line "System MEM Usage  : $SYSTEM_MEM_USAGE%"

# 디스크 사용률을 출력한다.
print_line "Disk Used         : $DISK_USED%"

# 앱 프로세스 CPU 사용률을 출력한다.
print_line "Process CPU Usage : $PROCESS_CPU_USAGE%"

# 앱 프로세스 메모리 사용률을 출력한다.
print_line "Process MEM Usage : $PROCESS_MEM_USAGE%"

# 앱 프로세스 RSS 값을 출력한다.
print_line "Process RSS       : ${PROCESS_RSS_KB}KB"


# ------------------------------------
# 시스템 CPU 사용률이 80%를 넘으면 경고를 출력한다.
warn_if_high "System CPU" "$SYSTEM_CPU_USAGE" 80

# 시스템 메모리 사용률이 80%를 넘으면 경고를 출력한다.
warn_if_high "System MEM" "$SYSTEM_MEM_USAGE" 80

# 앱 프로세스 CPU 사용률이 50%를 넘으면 경고를 출력한다.
warn_if_high "Process CPU" "$PROCESS_CPU_USAGE" 50

# 앱 프로세스 메모리 사용률이 50%를 넘으면 경고를 출력한다.
warn_if_high "Process MEM" "$PROCESS_MEM_USAGE" 50



# ------------------------------------
# 로그 파일이 너무 커졌는지 확인하고 필요하면 회전시킨다.
rotate_log_if_needed



# ------------------------------------
# 한 줄짜리 관제 결과를 monitor.log에 추가한다.
# 각 항목 사이에 | 문자를 넣어 사람이 읽을 때 항목 경계를 쉽게 구분하게 한다.
echo "[$NOW] PROCESS:$APP_NAME | PID:$PID | PORT:$PORT_STATUS | SYS_CPU:$SYSTEM_CPU_USAGE% | SYS_MEM:$SYSTEM_MEM_USAGE% | PROC_CPU:$PROCESS_CPU_USAGE% | PROC_MEM:$PROCESS_MEM_USAGE% | RSS:${PROCESS_RSS_KB}KB | DISK_USED:$DISK_USED%" >> "$LOG_FILE"
