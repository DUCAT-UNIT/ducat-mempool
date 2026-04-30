import { ChangeDetectionStrategy, ChangeDetectorRef, Component, OnDestroy, OnInit } from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import { Subscription } from 'rxjs';
import { DucatApiService } from '@app/services/ducat-api.service';
import {
  DucatAssetProfile,
  DucatProtoMember,
  DucatProtoProfile,
  DucatProtoTerm,
} from '@interfaces/ducat.interface';

const GUARDIAN_GROUP = 21;
const ORACLE_GROUP = 22;

// AnchorTermTag enum values, kept in sync with
// protocol-sdk/.../contract/anchor/term.rs.
const TERM_LABELS: Record<number, { label: string; format?: 'rate' | 'thold' | 'sats' | 'cents' | 'time' }> = {
  200: { label: 'Governance proposal lock time', format: 'time' },
  201: { label: 'Governance token asset id' },
  202: { label: 'Governance vote lock time', format: 'time' },
  203: { label: 'Governance voting threshold', format: 'rate' },
  204: { label: 'Governance quorum threshold', format: 'rate' },
  221: { label: 'Price bucket min' },
  222: { label: 'Price bucket max' },
  223: { label: 'Price bucket size' },
  241: { label: 'Liquidation tax', format: 'rate' },
  242: { label: 'Liquidation threshold', format: 'thold' },
  243: { label: 'Reserve pubkey' },
  244: { label: 'Reserve value min', format: 'sats' },
  245: { label: 'Subsidy increment' },
  246: { label: 'Subsidy threshold' },
  247: { label: 'UNIT asset id' },
  248: { label: 'UNIT balance min', format: 'cents' },
  249: { label: 'Vault ratio min', format: 'rate' },
  250: { label: 'Vault value min', format: 'sats' },
};

interface DisplayTerm {
  key: number;
  label: string;
  values: string[];
}

@Component({
  selector: 'app-ducat-anchor',
  templateUrl: './ducat-anchor.component.html',
  styleUrls: ['./ducat-anchor.component.scss'],
  standalone: false,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class DucatAnchorComponent implements OnInit, OnDestroy {
  contractId: string | null = null;
  proto: DucatProtoProfile | null = null;
  loading = true;
  reachable = true;

  private subs: Subscription[] = [];

  constructor(
    private route: ActivatedRoute,
    private ducatApi: DucatApiService,
    private cd: ChangeDetectorRef,
  ) {}

  ngOnInit(): void {
    this.subs.push(this.route.paramMap.subscribe((params) => {
      this.contractId = params.get('contract_id');
      this.cd.markForCheck();
    }));
    this.subs.push(this.ducatApi.getProtoLatest$().subscribe((proto) => {
      this.loading = false;
      this.reachable = proto !== null;
      this.proto = proto;
      this.cd.markForCheck();
    }));
  }

  ngOnDestroy(): void {
    this.subs.forEach((s) => s.unsubscribe());
  }

  // The route param could match the BIP340 contract_id, the anchor_id, or
  // the anchor_txid. With only one active contract per validator, this is
  // mostly a sanity check.
  get matchesRoute(): boolean {
    if (!this.proto || !this.contractId) return false;
    const cid = this.contractId.toLowerCase();
    return [this.proto.contract_id, this.proto.anchor_id, this.proto.anchor_txid]
      .some(v => v && v.toLowerCase() === cid);
  }

  get assets(): DucatAssetProfile[] {
    return this.proto?.proto_assets ?? [];
  }

  get guardians(): DucatProtoMember[] {
    return (this.proto?.proto_members ?? []).filter((m) => m.group === GUARDIAN_GROUP);
  }

  get oracles(): DucatProtoMember[] {
    return (this.proto?.proto_members ?? []).filter((m) => m.group === ORACLE_GROUP);
  }

  get displayTerms(): DisplayTerm[] {
    if (!this.proto) return [];
    return this.proto.proto_terms.map((t) => this.formatTerm(t));
  }

  private formatTerm(term: DucatProtoTerm): DisplayTerm {
    const meta = TERM_LABELS[term.key] || { label: `Unknown (${term.key})` };
    const values = term.value.map((v) => this.formatValue(v, meta.format));
    return { key: term.key, label: meta.label, values };
  }

  private formatValue(v: any, format?: string): string {
    if (v === null || v === undefined) return '';
    switch (format) {
      case 'rate':
        return `${(Number(v) * 100).toLocaleString(undefined, { maximumFractionDigits: 2 })}%`;
      case 'thold':
        // LiquidationThold is fraction (e.g. 1.5 = 150%); display both.
        return `${Number(v).toLocaleString(undefined, { maximumFractionDigits: 2 })} (${(Number(v) * 100).toFixed(0)}%)`;
      case 'sats':
        return `${(Number(v) / 1e8).toLocaleString(undefined, { maximumFractionDigits: 8 })} BTC`;
      case 'cents':
        return `${(Number(v) / 100).toLocaleString(undefined, { maximumFractionDigits: 2 })} UNIT`;
      case 'time':
        // Bitcoin block count (terms are usually in blocks for time fields).
        return `${Number(v).toLocaleString()} blocks`;
      default:
        return typeof v === 'object' ? JSON.stringify(v) : String(v);
    }
  }
}
