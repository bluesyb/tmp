#!/bin/bash

# cmagent loganalyzer 시작 스크립트

# 색상 코드 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 설정값들
JAR_FILE="loganalyzerapp.jar"
PID_FILE="cmagent.pid"
LOG_FILE="app.log"

# Java 경로 (필요시 수정)
JAVA_HOME=${JAVA_HOME:-"/usr/lib/jvm/java-21-openjdk"}
JAVA_BIN="${JAVA_HOME}/bin/java"

# JDK 21이 없으면 기본 java 사용
if [ ! -f "${JAVA_BIN}" ]; then
    JAVA_BIN="java"
    log_warn "JDK 21을 찾을 수 없어 시스템 기본 Java를 사용합니다"
fi

# 기본 JVM 옵션
JVM_OPTS="-Xms1g -Xmx3g"

# 애플리케이션이 이미 실행 중인지 확인
check_running() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            return 0  # 실행 중
        else
            rm -f "$PID_FILE"
            return 1  # 실행 중이 아님
        fi
    fi
    return 1  # PID 파일 없음
}

# 애플리케이션 중지
stop_app() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        log_info "애플리케이션 중지 중... (PID: $PID)"

        if ps -p "$PID" > /dev/null 2>&1; then
            kill "$PID"
            sleep 5

            if ps -p "$PID" > /dev/null 2>&1; then
                log_warn "강제 종료를 시도합니다"
                kill -9 "$PID"
                sleep 2
            fi
        fi

        rm -f "$PID_FILE"
        log_info "애플리케이션이 중지되었습니다"
    else
        log_warn "실행 중인 애플리케이션이 없습니다"
    fi
}

# 애플리케이션 시작
start_app() {
    if check_running; then
        log_error "애플리케이션이 이미 실행 중입니다"
        exit 1
    fi

    if [ ! -f "$JAR_FILE" ]; then
        log_error "JAR 파일을 찾을 수 없습니다: $JAR_FILE"
        exit 1
    fi

    # .env 로드
    if [ -f ".env" ]; then
        set -o allexport
        source ".env"
        set +o allexport
        log_info ".env 로드 완료"
    else
        log_warn ".env 파일이 없습니다. 환경변수가 미리 export되어 있어야 합니다."
    fi

    log_info "=================================="
    log_info "CM Agent Log Analyzer 시작"
    log_info "=================================="
    log_info "JAR 파일: $JAR_FILE"
    log_info "로그 파일: $LOG_FILE"
    log_info "Java 경로: $JAVA_BIN"

    # 필수 환경변수 검증 (미설정 시 기동 중단)
    local missing=()
    [ -z "$API_KEY" ]        && missing+=("API_KEY")
    [ -z "$JIRA_BASE_URL" ]  && missing+=("JIRA_BASE_URL")
    [ -z "$JIRA_EMAIL" ]     && missing+=("JIRA_EMAIL")
    [ -z "$JIRA_API_TOKEN" ] && missing+=("JIRA_API_TOKEN")

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "필수 환경변수가 설정되지 않았습니다: ${missing[*]}"
        log_error "export <변수명>=<값> 으로 설정 후 다시 시도하세요"
        exit 1
    fi

    # Jenkins 기본 인증 정보 (환경변수에서 가져오거나 기본값 사용)
    JENKINS_USERNAME=${JENKINS_DEFAULT_USERNAME:-""}
    JENKINS_PASSWORD=${JENKINS_DEFAULT_PASSWORD:-""}

    # Rundeck 토큰들 (환경변수에서 가져오기)
    DEV_TOKEN=${RUNDECK_API_DEV_TOKEN:-""}
    SIT_TOKEN=${RUNDECK_API_SIT_TOKEN:-""}
    HFDEV_TOKEN=${RUNDECK_API_HFDEV_TOKEN:-""}
    HFSIT_TOKEN=${RUNDECK_API_HFSIT_TOKEN:-""}

    # 토큰이 설정되지 않은 경우 사용자에게 알림
    if [ -z "$DEV_TOKEN" ] && [ -z "$SIT_TOKEN" ] && [ -z "$HFDEV_TOKEN" ] && [ -z "$HFSIT_TOKEN" ]; then
        log_warn "Rundeck API 토큰이 설정되지 않았습니다"
        log_warn "다음 환경변수를 설정해주세요:"
        log_warn "  export RUNDECK_API_DEV_TOKEN=your_dev_token"
        log_warn "  export RUNDECK_API_SIT_TOKEN=your_sit_token"
        log_warn "  export RUNDECK_API_HFDEV_TOKEN=your_hfdev_token"
        log_warn "  export RUNDECK_API_HFSIT_TOKEN=your_hfsit_token"
    fi

    # SVN 미설정 시 경고 (선택적)
    if [ -z "$SVN_BASE_URL" ]; then
        log_warn "SVN_BASE_URL이 설정되지 않았습니다 (SVN diff 기능 비활성화)"
    fi

    # nohup을 사용한 백그라운드 실행 (첨부파일의 방식 적용)
    log_info "백그라운드로 애플리케이션을 시작합니다..."

    nohup $JAVA_BIN \
        -Djenkins.default.username="$JENKINS_USERNAME" \
        -Djenkins.default.password="$JENKINS_PASSWORD" \
        -Drundeck.api.dev-token="$DEV_TOKEN" \
        -Drundeck.api.hfdev-token="$HFDEV_TOKEN" \
        -Drundeck.api.sit-token="$SIT_TOKEN" \
        -Drundeck.api.hfsit-token="$HFSIT_TOKEN" \
        $JVM_OPTS \
        -jar "$JAR_FILE" \
        > "$LOG_FILE" 2>&1 &

    # PID 저장
    echo $! > "$PID_FILE"

    log_info "애플리케이션이 시작되었습니다 (PID: $(cat $PID_FILE))"
    log_info "로그 파일: $LOG_FILE"
    log_info "서비스 URL: http://localhost:8085"
    log_info "Swagger UI: http://localhost:8085/swagger-ui.html"
    log_info "헬스체크: http://localhost:8085/actuator/health"

    # 잠시 대기 후 상태 확인
    sleep 3
    if check_running; then
        log_info "✅ 애플리케이션이 성공적으로 시작되었습니다"
        log_info "로그 확인: tail -f $LOG_FILE"
    else
        log_error "❌ 애플리케이션 시작에 실패했습니다"
        log_error "로그를 확인하세요: cat $LOG_FILE"
        exit 1
    fi
}

# 상태 확인
status_app() {
    if check_running; then
        PID=$(cat "$PID_FILE")
        log_info "애플리케이션이 실행 중입니다 (PID: $PID)"

        # 프로세스 정보 표시
        echo ""
        echo "프로세스 정보:"
        ps -p "$PID" -o pid,ppid,cmd,start,time

        # 포트 확인
        if command -v netstat > /dev/null 2>&1; then
            echo ""
            echo "포트 사용 현황:"
            netstat -tlnp 2>/dev/null | grep :8085 || echo "포트 8085가 사용되지 않고 있습니다"
        fi

        # 서비스 응답 확인
        echo ""
        log_info "서비스 응답 확인 중..."
        if command -v curl > /dev/null 2>&1; then
            HEALTH_RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null http://localhost:8085/actuator/health --connect-timeout 5)
            if [ "$HEALTH_RESPONSE" = "200" ]; then
                log_info "✅ 서비스가 정상적으로 응답하고 있습니다"
            else
                log_warn "⚠️ 서비스가 아직 준비되지 않았거나 응답하지 않습니다 (HTTP: $HEALTH_RESPONSE)"
            fi
        else
            log_warn "curl이 설치되지 않아 서비스 응답을 확인할 수 없습니다"
        fi
    else
        log_warn "애플리케이션이 실행되지 않고 있습니다"
        exit 1
    fi
}

# 로그 보기
logs_app() {
    if [ -f "$LOG_FILE" ]; then
        if [ "$1" = "-f" ]; then
            log_info "실시간 로그를 표시합니다 (Ctrl+C로 종료)"
            tail -f "$LOG_FILE"
        else
            log_info "최근 로그 50줄을 표시합니다"
            tail -50 "$LOG_FILE"
        fi
    else
        log_error "로그 파일을 찾을 수 없습니다: $LOG_FILE"
        exit 1
    fi
}

# 재시작
restart_app() {
    log_info "애플리케이션을 재시작합니다"
    stop_app
    sleep 2
    start_app
}

# 사용법 표시
usage() {
    echo "사용법: $0 {start|stop|restart|status|logs|logs -f}"
    echo ""
    echo "명령어:"
    echo "  start     애플리케이션 시작"
    echo "  stop      애플리케이션 중지"
    echo "  restart   애플리케이션 재시작"
    echo "  status    애플리케이션 상태 확인"
    echo "  logs      최근 로그 50줄 표시"
    echo "  logs -f   실시간 로그 표시"
    echo ""
    echo "환경변수 설정 예제:"
    echo "  [필수]"
    echo "  export API_KEY=your_api_key"
    echo "  export JIRA_BASE_URL=https://your-domain.atlassian.net"
    echo "  export JIRA_EMAIL=your@email.com"
    echo "  export JIRA_API_TOKEN=your_jira_api_token"
    echo ""
    echo "  [선택]"
    echo "  export SVN_BASE_URL=http://svn.server/svn"
    echo "  export SVN_USERNAME=your_svn_username"
    echo "  export SVN_PASSWORD=your_svn_password"
    echo "  export JENKINS_DEFAULT_USERNAME=your_username"
    echo "  export JENKINS_DEFAULT_PASSWORD=your_password"
    echo "  export RUNDECK_API_DEV_TOKEN=your_dev_token"
    echo "  export RUNDECK_API_SIT_TOKEN=your_sit_token"
    echo "  export RUNDECK_API_HFDEV_TOKEN=your_hfdev_token"
    echo "  export RUNDECK_API_HFSIT_TOKEN=your_hfsit_token"
    echo ""
}

# 메인 로직
case "$1" in
    start)
        start_app
        ;;
    stop)
        stop_app
        ;;
    restart)
        restart_app
        ;;
    status)
        status_app
        ;;
    logs)
        logs_app "$2"
        ;;
    *)
        usage
        exit 1
        ;;
esac

exit 0