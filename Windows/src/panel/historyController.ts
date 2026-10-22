import type { ClipItem, PinboardFilter } from "./panelTypes";

export type HistoryScope = { itemType: string | null; pinboardId: string | null; searchText: string };
export type HistoryPage = { items: ClipItem[]; totalCount: number; hasMore: boolean; revision: number };
export type HistoryRepository = {
  list(scope: HistoryScope, limit: number, offset: number): Promise<HistoryPage>;
  pinboards(): Promise<PinboardFilter[]>;
};
export type HistoryState = HistoryPage & {
  scope: HistoryScope; pinboards: PinboardFilter[]; refreshing: boolean; loadingMore: boolean; error: string | null;
};
const PAGE_SIZE = 50;
const MAX_REQUEST = 200;

/** One current query and its explicitly loaded window. No clipboard-content cache. */
export class HistoryController {
  private listeners = new Set<() => void>();
  private generation = 0;
  private started = false;
  private refreshRequested = false;
  private running = false;
  private needsRefresh = true;
  private wantedCount = PAGE_SIZE;
  private state: HistoryState = {
    scope: { itemType: null, pinboardId: null, searchText: "" }, items: [], pinboards: [],
    totalCount: 0, hasMore: false, revision: -1, refreshing: false, loadingMore: false, error: null
  };

  constructor(private repository: HistoryRepository) {}
  snapshot = () => this.state;
  subscribe = (listener: () => void) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; };
  private publish(patch: Partial<HistoryState>) {
    this.state = { ...this.state, ...patch };
    this.listeners.forEach((listener) => listener());
  }
  start() { this.started = true; this.refresh(); }
  stop() { this.started = false; this.generation++; this.refreshRequested = false; }

  setScope(scope: HistoryScope) {
    if (JSON.stringify(scope) === JSON.stringify(this.state.scope)) return;
    this.generation++;
    this.wantedCount = PAGE_SIZE;
    this.publish({ scope, items: [], totalCount: 0, hasMore: false, error: null, loadingMore: false });
    this.refresh();
  }

  invalidate(revision: number) {
    if (revision <= this.state.revision) return;
    this.refresh();
  }

  refresh = () => {
    if (!this.started) return;
    this.generation++;
    this.refreshRequested = true;
    this.needsRefresh = true;
    this.publish({ refreshing: true, loadingMore: false, error: null });
    void this.drainRefreshes();
  };

  private async drainRefreshes() {
    if (this.running) return;
    this.running = true;
    try {
      while (this.started && this.refreshRequested) {
        this.refreshRequested = false;
        const generation = this.generation;
        const scope = { ...this.state.scope };
        const wanted = Math.max(PAGE_SIZE, this.wantedCount);
        try {
          const items: ClipItem[] = [];
          let firstRevision: number | undefined;
          let page: HistoryPage;
          do {
            page = await this.repository.list(scope, Math.min(MAX_REQUEST, wanted - items.length), items.length);
            if (!this.started || generation !== this.generation) break;
            if (firstRevision !== undefined && firstRevision !== page.revision) {
              this.refreshRequested = true;
              break;
            }
            firstRevision = page.revision;
            items.push(...page.items);
            if (!page.hasMore || page.items.length === 0) break;
          } while (items.length < wanted);
          if (!this.started || generation !== this.generation || this.refreshRequested) continue;
          const pinboards = await this.repository.pinboards();
          if (!this.started || generation !== this.generation) continue;
          this.needsRefresh = false;
          this.publish({ items, totalCount: page!.totalCount, hasMore: page!.hasMore,
            revision: page!.revision, pinboards, refreshing: false, error: null });
        } catch {
          if (this.started && generation === this.generation) {
            this.publish({ refreshing: false, error: "历史记录加载失败，请重试" });
          }
        }
      }
    } finally { this.running = false; }
  }

  loadMore = async () => {
    if (!this.started || this.needsRefresh || this.state.refreshing || this.state.loadingMore || !this.state.hasMore) return;
    const generation = this.generation;
    const offset = this.state.items.length;
    this.wantedCount = offset + PAGE_SIZE;
    this.publish({ loadingMore: true, error: null });
    try {
      const page = await this.repository.list(this.state.scope, PAGE_SIZE, offset);
      if (!this.started || generation !== this.generation) return;
      if (page.revision !== this.state.revision) { this.refresh(); return; }
      const known = new Set(this.state.items.map((item) => item.id));
      this.publish({ items: [...this.state.items, ...page.items.filter((item) => !known.has(item.id))],
        totalCount: page.totalCount, hasMore: page.hasMore, loadingMore: false });
    } catch {
      if (this.started && generation === this.generation) {
        this.publish({ loadingMore: false, error: "更多记录加载失败，请重试" });
      }
    }
  };

  updateItem(id: string, update: (item: ClipItem) => ClipItem) {
    this.publish({ items: this.state.items.map((item) => item.id === id ? update(item) : item) });
  }
}
