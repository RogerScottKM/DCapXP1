type TaskFactory<T> = () => Promise<T>;

const lanes = new Map<string, Promise<unknown>>();

export async function runSerializedByKey<T>(
  key: string,
  taskFactory: TaskFactory<T>,
): Promise<T> {
  const previous = lanes.get(key) ?? Promise.resolve();

  const run = previous.catch(() => undefined).then(taskFactory);
  const tracked = run.finally(() => {
    if (lanes.get(key) === tracked) {
      lanes.delete(key);
    }
  });

  lanes.set(key, tracked);
  return tracked;
}

export function buildSymbolModeKey(symbol: string, mode: string): string {
  return `${symbol}:${mode}`;
}

export function getSerializedLaneCount(): number {
  return lanes.size;
}

export function resetSerializedDispatchForTests(): void {
  lanes.clear();
}
