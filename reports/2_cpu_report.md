# 🟩 [Bug] CPU Latency - CPU 과점유 방지 와치독 정책에 의한 프로세스 비상 정지  


<br>

## 🟢 1. Description (현상 설명)  
- `agent-app-leak` 애플리케이션 가동 후 약 36초가 지나면 갑자기 프로세스에서 메세지를 띄움.  
    - [CRITICAL] [CpuWorker] CPU Threshold Violated!  
    - [SYSTEM] WATCHDOG: INITIATING EMERGENCY ABORT (SIGTERM)  
- 결국 프로세스 `Terminated`됨.  




<br><br>

## 🟢 2. Evidence & Logs (증거 자료)  

### 🟡 agent_app.log - 프로그램 실행 로그 중 핵심 구간 발췌  
- `agent_app.log`에서 CPU 점유 로드가 상승하다가 실질 안전 제어선인 50%를 초과하는 즉시 비상 와치독에 의해 강제 종료된 로그를 획득했다.  
```bash
2026-05-26 20:49:07,183 [INFO] [CpuWorker] Started. Maximum CPU Limit: 60%  
2026-05-26 20:49:07,184 [INFO] [CpuWorker] Current Load: 5.00%  
2026-05-26 20:49:10,347 [INFO] [CpuWorker] Current Load: 7.42%  
~~~ 중략 ~~~  
2026-05-26 20:49:38,431 [INFO] [CpuWorker] Current Load: 49.71%  
2026-05-26 20:49:41,538 [INFO] [CpuWorker] Current Load: 50.98%  
2026-05-26 20:49:41,639 [CRITICAL] [CpuWorker] CPU Threshold Violated! (50.98%).  
>>> [SYSTEM] WATCHDOG: INITIATING EMERGENCY ABORT (SIGTERM) <<<  
Terminated  
```

<br>

### 🟡 monitor.log - 관제 로그 데이터  
- `monitor.log`를 관제한 결과, 동일 PID `82799`에 대한 `PROC_CPU` 점유율이 50%의 실질 가이드라인 부근에 근접한 후 더 이상 갱신되지 못하고 프로세스가 삭제되어 사라진 흐름이 잡혔다.  
- (🔥🔥🔥🔥🔥 이 과제에서는 그 흐름이 잡혀야 하지만 잡히지 않았다.)  

```bash
[2026-05-26 20:49:06] PROCESS:agent-app-leak | PID:82799 | PORT:OK | SYS_CPU:1.7% | SYS_MEM:8.5% | PROC_CPU:7.5% | PROC_MEM:0.3% | RSS:31.74MB | DISK_USED:1%  
[2026-05-26 20:49:09] PROCESS:agent-app-leak | PID:82799 | PORT:OK | SYS_CPU:1.7% | SYS_MEM:8.6% | PROC_CPU:3.3% | PROC_MEM:0.3% | RSS:31.74MB | DISK_USED:1%  
[2026-05-26 20:49:12] PROCESS:agent-app-leak | PID:82799 | PORT:OK | SYS_CPU:0.8% | SYS_MEM:8.9% | PROC_CPU:2.2% | PROC_MEM:0.4% | RSS:31.75MB | DISK_USED:1%  
[2026-05-26 20:49:15] PROCESS:agent-app-leak | PID:82799 | PORT:OK | SYS_CPU:2.5% | SYS_MEM:8.9% | PROC_CPU:1.8% | PROC_MEM:0.4% | RSS:31.75MB | DISK_USED:1%  
[2026-05-26 20:49:18] PROCESS:agent-app-leak | PID:82799 | PORT:OK | SYS_CPU:1.7% | SYS_MEM:8.8% | PROC_CPU:1.5% | PROC_MEM:0.4% | RSS:31.75MB | DISK_USED:1%  
[2026-05-26 20:49:21] PROCESS:agent-app-leak | PID:82799 | PORT:OK | SYS_CPU:1.7% | SYS_MEM:8.9% | PROC_CPU:1.4% | PROC_MEM:0.4% | RSS:31.75MB | DISK_USED:1%  
[2026-05-26 20:49:23] PROCESS:agent-app-leak | PID:82799 | PORT:OK | SYS_CPU:1.7% | SYS_MEM:9.0% | PROC_CPU:1.4% | PROC_MEM:0.4% | RSS:31.75MB | DISK_USED:1%  
[2026-05-26 20:49:26] PROCESS:agent-app-leak | PID:82799 | PORT:OK | SYS_CPU:1.7% | SYS_MEM:9.0% | PROC_CPU:1.4% | PROC_MEM:0.4% | RSS:31.75MB | DISK_USED:1%  
[2026-05-26 20:49:29] PROCESS:agent-app-leak | PID:82799 | PORT:OK | SYS_CPU:3.2% | SYS_MEM:8.9% | PROC_CPU:1.4% | PROC_MEM:0.4% | RSS:31.75MB | DISK_USED:1%  
[2026-05-26 20:49:32] PROCESS:agent-app-leak | PID:82799 | PORT:OK | SYS_CPU:0.9% | SYS_MEM:9.0% | PROC_CPU:1.4% | PROC_MEM:0.4% | RSS:31.75MB | DISK_USED:1%  
[2026-05-26 20:49:35] PROCESS:agent-app-leak | PID:82799 | PORT:OK | SYS_CPU:0.9% | SYS_MEM:9.0% | PROC_CPU:1.4% | PROC_MEM:0.4% | RSS:31.75MB | DISK_USED:1%  
[2026-05-26 20:49:38] PROCESS:agent-app-leak | PID:82799 | PORT:OK | SYS_CPU:0.8% | SYS_MEM:8.9% | PROC_CPU:1.3% | PROC_MEM:0.4% | RSS:31.75MB | DISK_USED:1%   
```

- 실제 프로세스가 종료된 것을 확인한 로그  
```bash
pgrep -x "82799"  
```




<br><br>

## 🟢 3. Root Cause Analysis (원인 분석)  

- 알고 가기  
    - `와치독(사냥개)`  
        - 시스템이 정상적으로 작동하고 있는지 감시하고, 만약 시스템이 먹통(Hang)이 되거나 무한 루프에 빠지면 이를 감지하여 강제로 복구(재시작)시키는 하드웨어 또는 소프트웨어 장치.  
    - `SIGTERM(Signal Terminate)`  
        - 리눅스/유닉스 계열 운영체제에서 프로세스에게 "이제 안전하게 종료하라"고 보내는 표준 신호(Signal)(신호 번호는 15번)  

<br>

- **임계치 강제 하향 잠금**: 사용자가 환경변수를 강제로 `CPU_MAX_OCCUPY=60%`로 지정하더라도, 내부 안전 정책인 `SafetyGuard`는 시스템 안정성 보호를 위해 강제로 **실제 비상 정지 한계치를 50%로 고정 및 하향 잠금**한다.  

- **와치독 발동**  
    - 계산 로드가 지속적으로 늘어나 50%의 강제 안전선을 넘기는 즉시(`50.98%`) **Watchdog** 감시 로직이 이를 감지하여 프로세스를 차단하기 시작했다.  




<br><br>

## 🟢 4. Workaround & Verification (조치 및 검증)  

- **근본적 조치**  
    - CPU 점유를 억제하기 위해선, 무한 반복 계산 연산부 내부 혹은 워커 스레드의 루프 중간에 적절한 양보(`sleep` 또는 `yield`) 함수를 명시적으로 삽입해 주기적으로 자원을 양보하도록 앱을 리팩토링.  

- **(과제 기준) 검증 Before & After 비교 결과**  
    - `.bashrc` 스크립트 내에서 `CPU_MAX_OCCUPY` 환경변수를 안전 권장 범위 안쪽 50% 미만으로 설정.    
        ```bash
        export CPU_MAX_OCCUPY=40  
        ```

    - Peak(40.00%)에 도달하더라도 프로세스가 사살되지 않고 정상적으로 **Cooldown (냉각) 로직이 발동하여 5%대로 낮춘 뒤 안전하게 가동을 유지함**이 검증되었다.  

        | 비교 항목 | Before (조치 전 - 장애) | After (조치 후 - 정상) |  
        | :--- | :--- | :--- |
        | CPU_MAX_OCCUPY | `60%` | `40%` |  
        | 부팅 판단 결과 | `[ WARNING: Recommend Under 50% ]` | `[ CPU ] Limit: 40% [ OK ]` |  
        | 최고 로드 점유 | 50.98% (50% 안전 차단선 오버) | 40.00% (설정된 최대 Peak 도달) |  
        | 로그 메시지 | `CPU Threshold Violated! (50.98%)` | `Peak reached (40.00%). Starting cooldown...` |  
        | 최종 동작 결과 | Killed (Watchdog SIGTERM 폭사) | Stable (정상 복구 및 무제한 생존) |  



