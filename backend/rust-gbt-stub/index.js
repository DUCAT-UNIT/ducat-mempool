// Stub of the rust-gbt NAPI module. Backend imports these symbols at
// module load time; RUST_GBT=false in the runtime config keeps them
// from being instantiated. If you do hit one, RUST_GBT was left on.
const STUB_ERR = 'rust-gbt stub: build the Rust NAPI addon, or set MEMPOOL.RUST_GBT=false in backend config';

class GbtGenerator {
  constructor() { throw new Error(STUB_ERR); }
}
class GbtResult {
  constructor() { throw new Error(STUB_ERR); }
}
class ThreadTransaction {
  constructor() { throw new Error(STUB_ERR); }
}
class ThreadAcceleration {
  constructor() { throw new Error(STUB_ERR); }
}

module.exports = { GbtGenerator, GbtResult, ThreadTransaction, ThreadAcceleration };
