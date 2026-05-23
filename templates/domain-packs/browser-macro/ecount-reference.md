# Ecount Chrome 확장프로그램 개발 필수 패턴

> 이 문서는 Ecount ERP 시스템을 대상으로 하는 Chrome 확장프로그램 개발 시
> 반드시 고려해야 할 핵심 패턴과 함정(pitfall)들을 정리한 개발 참고서입니다.

---

## 1. Chrome 팝업 차단 우회 — `window.open()` 금지

### 왜 막히는가?

`window.open()`을 **비동기 컨텍스트**(MutationObserver, Promise `.then()`, `setTimeout`, `setInterval`, `async/await`)에서 호출하면 Chrome이 팝업 차단을 적용합니다.
Chrome은 사용자의 직접 클릭(사용자 제스처)이 없는 팝업을 스팸으로 간주하기 때문입니다.

```javascript
// ❌ 비동기 컨텍스트에서 window.open → Chrome이 차단
const observer = new MutationObserver(() => {
    window.open(url); // 차단됨!
});

fetch(url).then(() => {
    window.open(anotherUrl); // 차단됨!
});
```

### 해결책: Service Worker → `chrome.tabs.create({ active: false })`

Chrome Extension의 Service Worker(백그라운드 스크립트)는 사용자 제스처 제한을 받지 않습니다.
Content Script에서 메시지를 보내고, Service Worker에서 `chrome.tabs.create()`를 호출합니다.
`active: false`를 주면 현재 탭에서 포커스가 이동하지 않습니다(백그라운드 탭 열기).

**Content Script (features/*.js):**
```javascript
let openedTabId = null;

chrome.runtime.sendMessage({ type: 'openSerialLotTab', url: targetUrl }, (response) => {
    if (chrome.runtime.lastError) {
        console.error('탭 열기 실패:', chrome.runtime.lastError.message);
        return;
    }
    if (response && response.tabId) {
        openedTabId = response.tabId;
    }
});

// 작업 완료 후 탭 닫기
if (openedTabId) {
    chrome.runtime.sendMessage({ type: 'closeTab', tabId: openedTabId });
}
```

**service-worker.js:**
```javascript
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
    if (request.type === 'openSerialLotTab') {
        // active: false → 포커스 이동 없이 백그라운드에서 탭 열기
        chrome.tabs.create({ url: request.url, active: false }, (tab) => {
            sendResponse({ success: true, tabId: tab.id });
        });
        return true; // ← 비동기 sendResponse를 유지하기 위해 반드시 필요!
    }

    if (request.type === 'closeTab') {
        chrome.tabs.remove(request.tabId, () => {
            if (chrome.runtime.lastError) {
                console.warn('closeTab 오류 (이미 닫혔을 수 있음):', chrome.runtime.lastError.message);
            }
            sendResponse({ success: true });
        });
        return true; // ← 반드시 필요!
    }
});
```

**manifest.json — `"tabs"` 권한 필수:**
```json
{
    "permissions": ["scripting", "storage", "tabs"]
}
```

### 체크포인트
- 비동기 컨텍스트에서 탭/팝업 열기 → 항상 Service Worker의 `chrome.tabs.create()` 사용
- `active: false` → 포커스 이동 없는 백그라운드 탭
- `sendMessage` 핸들러에서 비동기 응답 시 `return true` 반드시 추가
- manifest.json에 `"tabs"` 권한 추가 필수

---

## 2. Isolated World vs MAIN World — Content Script 격리 문제

### 왜 Ecount 전역 객체에 접근이 안 되는가?

Chrome 확장프로그램의 Content Script는 **Isolated World(격리된 세계)**에서 실행됩니다.
같은 페이지를 보고 있더라도 Ecount 페이지의 JavaScript 환경(전역 객체)과 완전히 분리되어 있습니다.
마치 두 개의 평행한 우주처럼, 같은 DOM은 공유하지만 JavaScript 변수는 공유하지 않습니다.

```javascript
// Content Script에서 (Isolated World)
console.log(window.gridRegistered); // → undefined (접근 불가!)
console.log(window.eFormData);      // → undefined (접근 불가!)
```

### 해결책: `page-world-bridge.js` — MAIN World 스크립트

manifest.json에서 `"world": "MAIN"` 설정으로 Ecount 페이지와 동일한 환경에서 실행되는 스크립트를 추가합니다.
두 World 간 통신은 **CustomEvent**를 통해서만 가능합니다.

**manifest.json:**
```json
{
    "content_scripts": [
        {
            "matches": ["*://*.ecount.com/*"],
            "js": ["page-world-bridge.js"],
            "world": "MAIN",
            "run_at": "document_idle"
        }
    ]
}
```

**page-world-bridge.js (MAIN World — Ecount 전역 객체 직접 접근 가능):**
```javascript
window.addEventListener('__ecExt_setcell_request', (event) => {
    const { gridKey, colId, rowKey, value } = event.detail;

    if (!window.gridRegistered) {
        window.dispatchEvent(new CustomEvent('__ecExt_setcell_result', {
            detail: { success: false, error: 'gridRegistered 없음', availableKeys: [] }
        }));
        return;
    }

    const grid = window.gridRegistered[gridKey];
    if (!grid) {
        const availableKeys = Object.keys(window.gridRegistered);
        console.warn(`[Bridge] gridRegistered 없음. gridKey: ${gridKey} 사용 가능한 키:`, availableKeys);
        window.dispatchEvent(new CustomEvent('__ecExt_setcell_result', {
            detail: { success: false, error: `gridKey '${gridKey}' 없음`, availableKeys }
        }));
        return;
    }

    grid.setCell(colId, rowKey, value);
    window.dispatchEvent(new CustomEvent('__ecExt_setcell_result', {
        detail: { success: true }
    }));
});
```

**Content Script에서 bridge 호출:**
```javascript
// Content Script → MAIN World 요청
window.dispatchEvent(new CustomEvent('__ecExt_setcell_request', {
    detail: { gridKey, colId, rowKey, value }
}));

// MAIN World → Content Script 결과 수신
window.addEventListener('__ecExt_setcell_result', (event) => {
    if (event.detail.success) {
        console.log('setCell 성공');
    } else {
        console.error('setCell 실패:', event.detail.error,
                      '사용 가능한 키:', event.detail.availableKeys);
    }
}, { once: true });
```

### 체크포인트
- Content Script = Isolated World → Ecount의 `window.*` (gridRegistered 등) 접근 불가
- `"world": "MAIN"` 스크립트 = 페이지와 동일 환경 → Ecount 전역 객체 접근 가능
- 두 World 간 통신: **CustomEvent**를 통해서만 가능

---

## 3. DOM 수정 vs 내부 모델 수정 — `setCell()` 필수

### 왜 DOM 수정이 사라지는가?

Ecount 그리드는 자체 **내부 데이터 모델**을 가집니다.
DOM(`<span>`, `<input>`)을 직접 수정하면 화면에는 보이지만,
셀에 포커스를 가져가는 순간 그리드가 **내부 모델에서 값을 다시 렌더링**하여 변경사항이 사라집니다.

마치 화이트보드에 써놓은 것과 컴퓨터 파일에 저장한 것의 차이입니다.
DOM 수정 = 화이트보드에 쓰기 (지워질 수 있음)
setCell = 컴퓨터 파일에 저장 (영구 저장)

```javascript
// ❌ DOM만 수정 → 포커스 시 0으로 리셋됨!
const span = cell.querySelector('span');
span.textContent = '100'; // 화면에는 보이지만 실제로는 저장 안 됨
```

### 해결책: `window.gridRegistered[gridKey].setCell()` 호출

내부 모델에 값을 저장하고, DOM도 함께 업데이트합니다:

```javascript
// 1. bridge를 통해 setCell 요청 (내부 모델 업데이트 — 영구 저장)
window.dispatchEvent(new CustomEvent('__ecExt_setcell_request', {
    detail: { gridKey, colId, rowKey, value }
}));

// 2. DOM도 업데이트 (즉각적인 시각적 피드백)
const input = cell.querySelector('input');
if (input) {
    input.value = value;
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
} else {
    const span = cell.querySelector('span');
    if (span) span.textContent = value;
}
```

> **⚠️ 중요:** `setCell` 호출은 `input` 엘리먼트 유무와 **무관하게 항상 실행**해야 합니다.
> `if (input) { setCell(...) }` 패턴은 셀이 비활성 상태(input이 없는 경우)에 setCell이 건너뛰어지는 버그를 만듭니다.

---

## 4. Ecount 특유 DOM 속성명 & gridKey 구조

### 속성명 주의사항

| 속성 | **올바른 이름** | ~~잘못된 이름~~ |
|------|----------------|----------------|
| 컬럼 ID | `data-columnid` | ~~`data-column-id`~~ (하이픈 있음 → null 반환) |
| 행 키 | `data-key` | |
| 팝업 ID | `data-popup-id` | (팝업 컨테이너 div에 있음) |

```javascript
// ✅ Ecount 실제 속성명 (하이픈 없음)
const colId = cell.getAttribute('data-columnid'); // "sale012.prodqty"

// ❌ null 반환! Ecount에는 이 속성이 없음
const colId = cell.getAttribute('data-column-id'); // null!
```

### colId 조회 — 폴백 체인 사용 권장

```javascript
const colId = cell.getAttribute('data-cid')
    || cell.getAttribute('data-columnid')      // ← Ecount 실제 속성명
    || cell.getAttribute('data-column-id')
    || cell.getAttribute('data-id')
    || (input ? input.getAttribute('data-cid') : null)
    || (input ? input.getAttribute('data-columnid') : null)
    || (targetTh ? targetTh.getAttribute('data-columnid') : null)
    || (targetTh ? targetTh.getAttribute('data-id') : null);
```

### gridKey 구성 — `popupId + gridEl.id`

```javascript
// ※ gridKey = popupId + gridEl.id (연결, 구분자 없음)
// 예: "ES028P_1606128064818" + "dataGridES028P"
//   = "ES028P_1606128064818dataGridES028P"

const popupEl = row.closest('div[data-popup-id]');
const popupId = popupEl ? popupEl.getAttribute('data-popup-id') : null;
const gridEl  = popupEl ? popupEl.querySelector('[id^="dataGrid"]') : null;
const gridKey = (popupId && gridEl) ? (popupId + gridEl.id) : null;

// ❌ gridEl.id만으로는 부족 → window.gridRegistered에서 키를 못 찾음
// const gridKey = gridEl.id; // 틀림! "dataGridES028P"로만 되어 찾지 못함
```

> **gridKey 확인 방법:** `page-world-bridge.js`가 콘솔에 출력하는
> `"[Bridge] 사용 가능한 키: [...]"` 로그에서 실제 키 형식을 확인합니다.

### rowKey 조회

```javascript
const rowKey = targetCell.getAttribute('data-key')
    || row.querySelector('td:nth-child(2) span')?.textContent?.trim();
```

### Ecount 팝업 DOM 구조

```html
<div data-popup-id="ES028P_1606128064818">      ← popupId
    <div id="dataGridES028P">                    ← gridEl.id
        <table>
            <thead>
                <tr>
                    <th data-columnid="sale012.prodqty">입력수량</th>  ← targetTh
            <tbody>
                <tr data-key="rowKey123">        ← rowKey
                    <td data-columnid="sale012.prodqty">  ← colId (하이픈 없음!)
```

---

## 5. 진단 로그 패턴

### colId가 null인 경우

```javascript
if (!colId) {
    console.log('[진단] cell 속성:',
        [...cell.attributes].map(a => `${a.name}="${a.value}"`).join(', '));
    console.log('[진단] th 속성:',
        targetTh ? [...targetTh.attributes].map(a => `${a.name}="${a.value}"`).join(', ') : 'null');
}
// → 로그에서 실제 속성명 확인 후 코드 수정
```

### gridKey가 잘못된 경우

bridge.js가 출력하는 로그에서 실제 키 형식을 확인합니다:
```
[Bridge] gridRegistered 없음. gridKey: dataGridES028P 사용 가능한 키: ["ES028P_1606128064818dataGridES028P"]
```
→ `gridKey = popupId + gridEl.id` 형식으로 코드를 수정합니다.

---

## 6. localStorage 기반 탭 간 통신

팝업 탭(ES028P)과 검색 탭(E040619) 간 데이터 교환:

```javascript
// [ES028P] 요청 탭 — 요청 쓰기
const requestTimestamp = Date.now();
localStorage.setItem('serialLotSearchRequest', JSON.stringify({
    barcode: targetBarcode,
    timestamp: requestTimestamp
}));

// [E040619] 검색 탭 — 결과 쓰기
localStorage.setItem('serialLotSearchResult', JSON.stringify({
    found: true,
    data: resultData,
    timestamp: Date.now()
}));

// [ES028P] 요청 탭 — 결과 폴링
const interval = setInterval(() => {
    const result = localStorage.getItem('serialLotSearchResult');
    if (result) {
        const parsed = JSON.parse(result);
        if (parsed.timestamp > requestTimestamp) {
            clearInterval(interval);
            processResult(parsed);
        }
    }
}, 500);
```

---

## 7. Template Literal 문법 주의

`${...}` 표현식에서 닫는 `}`의 위치 실수:

```javascript
// ❌ 틀린 예 → SyntaxError: Missing } in template expression
const msg = `값: ${x > 0 ? '양수' : '(없음)'"}`; // '}' 위치가 따옴표 뒤에 와야 함

// ✅ 올바른 예
const msg = `값: ${x > 0 ? '양수' : '(없음)'}"`; // 따옴표 전에 '}' 닫기
```

---

## 빠른 체크리스트

Ecount Chrome 확장프로그램 코드를 작성/수정할 때마다 확인:

- [ ] 비동기 컨텍스트에서 탭 열기 → `chrome.tabs.create()` (Service Worker 경유)
- [ ] manifest.json에 `"tabs"` 권한 추가
- [ ] `sendMessage` 핸들러에서 비동기 응답 시 `return true` 확인
- [ ] Content Script에서 Ecount 전역 객체 필요 → `page-world-bridge.js` (MAIN World) 경유
- [ ] 그리드 값 변경 → `setCell()` 내부 모델 업데이트 + DOM 업데이트 병행
- [ ] `setCell` 호출은 input 유무와 무관하게 항상 실행
- [ ] `data-columnid` (하이픈 없음) 확인
- [ ] `gridKey = popupId + gridEl.id` 형식 확인 (gridEl.id 단독 사용 금지)
- [ ] Template literal `${...}` 닫는 `}` 위치 확인
