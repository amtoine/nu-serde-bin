use ../nu-serde-bin [ "deserialize", "serialize" ]
use std assert

export def vectors [] {
    let actual = 0x[03 00 00 00  00 00 00 00  00 01 02] | deserialize "vec:1"
    let expected = [0x[00], 0x[01], 0x[02]]
    assert equal $actual $expected

    let actual = [0x[01 00], 0x[02, 00], 0x[03, 00], 0x[04, 00]] | serialize "vec:2"
    let expected = 0x[04 00 00 00  00 00 00 00  01 00 02 00  03 00 04 00]
    assert equal $actual $expected
}
