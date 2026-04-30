import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, of } from 'rxjs';
import { catchError, map } from 'rxjs/operators';
import {
  DucatTxData,
  DucatHeightInfo,
  DucatStatsVolume,
  DucatPriceLatest,
} from '@interfaces/ducat.interface';

@Injectable({
  providedIn: 'root'
})
export class DucatApiService {
  private apiBaseUrl = 'http://localhost:4000';

  constructor(private httpClient: HttpClient) {}

  getTxData$(txid: string): Observable<DucatTxData | null> {
    return this.httpClient
      .get<DucatTxData>(`${this.apiBaseUrl}/api/tx/${txid}`)
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
