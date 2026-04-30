// Stub of the rust-gbt NAPI module. The backend instantiates GbtGenerator
// at class-field-initialization time (before the runtime RUST_GBT flag is
// checked), so the constructors must succeed. The make/update methods are
// the actual runtime entry points — those throw if reached, which only
// happens if RUST_GBT=true in the backend config.
const STUB_ERR = 'rust-gbt stub: this build was packaged without the Rust NAPI addon. Set MEMPOOL.RUST_GBT=false in the backend config.';

class GbtGenerator {
  constructor() {}
  make() { return Promise.reject(new Error(STUB_ERR)); }
  update() { return Promise.reject(new Error(STUB_ERR)); }
}
class GbtResult {
  constructor() {
    this.blocks = [];
    this.blockWeights = [];
    this.clusters = [];
    this.rates = [];
    this.overflow = [];
  }
}
class ThreadTransaction {}
class ThreadAcceleration {}

module.exports = { GbtGenerator, GbtResult, ThreadTransaction, ThreadAcceleration };
