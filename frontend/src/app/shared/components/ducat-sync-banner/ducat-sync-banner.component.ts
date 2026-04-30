import { ChangeDetectionStrategy, ChangeDetectorRef, Component, OnDestroy, OnInit } from '@angular/core';
import { Subscription, timer } from 'rxjs';
import { switchMap } from 'rxjs/operators';
import { DucatApiService } from '@app/services/ducat-api.service';
import { DucatHeightInfo } from '@interfaces/ducat.interface';

const POLL_INTERVAL_MS = 15_000;
// Lag below this is normal: the validator processes a block shortly after
// Bitcoin Core sees its tip, so a 1-block transient gap is expected.
const LAG_THRESHOLD = 2;

@Component({
  selector: 'app-ducat-sync-banner',
  templateUrl: './ducat-sync-banner.component.html',
  styleUrls: ['./ducat-sync-banner.component.scss'],
  standalone: false,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class DucatSyncBannerComponent implements OnInit, OnDestroy {
  height: DucatHeightInfo | null = null;
  private sub?: Subscription;

  constructor(
    private ducatApi: DucatApiService,
    private cd: ChangeDetectorRef,
  ) {}

  ngOnInit(): void {
    this.sub = timer(0, POLL_INTERVAL_MS)
      .pipe(switchMap(() => this.ducatApi.getHeight$()))
      .subscribe((h) => {
        this.height = h;
        this.cd.markForCheck();
      });
  }

  ngOnDestroy(): void {
    this.sub?.unsubscribe();
  }

  get lag(): number {
    if (!this.height) return 0;
    return Math.max(0, this.height.remote_height - this.height.scanned_height);
  }

  get visible(): boolean {
    return this.height !== null && this.lag >= LAG_THRESHOLD;
  }
}
