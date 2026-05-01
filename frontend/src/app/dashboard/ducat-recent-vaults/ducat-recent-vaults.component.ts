import { ChangeDetectionStrategy, ChangeDetectorRef, Component, OnDestroy, OnInit } from '@angular/core';
import { Subscription, timer } from 'rxjs';
import { switchMap } from 'rxjs/operators';
import { DucatApiService } from '@app/services/ducat-api.service';
import { DucatStatsTxItem } from '@interfaces/ducat.interface';

const POLL_INTERVAL_MS = 30_000;
const ROW_LIMIT = 15;

@Component({
  selector: 'app-ducat-recent-vaults',
  templateUrl: './ducat-recent-vaults.component.html',
  styleUrls: ['./ducat-recent-vaults.component.scss'],
  standalone: false,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class DucatRecentVaultsComponent implements OnInit, OnDestroy {
  items: DucatStatsTxItem[] = [];
  loaded = false;
  reachable = true;

  private sub?: Subscription;

  constructor(
    private ducatApi: DucatApiService,
    private cd: ChangeDetectorRef,
  ) {}

  ngOnInit(): void {
    this.sub = timer(0, POLL_INTERVAL_MS)
      .pipe(switchMap(() => this.ducatApi.getStatsTx$(ROW_LIMIT)))
      .subscribe((resp) => {
        this.loaded = true;
        this.reachable = resp !== null;
        this.items = (resp?.data ?? []).slice().sort((a, b) => b.block_time - a.block_time);
        this.cd.markForCheck();
      });
  }

  ngOnDestroy(): void {
    this.sub?.unsubscribe();
  }

  // Map our action strings onto bootstrap badge colors. Same scheme as the
  // tx page banner so the visual identity stays consistent.
  badgeClass(action: string): string {
    switch (action) {
      case 'open':       return 'bg-success';
      case 'borrow':     return 'bg-primary';
      case 'deposit':    return 'bg-primary';
      case 'repay':      return 'bg-warning';
      case 'withdraw':   return 'bg-warning';
      case 'liquidate':  return 'bg-danger';
      case 'close':      return 'bg-danger';
      case 'trim':       return 'bg-info';
      default:           return 'bg-secondary';
    }
  }

  // ms-since-now → "30s", "5m", "2h", "3d"
  timeAgo(blockTime: number): string {
    const seconds = Math.max(0, Math.floor(Date.now() / 1000) - blockTime);
    if (seconds < 60) return `${seconds}s`;
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h`;
    return `${Math.floor(seconds / 86400)}d`;
  }
}
