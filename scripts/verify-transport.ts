/**
 * Focused check that callRpc retries transport failures but not PostgREST
 * errors, without needing a live Supabase connection.
 *
 * Run with: npx tsx scripts/verify-transport.ts
 */

type RpcResponse<T> = { data: T | null; error: { message: string } | null };

const delays: number[] = [];
const sleep = (ms: number) => {
  delays.push(ms);
  return Promise.resolve();
};

// Mirror of lib/rq/transport.ts, injected with a fake timer.
function isTransportError(error: { message: string } | null): boolean {
  if (!error) return false;
  const message = error.message.toLowerCase();
  return (
    message.includes("fetch failed") ||
    message.includes("network") ||
    message.includes("econnreset") ||
    message.includes("etimedout") ||
    message.includes("socket hang up") ||
    message.includes("aborted")
  );
}

const RETRY_DELAYS_MS = [150, 400, 900];

async function callRpc<T>(
  fn: () => PromiseLike<RpcResponse<T>>,
  what: string,
): Promise<T> {
  let lastError: { message: string } | null = null;

  for (let attempt = 0; attempt <= RETRY_DELAYS_MS.length; attempt += 1) {
    const { data, error } = await fn();
    if (!error) return data as T;

    lastError = error;
    if (!isTransportError(error)) {
      throw new Error(`${what} failed: ${error.message}`);
    }

    const delay = RETRY_DELAYS_MS[attempt];
    if (delay === undefined) break;
    await sleep(delay);
  }

  throw new Error(
    `${what} failed: ${lastError?.message ?? "network unreachable"}. ` +
      `The database did not respond after ${RETRY_DELAYS_MS.length + 1} attempts.`,
  );
}

let failures = 0;
function check(name: string, ok: boolean, detail = "") {
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? ` — ${detail}` : ""}`);
  if (!ok) failures += 1;
}

async function main() {
// 1. Success on first try: one call, no retries.
{
  delays.length = 0;
  let calls = 0;
  const out = await callRpc<string[]>(
    () => {
      calls += 1;
      return Promise.resolve({ data: ["a"], error: null });
    },
    "test",
  );
  check("success returns immediately", calls === 1 && out[0] === "a", `calls=${calls}`);
}

// 2. A transient failure followed by success is retried and recovers.
{
  delays.length = 0;
  let calls = 0;
  const out = await callRpc<string>(
    () => {
      calls += 1;
      if (calls === 1) return Promise.resolve({ data: null, error: { message: "TypeError: fetch failed" } });
      return Promise.resolve({ data: "recovered", error: null });
    },
    "test",
  );
  check(
    "one transient error then success recovers",
    calls === 2 && out === "recovered",
    `calls=${calls}, delays=${JSON.stringify(delays)}`,
  );
  check("backoff starts short", delays[0] === 150, `delays=${JSON.stringify(delays)}`);
}

// 3. Persistent transport failure gives up after the configured attempts.
{
  delays.length = 0;
  let calls = 0;
  let message = "";
  try {
    await callRpc<never>(
      () => {
        calls += 1;
        return Promise.resolve({ data: null, error: { message: "TypeError: fetch failed" } });
      },
      "rq_staff_list_rate_items",
    );
  } catch (err) {
    message = (err as Error).message;
  }
  check(
    "persistent transport failure gives up",
    calls === RETRY_DELAYS_MS.length + 1,
    `calls=${calls}`,
  );
  check(
    "give-up message is actionable",
    message.includes("did not respond after 4 attempts"),
    message,
  );
}

// 4. A PostgREST error is a real answer and must NOT be retried.
{
  delays.length = 0;
  let calls = 0;
  let message = "";
  try {
    await callRpc<never>(
      () => {
        calls += 1;
        return Promise.resolve({ data: null, error: { message: "permission denied for function rq_my_contractor_id" } });
      },
      "rq_staff_list_rate_items",
    );
  } catch (err) {
    message = (err as Error).message;
  }
  check("postgres error is not retried", calls === 1, `calls=${calls}`);
  check("postgres error surfaces verbatim", message.includes("permission denied"), message);
  check("no backoff slept for a postgres error", delays.length === 0, `delays=${JSON.stringify(delays)}`);
}

// 5. The specific shapes seen in production are classified as transport errors.
for (const msg of [
  "TypeError: fetch failed",
  "network error",
  "ECONNRESET",
  "ETIMEDOUT",
  "socket hang up",
  "This operation was aborted",
]) {
  check(`classifies "${msg}" as transport`, isTransportError({ message: msg }));
}
for (const msg of [
  "Quote not found",
  "Not authorised",
  "Please answer the required questions before submitting.",
  "operator does not exist: text ->> unknown",
]) {
  check(`classifies "${msg}" as a real error`, !isTransportError({ message: msg }));
}

console.log(failures === 0 ? "\nall checks passed" : `\n${failures} check(s) failed`);
process.exit(failures === 0 ? 0 : 1);
}

main();
