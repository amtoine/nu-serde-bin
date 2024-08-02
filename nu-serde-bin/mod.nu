use std repeat

def "deserialize int" [size: int]: [ binary -> record<deser: int, n: int> ] {
    if $size mod 8 != 0 {
        error make --unspanned { msg: "deser int: invalid size" }
    }
    let nb_bytes = $size / 8

    if ($in | bytes length) < $nb_bytes {
        error make --unspanned { msg: "deser int: invalid binary" }
    }

    { deser: ($in | first $nb_bytes | into int), n: $nb_bytes }
}

def "serialize int" [size: int]: [ int -> binary ] {
    if $size mod 8 != 0 {
        error make --unspanned { msg: "ser int: invalid size" }
    }
    let nb_bytes = $size / 8

    $in | into binary --compact | bytes add --end (0x[00] | repeat $nb_bytes | bytes build ...$in) | bytes at ..<$nb_bytes
}

def "deserialize vec" [size: int]: [ binary -> record<deser: list<binary>, n: int> ] {
    if $size mod 8 != 0 {
        error make --unspanned { msg: "deser vec: invalid size" }
    }
    let nb_bytes_per_element = $size / 8

    let nb_elements = $in | bytes at ..<8 | deserialize int 64 | get deser
    let elements = $in | bytes at 8..

    if ($elements | bytes length) < ($nb_elements * $nb_bytes_per_element) {
        error make --unspanned { msg: "deser vec: invalid binary" }
    }

    {
        deser: (0..<$nb_elements | each { |i|
            $elements | bytes at ($i * $nb_bytes_per_element)..<(($i + 1) * $nb_bytes_per_element)
        }),
        n: (8 + $nb_elements * $nb_bytes_per_element),
    }
}

def "serialize vec" [size: int]: [ list<binary> -> binary ] {
    if $size mod 8 != 0 {
        error make --unspanned { msg: "ser vec: invalid size" }
    }
    let nb_bytes_per_element = $size / 8

    for el in $in {
        if ($el | bytes length) != $nb_bytes_per_element {
            error make --unspanned { msg: "ser vec: invalid binary" }
        }
    }

    let nb_elements = $in | length | serialize int 64

    $in | prepend $nb_elements | bytes build ...$in
}

export def "deserialize" [schema]: [ binary -> any ] {
    def aux [schema, offset: int = 0]: [ binary -> record<deser: any, n: int> ] {
        let bin = $in

        match ($schema | describe | str replace --regex '<.*' '') {
            "string" => {
                let s = $schema | parse "{type}:{size}" | into record
                if $s == {} {
                    error make {
                        msg: $"(ansi red_bold)invalid_schema(ansi reset)",
                        label: {
                            text: "schema is malformed",
                            span: (metadata $schema).span,
                        },
                        help: $"expected format to be (ansi cyan){type}:{size}(ansi reset), found (ansi yellow)($schema)(ansi reset)"
                    }
                }

                let s = try {
                    $s | into int size
                } catch {
                    error make {
                        msg: $"(ansi red_bold)invalid_schema(ansi reset)",
                        label: {
                            text: "schema is malformed",
                            span: (metadata $schema).span,
                        },
                        help: $"expected (ansi cyan)size(ansi reset) in format (ansi cyan){type}:{size}(ansi reset) to be an (ansi purple)int(ansi reset), found (ansi yellow)($s.size)(ansi reset)"
                    }
                }

                match $s.type {
                    "vec" => { return ($bin | skip $offset | deserialize vec $s.size) },
                    "int" => { return ($bin | skip $offset | deserialize int $s.size) },
                    $t => {
                        error make {
                            msg: $"(ansi red_bold)invalid_schema(ansi reset)",
                            label: {
                                text: "invalid schema type",
                                span: (metadata $schema).span,
                            },
                            help: $"expected one of (ansi cyan)['vec', 'int'](ansi reset), found (ansi yellow)($t)(ansi reset)"
                        }
                    },
                }
            },
            "record" => {
                let _schema = $schema | transpose k v
                let res = generate { |it|
                    let curr = $_schema | get $it.0

                    let res = $bin | aux $curr.v $it.1

                    let deser = $it.2 | merge { $curr.k: $res.deser }
                    let offset = $it.1 + $res.n

                    if $it.0 == ($_schema | length) - 1 {
                        { out: { deser: $deser, n: $offset } }
                    } else {
                        { next: [ ($it.0 + 1), $offset, $deser ] }
                    }
                } [0, $offset, {}]

                $res | into record
            },
            $t => {
                error make {
                    msg: $"(ansi red_bold)invalid_schema(ansi reset)",
                    label: {
                        text: "invalid serde schema",
                        span: (metadata $schema).span,
                    },
                    help: $"type is (ansi purple)($t)(ansi reset)"
                }
            }
        }
    }

    $in | aux $schema 0 | get deser
}

export def "serialize" [schema]: [ any -> binary ] {
    let data = $in

    match ($schema | describe | str replace --regex '<.*' '') {
        "string" => {
            let s = $schema | parse "{type}:{size}" | into record
            if $s == {} {
                error make {
                    msg: $"(ansi red_bold)invalid_schema(ansi reset)",
                    label: {
                        text: "schema is malformed",
                        span: (metadata $schema).span,
                    },
                    help: $"expected format to be (ansi cyan){type}:{size}(ansi reset), found (ansi yellow)($schema)(ansi reset)"
                }
            }

            let s = try {
                $s | into int size
            } catch {
                error make {
                    msg: $"(ansi red_bold)invalid_schema(ansi reset)",
                    label: {
                        text: "schema is malformed",
                        span: (metadata $schema).span,
                    },
                    help: $"expected (ansi cyan)size(ansi reset) in format (ansi cyan){type}:{size}(ansi reset) to be an (ansi purple)int(ansi reset), found (ansi yellow)($s.size)(ansi reset)"
                }
            }

            match $s.type {
                "vec" => { return ($data | serialize vec $s.size) },
                "int" => { return ($data | serialize int $s.size) },
                $t => {
                    error make {
                        msg: $"(ansi red_bold)invalid_schema(ansi reset)",
                        label: {
                            text: "invalid schema type",
                            span: (metadata $schema).span,
                        },
                        help: $"expected one of (ansi cyan)['vec', 'int'](ansi reset), found (ansi yellow)($t)(ansi reset)"
                    }
                },
            }
        },
        "record" => {
            $schema | items { |k, v| $data | get $k | serialize $v } | bytes build ...$in
        },
        $t => {
            error make {
                msg: $"(ansi red_bold)invalid_schema(ansi reset)",
                label: {
                    text: "invalid serde schema",
                    span: (metadata $schema).span,
                },
                help: $"type is (ansi purple)($t)(ansi reset)"
            }
        }
    }
}