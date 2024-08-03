use ../nu-serde-bin [ "deserialize", "serialize" ]
use std assert

export def main [] {
    const SCHEMA = {
        a: "int:2",
        v: "vec:1",
        b: { a: "int:1", b: "int:3", c: "int:2" },
    }

    let bin = 0x[
        01 01 05 00  00 00 00 00  00 00 ff ff  ff ff ff 01
        02 03 04 05  06
    ]
    let value = {
        a: 257,
        v: [0x[ff], 0x[ff], 0x[ff], 0x[ff], 0x[ff]],
        b: { a: 1, b: 262914, c: 1541 },
    }

    assert equal ($bin | deserialize $SCHEMA) $value

    assert equal ($value | serialize $SCHEMA) $bin
}
