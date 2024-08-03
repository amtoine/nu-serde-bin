# nu-serde-bin
Helpers to serialize and deserialize binary data.

## What it does

`nu-serde-bin` is a Nushell package that ships a single module: [`nu-serde-bin`](nu-serde-bin/mod.nu).

This module then exports two commands:
- `deserialize`: takes in some binary data and a _schema_ and outputs a Nushell value that is the
  deserialized equivalent of the input.
- `serialize`: takes in some Nushell value and a _schema_ and outputs binary data. It is the inverse
  of `deserialize`.

## Installation
The recommended way is to use [Nupm](https://github.com/nushell/nupm).

## Valid binary formats

`nu-serde-bin` currently supports three kinds of binary data and their associated Nushell values:
- integers: the format is `int:n` where $n$ is the number of bytes of the integer. $n$ could be
  any strictly positive integer. The associated Nushell values are `int`.
- lists / vectors of integers: the format is `vec:n` where $n$ is the number of bytes of each element
  in the vector. All elements in the vector should take the same amount of bytes $n$ and $n$ could be
  any strictly positive integer. The length of the vector is encoded with $8$ bytes, before the first
  item of the vector. The associated Nushell values are `list<binary>`.
- records / key-value structures: the format is `{ k1: v1, k2, v2 }` where the $k_i$ are string
  names that you can define however you like and the $v_i$ are any of the valid `nu-serde-bin`
  formats. This last format is recursive, i.e. a $v_i$ can itself be a record. The associated
  Nushell values are `record<>`.

## Some examples
#### invalid formats
```nushell
0x[01 00] | deserialize "not-a:format"
```

### invalid binary data or Nushell values
```nushell
0x[01 10] | deserialize "int:4"
```

```nushell
assert equal (123456 | serialize "int:1") 0x[40] # instead of `0x[40 e2 01 00]`
```

#### integers
```nushell
assert equal (0x[01 10] | deserialize "int:2") 4097
```

```nushell
assert equal (123456 | serialize "int:4") 0x[40 e2 01 00]
```

```nushell
assert equal (123456 | serialize "int:8") 0x[40 e2 01 00  00 00 00 00]
```

### vectors
```nushell
let actual = 0x[03 00 00 00  00 00 00 00  00 01 02] | deserialize "vec:1"
#               \______________________/  \______/
#                        length             items
let expected = [0x[00], 0x[01], 0x[02]]

assert equal $actual $expected
```

```nushell
let actual = [0x[01 00], 0x[02, 00], 0x[03, 00], 0x[04, 00]] | serialize "vec:2"
let expected = 0x[04 00 00 00  00 00 00 00  01 00 02 00  03 00 04 00]

assert equal $actual $expected
```

### records
```nushell
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
```

```nushell
assert equal ($bin | deserialize $SCHEMA) $value
```

```nushell
assert equal ($value | serialize $SCHEMA) $bin
```

### Rust libraries
Below is a non-exhaustive list of Rust libraries that should be supported by `nu-serde-bin`:
- the [`bincode`] crate
- the [`serde::Serialize`] and [`serde::Deserialize`] traits from the [Serde framework][Serde]
- the [`ark_serialize::CanonicalSerialize`] and [`ark_serialize::CanonicalDeserialize`] traits from the [Arkworks ecosystem][Arkworks]


## TODO
- [x] polish serialization error messages
- [ ] add documentation

[`bincode`]: https://docs.rs/bincode/latest/bincode/
[`serde::Serialize`]: https://docs.rs/serde/1.0.204/serde/trait.Serialize.html
[`serde::Deserialize`]: https://docs.rs/serde/1.0.204/serde/trait.Deserialize.html
[Serde]: https://serde.rs/
[`ark_serialize::CanonicalSerialize`]: https://docs.rs/ark-serialize/latest/ark_serialize/trait.CanonicalSerialize.html
[`ark_serialize::CanonicalDeserialize`]: https://docs.rs/ark-serialize/latest/ark_serialize/trait.CanonicalDeserialize.html
[Arkworks]: https://github.com/arkworks-rs
