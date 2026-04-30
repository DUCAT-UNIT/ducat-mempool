import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, of } from 'rxjs';
import { catchError, map, shareReplay } from 'rxjs/operators';
import {
  DucatTxData,
  DucatHeightInfo,
  DucatStatsVolume,
  DucatPriceLatest,
  DucatProtoProfile,
  DucatVaultProfile,
} from '@interfaces/ducat.interface';

@Injectable({
  providedIn: 'root'
})
export class DucatApiService {
  // Relative path: nginx (or the Angular dev proxy) routes /ducat-api/* to
  // the Ducat validator's REST API. Strips the cross-origin browser request
  // we'd otherwise have against http://localhost:4000.
  private apiBaseUrl = '/ducat-api';
  // Proto profile changes only when the anchor contract is republished
  // (rare). Cache for the lifetime of the service, refreshable on demand.
  private protoCache$?: Observable<DucatProtoProfile | null>;

  constructor(private httpClient: HttpClient) {}

  getTxData$(txid: string): Observable<DucatTxData | null> {
    return this.httpClient
      .get<DucatTxData>(`${this.apiBaseUrl}/api/tx/${txid}`)
      .pipe(catchError(() => of(null)));
  }

  getVaultLatest$(vaultId: string): Observable<DucatVaultProfile | null> {
    return this.httpClient
      .get<DucatVaultProfile>(`${this.apiBaseUrl}/api/vault/${vaultId}/latest`)
      .pipe(catchError(() => of(null)));
  }

  getHeight$(): Observable<DucatHeightInfo | null> {
    return this.httpClient
      .get<DucatHeightInfo>(`${this.apiBaseUrl}/api/height`)
      .pipe(catchError(() => of(null)));
  }

  getStatsVolume$(timeSpan?: string): Observable<DucatStatsVolume | null> {
    const url = timeSpan
      ? `${this.apiBaseUrl}/api/stats/volume?time_span=${encodeURIComponent(timeSpan)}`
      : `${this.apiBaseUrl}/api/stats/volume`;
    return this.httpClient
      .get<DucatStatsVolume>(url)
      .pipe(catchError(() => of(null)));
  }

  getProtoLatest$(forceRefresh = false): Observable<DucatProtoProfile | null> {
    if (forceRefresh || !this.protoCache$) {
      this.protoCache$ = this.httpClient
        .get<DucatProtoProfile>(`${this.apiBaseUrl}/api/proto/latest`)
        .pipe(
          catchError(() => of(null)),
          shareReplay(1),
        );
    }
    return this.protoCache$;
  }

  getPriceLatest$(): Observable<DucatPriceLatest | null> {
    // Endpoint returns an array (0 or 1 items); flatten to single record.
    return this.httpClient
      .get<DucatPriceLatest[]>(`${this.apiBaseUrl}/api/price/latest`)
      .pipe(
        map((arr) => (arr && arr.length > 0 ? arr[0] : null)),
        catchError(() => of(null)),
      );
  }
}
