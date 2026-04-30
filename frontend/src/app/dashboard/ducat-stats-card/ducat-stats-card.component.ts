import { ChangeDetectionStrategy, ChangeDetectorRef, Component, OnDestroy, OnInit } from '@angular/core';
import { Subscription, forkJoin, timer } from 'rxjs';
import { switchMap } from 'rxjs/operators';
import { DucatApiService } from '@app/services/ducat-api.service';
import {
  DucatPriceLatest,
  DucatStatsVolume,
} from '@interfaces/ducat.interface';

const POLL_INTERVAL_MS = 60_000;

@Component({
  selector: 'app-ducat-stats-card',
  templateUrl: './ducat-stats-card.component.html',
  styleUrls: ['./ducat-stats-card.component.scss'],
  standalone: false,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class DucatStatsCardComponent implements OnInit, OnDestroy {
  total: DucatStatsVolume | null = null;
  day: DucatStatsVolume | null = null;
  price: DucatPriceLatest | null = null;
  loaded = false;
  reachable = true;

  private sub?: Subscription;

  constructor(
    private ducatApi: DucatApiService,
    private cd: ChangeDetectorRef,
  ) {}

  ngOnInit(): void {
    this.sub = timer(0, POLL_INTERVAL_MS)
      .pipe(switchMap(() => forkJoin({
        total: this.ducatApi.getStatsVolume$(),
        day: this.ducatApi.getStatsVolume$('day'),
        price: this.ducatApi.getPriceLatest$(),
      })))
      .subscribe(({ total, day, price }) => {
        this.total = total;
        this.day = day;
        this.price = price;
        this.loaded = true;
        this.reachable = total !== null;
        this.cd.markForCheck();
      });
  }

  ngOnDestroy(): void {
    this.sub?.unsubscribe();
  }

  // Formatting helpers (cents → UNIT, sats → BTC) intentionally inline
  // so the template stays declarative.
  unitFromCents(cents: number): number {
    return cents / 100;
  }
}
