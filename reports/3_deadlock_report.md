# 🟩 [Bug] Deadlock - 멀티스레드 상호 배제 및 순환 대기로 인한 영구 무응답 상태  

<br>

## 🟢 1. Description (현상 설명)  
- `agent-app-leak` 애플리케이션 가동 후 프로세스는 살아있으나(PID 존재), 터미널의 모든 진행 상황 출력이 멈추고 CPU 및 메모리 점유의 변화가 완전히 정체되어 무응답 상태에 빠졌다.  


<br><br>

## 🟢 2. Evidence & Logs (증거 자료)  

### 🟡 agent_app.log - 프로그램 실행 로그 중 핵심 구간 발췌  
- `agent_app.log`에서 스레드 1번과 2번이 각각의 선점된 자원(Shared_Memory_A, Socket_Pool_B)을 쥔 상태에서 다음 자원을 획득하기 위해 대기하는 `Status: BLOCKED` 로그가 포착되었다.  
```bash
=== step 1 ===  

2026-05-26 21:49:00,371 [INFO] [Worker-Thread-1] Process Started. Attempting to lock [Shared_Memory_A]...  
2026-05-26 21:49:00,372 [INFO] [AgentWorker][Worker-Thread-2] Process Started. Attempting to lock [Socket_Pool_B]...  


2026-05-26 21:49:00,372 [INFO] [AgentWorker][Worker-Thread-1] LOCK ACQUIRED: [Shared_Memory_A]. (Holding...)  
2026-05-26 21:49:00,372 [INFO] [AgentWorker][Worker-Thread-2] LOCK ACQUIRED: [Socket_Pool_B]. (Holding...)  


=== step 2 ===  

2026-05-26 21:49:00,372 [INFO] [AgentWorker] Waiting for worker threads to complete transactions...  

2026-05-26 21:49:00,372 [INFO] [AgentWorker][Worker-Thread-1] Processing critical data in Memory A...  
2026-05-26 21:49:00,373 [INFO] [AgentWorker][Worker-Thread-2] Establishing network connections in Pool B...  


=== step 3 ===  

2026-05-26 21:49:02,378 [INFO] [AgentWorker][Worker-Thread-1] Need resource [Socket_Pool_B] to finish job.  
2026-05-26 21:49:02,380 [INFO] [AgentWorker][Worker-Thread-2] Need resource [Shared_Memory_A] to write logs.  


=== step 4 ===  

2026-05-26 21:49:02,382 [INFO] [AgentWorker][Worker-Thread-1] WAITING for [Socket_Pool_B]... (Status: BLOCKED)  
2026-05-26 21:49:02,382 [INFO] [AgentWorker][Worker-Thread-2] WAITING for [Shared_Memory_A]... (Status: BLOCKED)  
```

### 🟡 PID 실행 여부 확인  
해당 프로세스는 살아있음을 확인함.  

```bash
 ps -ef | grep agent  
```

<br>  

### 🟡 monitor.log - 관제 로그 데이터 (수치/그래프/스크린샷)  
- `monitor.log`를 관제한 결과, 프로세스 PID `96735`가 장시간 가동 중임에도 상주 물리 메모리(RSS)가 `31.55MB`로 완벽히 얼어붙고, `PROC_CPU` 점유 속도가 `12.0%`에서 시작해 결국 `0.3%`로 완전히 가라앉은 정체 현상이 포착되었다.  
```bash
[2026-05-26 21:48:54] PROCESS:agent-app-leak | PID:96735 | PORT:OK | SYS_CPU:1.6% | SYS_MEM:8.3% | 🔥PROC_CPU:12.0% | 🔥PROC_MEM:0.3% | 🔥RSS:31.68MB | DISK_USED:1%  
[2026-05-26 21:48:57] PROCESS:agent-app-leak | PID:96735 | PORT:OK | SYS_CPU:6.2% | SYS_MEM:8.4% | 🔥PROC_CPU:4.1% | 🔥PROC_MEM:0.3% | 🔥RSS:31.68MB | DISK_USED:1%  
[2026-05-26 21:48:59] PROCESS:agent-app-leak | PID:96735 | PORT:OK | SYS_CPU:0.8% | SYS_MEM:8.4% | 🔥PROC_CPU:2.5% | 🔥PROC_MEM:0.3% | 🔥RSS:31.55MB | DISK_USED:1%  
[2026-05-26 21:49:02] PROCESS:agent-app-leak | PID:96735 | PORT:OK | SYS_CPU:1.6% | SYS_MEM:8.6% | 🔥PROC_CPU:1.7% | 🔥PROC_MEM:0.3% | 🔥RSS:31.55MB | DISK_USED:1%  
~~~ 중략 ~~~  
[2026-05-26 21:49:45] PROCESS:agent-app-leak | PID:96735 | PORT:OK | SYS_CPU:1.7% | SYS_MEM:8.9% | 🔥PROC_CPU:0.3% | 🔥PROC_MEM:0.3% | 🔥RSS:31.55MB | DISK_USED:1%  
[2026-05-26 21:49:48] PROCESS:agent-app-leak | PID:96735 | PORT:OK | SYS_CPU:3.6% | SYS_MEM:8.8% | 🔥PROC_CPU:0.3% | 🔥PROC_MEM:0.3% | 🔥RSS:31.55MB | DISK_USED:1%  
[2026-05-26 21:49:51] PROCESS:agent-app-leak | PID:96735 | PORT:OK | SYS_CPU:2.0% | SYS_MEM:8.8% | 🔥PROC_CPU:0.3% | 🔥PROC_MEM:0.3% | 🔥RSS:31.55MB | DISK_USED:1%  
```




<br><br>

## 🟢 3. Root Cause Analysis (원인 분석)  

- **순환 대기 교착 형성**  
    - 동시성(Concurrent) 환경에서 `Worker-Thread-1`이 `Shared_Memory_A`를 선점한 채 `Socket_Pool_B`를 요구하며 대기  
    - 동시에 `Worker-Thread-2`가 `Socket_Pool_B`를 선점한 채 `Shared_Memory_A`를 요구하며 대기  
    - **상호 락 대기 루프**가 완벽하게 발생.  

- **정체 메커니즘**  
    - 상호 락 획득이 물려 그 누구도 연산을 지속해 임계 영역을 벗어나지 못하므로 모든 스레드의 자원 이용률이 `0.3%` 극소 수치로 급락하고 물리 메모리 점유율도 요동치지 않는 정체가 지속.  



<br>

#### ⚫️ `교착상태`란,  
- **교착상태 4대 필수 요건의 성립** (4가지 요건이 완벽하게 결합하여 성립됨)   
    - ① **상호 배제(한 자원은 한 스레드만 획득 가능)**  
    - ② **점유 대기(자원을 쥔 상태에서 타 자원 대기)**  
    - ③ **비선점(남이 쥔 락을 빼앗을 수 없음)**  
    - ④ **순환 대기(교차 락 요구)**  
    
- **OS 커널의 프로세스 판단 기준**  
    - OS 커널 입장에서는 프로세스 내부 락 대기를 감지하지 못하므로 좀비 프로세스로 판단하지 않고 프로세스(PID)를 안전하게 유지하지만, 실제 사용자 레벨의 코드는 완전히 마비되는 **행(Hung / 먹통)** 상태를 보장하게 된다.  





<br><br>

## 🟢 4. Workaround & Verification (조치 및 검증)  

- **근본적 조치**  
    - 4대 필수 요건 제거하기  
    - 은행원 알고리즘 (Banker's Algorithm)  
        - 에츠허르 다익스트라(Edsger Dijkstra)가 제안한 대표적인 데드락 회피(Avoidance) 알고리즘  
        - 
    - 멀티스레드 성능을 확보하면서 데드락을 예방하려면, 모든 스레드가 락 자원을 획득하는 순서(예: 언제나 A를 락 한 후 B를 락 하도록 고정)를 일치시키는 **락 순서 규칙의 통일** 또는 자원 획득 시도를 일정 시간 내에 제한하는 **타임아웃 락 (Lock Timeout)** 설계를 적용해야 한다.  


- **(과제 기준) 검증 Before & After 비교 결과**  
    - 조치 완료 후 재실행 결과, 자원 락 선점 경쟁이 발생하지 않아 `Thread-A/B/C Completed`가 순차적으로 100% 완료되며 정상 구동됨이 검증되었다.  
    
    | 비교 항목 | Before (조치 전 - 장애) | After (조치 후 - 정상) |  
    | :--- | :--- | :--- |
    | **MULTI_THREAD_ENABLE** | `true` | `false` |  
    | **부팅 판단 결과** | `Concurrency: True [ WARNING ]` | `Concurrency: False [ OK ]` |  
    | **자원 동작 흐름** | 스레드 간 교차 락 선점 경쟁으로 데드락 성립 | 단일 제어선 내에서 차례대로 순차 계산 진행 |  
    | **점유 수치 (RSS)** | `31.55MB`로 소수점까지 완전 고정 정체 | 스레드 완료에 따라 안전하게 자원이 회수되며 정상 변동 |  
    | **최종 동작 결과** | **HUNG (영구 무응답 먹통)** | **Stable (정상 복구 및 업무 100% 완료)** |  



