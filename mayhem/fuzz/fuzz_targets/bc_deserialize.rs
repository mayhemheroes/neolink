#![no_main]
//! Fuzz neolink_core's Baichuan (BC) message deserialization surface.
//!
//! The historical `bc-deserialize` target drove neolink_core::bc::de::bc_deserialize,
//! which upstream keeps `pub(crate)` — the old fork's harness only reached it via a
//! non-additive edit to crates/core/src/bc/de.rs. To keep this overlay purely
//! additive, this harness drives the equivalent PUBLIC deserialization path a
//! modern BC message body flows through after the binary header parse: the payload
//! XML is parsed into neolink's BC data model (BcXml / Extension, both publicly
//! re-exported and YaDeserialize) via yaserde — the same parse bc::de performs
//! internally for every modern message.
use libfuzzer_sys::fuzz_target;

use neolink_core::bc::model::{BcXml, Extension};

fuzz_target!(|data: &[u8]| {
    let _ = yaserde::de::from_reader::<_, BcXml>(data);
    let _ = yaserde::de::from_reader::<_, Extension>(data);
});
