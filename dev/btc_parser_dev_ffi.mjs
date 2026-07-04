export function exitFailure() {
  if (
    typeof globalThis.Deno === "object" &&
    typeof globalThis.Deno.exit === "function"
  ) {
    globalThis.Deno.exit(1);
  }

  if (
    typeof globalThis.process === "object" &&
    typeof globalThis.process.exit === "function"
  ) {
    globalThis.process.exit(1);
  }

  throw new Error("Unable to exit the fuzz harness with a failure status");
}
