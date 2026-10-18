// Type-check shim for running `tsc` locally; the Edge runtime provides the real Deno global.
declare namespace Deno {
  function serve(handler: (req: Request) => Response | Promise<Response>): void;
  const env: { get(name: string): string | undefined; toObject(): Record<string, string> };
}
