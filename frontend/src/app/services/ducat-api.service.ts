import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, of } from 'rxjs';
import { catchError } from 'rxjs/operators';
import { DucatTxData, DucatHeightInfo } from '@interfaces/ducat.interface';

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
}
