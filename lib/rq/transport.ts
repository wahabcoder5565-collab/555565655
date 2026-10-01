/**
 * Shared RPC transport helpers.
 *
 * Two separate failure modes have to be distinguished here.
 *
 * 1. PostgREST failures (bad input, no data, not authorised) come back in the
 *    response body as `error` with a useful message. These are real answers and
 *    must surface immediately without a retry.
 *
 * 2. Transport failures reach us as `TypeError: fetch failed` instead, because
 *    the request never completed. The dev server's connection to Supabase
 *    stalls intermittently (observed: a 25 s timeout followed by a 16 s
 *    response, then sub-second responses). Those are worth retrying, so they are
 *    retried a few times with a short backoff before being given up on.
 */

/** Network-level errors that are worth a retry. */
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

export async function callRpc<T>(
  fn: () => PromiseLike<{ data: T | null; error: { message: string } | null }>,
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

    console.warn(
      `${what}: transport error (${error.message}), retrying in ${delay}ms ` +
        `(attempt ${attempt + 1}/${RETRY_DELAYS_MS.length + 1})`,
    );
    await new Promise((resolve) => setTimeout(resolve, delay));
  }

  throw new Error(
    `${what} failed: ${lastError?.message ?? "network unreachable"}. ` +
      `The database did not respond after ${RETRY_DELAYS_MS.length + 1} attempts.`,
  );
}