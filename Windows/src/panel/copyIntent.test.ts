import { describe, expect, it } from "vitest";
import { CopyIntentController } from "./copyIntent";

describe("copy intents", () => {
  it("invalidates a slow previous preparation when a newer copy is accepted", async () => {
    const intents = new CopyIntentController();
    let finish!: () => void;
    const old = intents.begin();
    const waiting = new Promise<void>((resolve) => { finish = resolve; });
    const writes: number[] = [];
    const first = waiting.then(() => { if (intents.isCurrent(old)) writes.push(old); });
    const next = intents.begin();
    if (intents.isCurrent(next)) writes.push(next);
    finish();
    await first;
    expect(writes).toEqual([next]);
  });

  it("cancels preparation without depending on wall-clock time", () => {
    const first = new CopyIntentController();
    const id = first.begin();
    expect(first.cancel()).toBeGreaterThan(id);
    expect(first.isCurrent(id)).toBe(false);
    expect(first.begin()).toBeGreaterThan(id);
  });
});
