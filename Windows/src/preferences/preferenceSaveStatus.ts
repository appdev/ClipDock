/** Retains every notice from one user save cycle until the next cycle starts. */
export class PreferenceSaveStatus {
  private pending = 0;
  private notices: string[] = [];

  get hasPending(): boolean { return this.pending > 0; }
  get message(): string | null { return this.notices.length ? this.notices.join("；") : null; }

  begin(): void {
    if (!this.hasPending) this.notices = [];
    this.pending++;
  }

  observe(notice: string | null): void {
    if (notice && !this.notices.includes(notice)) this.notices.push(notice);
  }

  complete(notice: string | null): void {
    this.observe(notice);
    this.pending--;
  }
}
