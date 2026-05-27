# 🟩 [Bug] OOM Crash - 메모리 누수로 인한 MemoryGuard의 강제 종료 장애  

<br>

## 🟢 1. Description (현상 설명)  
- 조건 설정: `MEMORY_LIMIT=256MB`(경계 한도), CPU_MAX_OCCUPY=49% (안전 영역), MULTI_THREAD_ENABLE=False (단일 스레드)  
  
- `agent-app-leak` 애플리케이션을 구동한 지 약 32초 만에 터미널에 애플리케이션 내부의 메모리 보호 정책(MemoryGuard)에 의해 프로세스가 `SELF-TERMINATED` 및 `Killed` 메시지가 출력되며 강제 종료됨.  



<br><br>

## 🟢 2. Evidence & Logs (증거 자료)  

### 🟡 agent_app.log - 프로그램 실행 로그 중 핵심 구간 발췌    
- `agent_app.log`에서 `Current Heap`이 25MB 단위로 급증하여 임계치를 초과하여 `MemoryGuard`가 작동한 것을 확인  

```bash
[ Agent Initiate ] Resource Check  
==================================================  
[ MEMORY ] Limit: 256MB          [ WARNING: Recommend Over 256MB ]  
==================================================  
2026-05-26 17:13:55,660 [INFO] [MemoryWorker] Current Heap: 25MB  
2026-05-26 17:13:58,675 [INFO] [MemoryWorker] Current Heap: 50MB  
2026-05-26 17:14:01,681 [INFO] [MemoryWorker] Current Heap: 75MB  
2026-05-26 17:14:04,697 [INFO] [MemoryWorker] Current Heap: 100MB  
2026-05-26 17:14:07,704 [INFO] [MemoryWorker] Current Heap: 125MB  
2026-05-26 17:14:10,709 [INFO] [MemoryWorker] Current Heap: 150MB  
2026-05-26 17:14:13,721 [INFO] [MemoryWorker] Current Heap: 175MB  
2026-05-26 17:14:16,789 [INFO] [MemoryWorker] Current Heap: 200MB  
2026-05-26 17:14:19,794 [INFO] [MemoryWorker] Current Heap: 225MB  
2026-05-26 17:14:22,804 [INFO] [MemoryWorker] Current Heap: 250MB  
2026-05-26 17:14:25,814 [INFO] [MemoryWorker] Current Heap: 275MB  
2026-05-26 17:14:25,814 [CRITICAL] [MemoryGuard] Memory limit exceeded (275MB >= 256MB) / (Recommend Over 256MB)  
2026-05-26 17:14:25,814 [CRITICAL] [MemoryGuard] Self-terminating process 26503 to prevent system instability.  
>>> [SYSTEM] SELF-TERMINATED (Memory Limit Exceeded) <<<  
Killed  
```


<br>

### 🟡 monitor.log 확인  
- `monitor.log`를 관제한 결과, `17:13:56`부터 `17:14:24`까지 **물리 메모리 상주 크기 (RSS)**가 `56.70MB`에서 시작해 `281.73MB`까지 선형적으로 증가하며, 정해둔 임계 한도인 `256MB`를 오버하는 패턴이 포착  

```bash
[2026-05-26 17:13:56] PROCESS:agent-app-leak | PID:26503 | PORT:OK | SYS_CPU:2.4% | SYS_MEM:8.9% | PROC_CPU:4.9% | PROC_MEM:0.7% | RSS:56.70MB | DISK_USED:1%  
[2026-05-26 17:13:59] PROCESS:agent-app-leak | PID:26503 | PORT:OK | SYS_CPU:8.8% | SYS_MEM:9.3% | PROC_CPU:3.0% | PROC_MEM:1.0% | RSS:81.70MB | DISK_USED:1%  
[2026-05-26 17:14:02] PROCESS:agent-app-leak | PID:26503 | PORT:OK | SYS_CPU:0.9% | SYS_MEM:9.8% | PROC_CPU:2.0% | PROC_MEM:1.3% | RSS:106.70MB | DISK_USED:1%  
[2026-05-26 17:14:05] PROCESS:agent-app-leak | PID:26503 | PORT:OK | SYS_CPU:1.7% | SYS_MEM:10.2% | PROC_CPU:1.5% | PROC_MEM:1.6% | RSS:131.71MB | DISK_USED:1%  
[2026-05-26 17:14:07] PROCESS:agent-app-leak | PID:26503 | PORT:OK | SYS_CPU:3.5% | SYS_MEM:10.4% | PROC_CPU:1.3% | PROC_MEM:1.9% | RSS:156.71MB | DISK_USED:1%  
[2026-05-26 17:14:10] PROCESS:agent-app-leak | PID:26503 | PORT:OK | SYS_CPU:0.9% | SYS_MEM:10.8% | PROC_CPU:1.1% | PROC_MEM:2.2% | RSS:181.71MB | DISK_USED:1%  
[2026-05-26 17:14:13] PROCESS:agent-app-leak | PID:26503 | PORT:OK | SYS_CPU:0.9% | SYS_MEM:11.2% | PROC_CPU:1.0% | PROC_MEM:2.6% | RSS:206.72MB | DISK_USED:1%  
[2026-05-26 17:14:16] PROCESS:agent-app-leak | PID:26503 | PORT:OK | SYS_CPU:1.6% | SYS_MEM:11.2% | PROC_CPU:0.9% | PROC_MEM:2.9% | RSS:231.72MB | DISK_USED:1%  
[2026-05-26 17:14:19] PROCESS:agent-app-leak | PID:26503 | PORT:OK | SYS_CPU:0.8% | SYS_MEM:11.6% | PROC_CPU:0.8% | PROC_MEM:2.9% | RSS:256.73MB | DISK_USED:1%  
[2026-05-26 17:14:22] PROCESS:agent-app-leak | PID:26503 | PORT:OK | SYS_CPU:3.4% | SYS_MEM:11.8% | PROC_CPU:0.7% | PROC_MEM:3.2% | RSS:256.73MB | DISK_USED:1%  
[2026-05-26 17:14:24] PROCESS:agent-app-leak | PID:26503 | PORT:OK | SYS_CPU:0.9% | SYS_MEM:12.4% | PROC_CPU:0.7% | PROC_MEM:3.5% | RSS:281.73MB | DISK_USED:1%  
```



<br><br>

## 🟢 3. Root Cause Analysis (원인 분석)  
- **현상 분석**  
    - `MemoryWorker`가 3초 간격으로 어플리케이션 로직 내부에서 생성한 데이터를 힙(Heap) 메모리에서 해제하지 않고 지속적으로 25MB씩 힙 메모리를 증가.  
    - 사용 후 반환을 하지 않는 `메모리 누수(Memory Leak)` 결함이 있는 것으로 판단.  

- **시스템 동작**  
    - 물리 메모리 사용량이 `MEMORY_LIMIT=256MB`에 초과하여 275MB에 도달.  
    - 애플리케이션 내부의 `MemoryGuard` 정책이 시스템 전체 불안정을 방지하기 위해 해당 프로세스를 `SIGKILL`로 강제 종료.  

  


<br><br>

## 🟢 4. Workaround & Verification (조치 및 검증)  

- **근본적 조치**  
   - `MEMORY_LIMIT` 도달 시 소스 코드 상에서 생성된 캐시 데이터 리스트나 객체 참조 체인에 대해 명시적으로 정리(`clear` 또는 `del`)가 일어나도록 애플리케이션 리팩토링.  
   - (이 과제에서는 MEMORY_LIMIT를 512MB로 상향한 것으로 해결)  

- **검증 결과**  
   - `MEMORY_LIMIT` 도달 시 cleanup 실행  
      - [WARNING] [MemoryWorker] Memory Usage Reached Limit (525MB). Starting cleanup...  
      - [INFO] [System] Memory Cache Flushed. Process Stabilized.  


