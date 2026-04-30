// Type declarations matching the real rust-gbt's auto-generated NAPI-RS
// d.ts. Used only at compile time; the runtime stub throws if any of
// these are instantiated.
export interface ThreadTransaction {
  uid: number;
  order: number;
  fee: number;
  weight: number;
  sigops: number;
  effectiveFeePerVsize: number;
  inputs: Array<number>;
}
export interface ThreadAcceleration {
  uid: number;
  delta: number;
}
export class GbtGenerator {
  constructor(maxBlockWeight: number, maxBlocks: number);
  make(mempool: Array<ThreadTransaction>, accelerations: Array<ThreadAcceleration>, maxUid: number): Promise<GbtResult>;
  update(newTxs: Array<ThreadTransaction>, removeTxs: Array<number>, accelerations: Array<ThreadAcceleration>, maxUid: number): Promise<GbtResult>;
}
export class GbtResult {
  blocks: Array<Array<number>>;
  blockWeights: Array<number>;
  clusters: Array<Array<number>>;
  rates: Array<Array<number>>;
  overflow: Array<number>;
  constructor(blocks: Array<Array<number>>, blockWeights: Array<number>, clusters: Array<Array<number>>, rates: Array<Array<number>>, overflow: Array<number>);
}
