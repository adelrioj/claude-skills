# Receipt Export — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a CSV receipt-export endpoint that streams a user's receipts for a given date range, gated behind the existing `receipts:read` scope.

**Architecture:** Reuse the existing `ReceiptRepository.findByUser` query. Add a thin `ReceiptCsvSerializer` that streams rows via a `Readable` to avoid buffering large result sets. Mount the new route under the existing `/api/v1/receipts` controller with the same auth middleware.

**Tech Stack:** Node.js 20, Fastify 4, Prisma, csv-stringify for streaming serialization, vitest for tests.

**Spec:** `docs/superpowers/specs/2026-05-23-receipt-export-design.md`

---

## File Structure

**Create:**
- `src/receipts/csv-serializer.ts` — streaming CSV row serializer
- `src/receipts/export.route.ts` — Fastify route handler
- `tests/receipts/csv-serializer.test.ts`
- `tests/receipts/export.route.test.ts`

**Modify:**
- `src/receipts/index.ts` — register the new route

---

## Task 1: CSV serializer with streaming output

**Files:**
- Create: `src/receipts/csv-serializer.ts`
- Test: `tests/receipts/csv-serializer.test.ts`

The serializer takes an async iterable of `Receipt` rows and yields CSV strings. Header row is emitted exactly once; rows are escaped per RFC 4180. No buffering — every yielded chunk is at most one row.

- [ ] **Step 1: Write the failing test**

```typescript
import { describe, it, expect } from "vitest";
import { serializeReceipts } from "../../src/receipts/csv-serializer";

describe("serializeReceipts", () => {
  it("emits header then rows", async () => {
    const rows = [{ id: "r1", total: 12.5, currency: "USD" }];
    const out: string[] = [];
    for await (const chunk of serializeReceipts(rows)) out.push(chunk);
    expect(out[0]).toBe("id,total,currency\n");
    expect(out[1]).toBe("r1,12.5,USD\n");
  });
});
```

- [ ] **Step 2: Run the test, verify it fails**

```bash
pnpm vitest run tests/receipts/csv-serializer.test.ts
```

Expected: FAIL with "Cannot find module '../../src/receipts/csv-serializer'".

- [ ] **Step 3: Implement minimal serializer**

```typescript
export async function* serializeReceipts(rows: Iterable<Receipt>) {
  yield "id,total,currency\n";
  for (const r of rows) yield `${r.id},${r.total},${r.currency}\n`;
}
```

- [ ] **Step 4: Run the test, verify it passes**

```bash
pnpm vitest run tests/receipts/csv-serializer.test.ts
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/receipts/csv-serializer.ts tests/receipts/csv-serializer.test.ts
git commit -m "feat(receipts): add streaming CSV serializer"
```

---

## Task 2: Export route handler

**Files:**
- Create: `src/receipts/export.route.ts`
- Modify: `src/receipts/index.ts`
- Test: `tests/receipts/export.route.test.ts`

The route accepts `?from=ISO&to=ISO`, validates the range is ≤ 90 days, and streams the serializer output as `text/csv`. 401 if no `receipts:read` scope; 400 if range invalid.

- [ ] **Step 1: Write the failing test**

```typescript
import { build } from "../helpers/app";

it("returns 401 without scope", async () => {
  const app = await build();
  const res = await app.inject({ method: "GET", url: "/api/v1/receipts/export" });
  expect(res.statusCode).toBe(401);
});
```

- [ ] **Step 2: Run, verify failure**

Run: `pnpm vitest run tests/receipts/export.route.test.ts`
Expected: FAIL (route not registered yet).

- [ ] **Step 3: Implement route and register it**

(handler omitted for fixture brevity — real plan would include full code)

- [ ] **Step 4: Run the full test suite**

```bash
pnpm test
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/receipts/export.route.ts src/receipts/index.ts tests/receipts/export.route.test.ts
git commit -m "feat(receipts): add CSV export route"
```

---

## Task 3: Smoke test against staging

**Files:**
- (no code changes — manual verification only)

- [ ] **Step 1: Deploy to staging and curl the endpoint**

```bash
curl -H "Authorization: Bearer $STAGING_TOKEN" \
  "https://staging.example.com/api/v1/receipts/export?from=2026-05-01&to=2026-05-20" \
  -o /tmp/receipts.csv
wc -l /tmp/receipts.csv
```

Expected: file downloads successfully. Inspect the first 5 rows manually to confirm header format and that currency codes look sane. If any row has an unescaped comma or quote inside the `merchant_name` field, fix the serializer's RFC 4180 escaping before merging.

- [ ] **Step 2: Commit any escaping fixes**

```bash
git add src/receipts/csv-serializer.ts
git commit -m "fix(receipts): tighten RFC 4180 escaping in CSV serializer"
```
