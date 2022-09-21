#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    _ = neolink_core::bc::de::bc_deserialize(data);
});
