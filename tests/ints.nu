use ../nu-serde-bin [ "deserialize", "serialize" ]
use std assert

export def integers [] {
    assert equal (123456 | serialize "int:1") 0x[40] # instead of `0x[40 e2 01 00]`

    assert equal (0x[01 10] | deserialize "int:2") 4097

    assert equal (123456 | serialize "int:4") 0x[40 e2 01 00]

    assert equal (123456 | serialize "int:8") 0x[40 e2 01 00  00 00 00 00]
}
