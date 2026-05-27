# 🟩 리눅스 프로세스 및 시스템 리소스 트러블슈팅  


<br>

## 🟢 프로젝트 소개  
- 리눅스 프로세스에서 발생할 수 있는 3대 리소스 장애(OOM, CPU 과점유, Deadlock) 상황을 Docker 컨테이너 환경 내에서 재현하고 정량적으로 진단 및 해결하는 트러블슈팅 프로젝트임.  
- 초보자가 명령어 하나하나의 영문 풀네임과 해설을 보며 기초부터 응용까지 쉽게 따라 할 수 있는 자가 학습 체계를 구축하고 있음.  



<br><br>

## 🟢 트러블슈팅 대상 3대 장애 유형  

| 장애 유형 | 현상 및 감지 메시지 | 분석 및 원인 | 해결 방안 (Before & After) |  
| :--- | :--- | :--- | :--- |
| **OOM (메모리 고갈)** | `Killed`, `SELF-TERMINATED` / RSS 메모리가 선형으로 급증해 한계 도달 | `MemoryWorker`가 데이터를 힙 메모리에서 해제하지 않는 누수 유발 | `MEMORY_LIMIT` 임계값을 적정선(512MB)으로 상향하여 청소 로직 가동 |  
| **CPU Latency (과점유)** | `WATCHDOG: INITIATING EMERGENCY ABORT` / 점유율 50% 돌파 시 강제 종료 | `SafetyGuard`가 비상 방지 잠금 선을 작동시키며 와치독 사살 | `CPU_MAX_OCCUPY=40` 등 안전 범위로 강제 설정하여 쿨다운 발동 유지 |  
| **Deadlock (교착 상태)** | `Status: BLOCKED` / PID는 살아있으나 CPU `0.3%`로 얼어붙고 출력 완전 중단 | 스레드1(A 점유, B 요구)과 스레드2(B 점유, A 요구)의 교차 락 대기 형성 | `MULTI_THREAD_ENABLE=False` 조정으로 순차 제어하여 락 충돌 회피 |  


<br><br>

## 🟢 핵심 터미널 명령어 사전  
- 실습 및 관제 시에 활용되는 명령어들의 풀네임과 해설표임.  

| 명령어 | 풀네임 (Full Name) | 기능 및 해설 |  
| :--- | :--- | :--- |
| `ps` | Process Status | 현재 동작 중인 프로세스의 실시간 상태 및 식별 정보를 조회함. |  
| `top` | Table Of Processes | 시스템의 CPU 점유율, 메모리 상태 등 전체 리소스 상태를 지속 동적 모니터링함. |  
| `pgrep` | Process Grep | 찾고자 하는 프로세스 이름을 검색해 일치하는 고유 PID만 추출함. |  
| `strace` | System Call Trace | 프로세스가 커널에 호출하는 시스템 콜을 실시간으로 추적함. |  
| `gh` | GitHub Command Line Tool | 깃허브 웹 화면에 갈 필요 없이 터미널 안에서 즉시 이슈 생성, PR 전송 등을 수행함. |  

