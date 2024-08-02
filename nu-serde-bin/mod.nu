use std repeat

def "deserialize int" [size: int]: [ binary -> record<deser: int, n: int, err: record> ] {
    if ($in | bytes length) < $size {
        return {
            deser: null,
            n: null,
            err: {
                msg: $"(ansi red_bold)deser_int::invalid_binary(ansi reset)",
                help: $"expected at least (ansi cyan)($size)(ansi reset) bytes, found (ansi yellow)($in | bytes length)(ansi reset): (ansi purple)($in)(ansi reset)",
            },
        }
    }

    { deser: ($in | first $size | into int), n: $size, err: {} }
}

def "serialize int" [size: int]: [ int -> binary ] {
    if $size mod 8 != 0 {
        error make --unspanned { msg: "ser int: invalid size" }
    }
    let nb_bytes = $size / 8

    $in | into binary --compact | bytes add --end (0x[00] | repeat $nb_bytes | bytes build ...$in) | bytes at ..<$nb_bytes
}

def "deserialize vec" [size: int]: [ binary -> record<deser: list<binary>, n: int, err: record> ] {
    let res = $in | bytes at ..<8 | deserialize int 8
    if $res.err != {} {
        return { deser: null, n: null, err: $res.err }
    }
    let nb_elements = $res.deser
    let elements = $in | bytes at 8..

    if ($elements | bytes length) < ($nb_elements * $size) {
        return {
            deser: null,
            n: 8,
            err: {
                msg: $"(ansi red_bold)deser_vec::invalid_binary(ansi reset)",
                help: $"expected at least (ansi cyan)($nb_elements * $size)(ansi reset) bytes, found (ansi yellow)($elements | bytes length)(ansi reset): (ansi purple)($elements)(ansi reset)",
            },
        }
    }

    {
        deser: (0..<$nb_elements | each { |i|
            $elements | bytes at ($i * $size)..<(($i + 1) * $size)
        }),
        n: (8 + $nb_elements * $size),
        err: {},
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
    def aux [schema, offset: int = 0]: [ binary -> record<deser: any, n: int, err: record> ] {
        let bin = $in

        match ($schema | describe | str replace --regex '<.*' '') {
            "string" => {
                let s = $schema | parse "{type}:{size}" | into record
                if $s == {} {
                    return {
                        deser: null,
                        n: $offset,
                        err: {
                            msg: $"(ansi red_bold)invalid_schema(ansi reset)",
                            label: {
                                text: "schema is malformed",
                                span: (metadata $schema).span,
                            },
                            help: $"expected format to be (ansi cyan){type}:{size}(ansi reset), found (ansi yellow)($schema)(ansi reset)"
                        },
                    }
                }

                let s = try {
                    $s | into int size
                } catch {
                    return {
                        deser: null,
                        n: $offset,
                        err: {
                            msg: $"(ansi red_bold)invalid_schema(ansi reset)",
                            label: {
                                text: "schema is malformed",
                                span: (metadata $schema).span,
                            },
                            help: $"expected (ansi cyan)size(ansi reset) in format (ansi cyan){type}:{size}(ansi reset) to be an (ansi purple)int(ansi reset), found (ansi yellow)($s.size)(ansi reset)"
                        },
                    }
                }

                if $s.size mod 8 != 0 {
                    return {
                        deser: null,
                        n: $offset,
                        err: {
                            msg: $"(ansi red_bold)invalid_schema(ansi reset)",
                            label: {
                                text: "schema is malformed",
                                span: (metadata $schema).span,
                            },
                            help: $"expected (ansi cyan)size(ansi reset) to be a multiple of (ansi purple)8(ansi reset), found (ansi yellow)($s.size)(ansi reset)"
                        },
                    }
                }
                let s = $s | update size { $in / 8 }

                match $s.type {
                    "vec" => {
                        let res = $bin | skip $offset | deserialize vec $s.size
                        if $res.err != {} {
                            return (
                                $res | upsert err.label.text { |it|
                                    $it.err.label?.text?
                                        | default ""
                                        | $in + $"error at byte (ansi red)($offset + $res.n)(ansi purple) ($bin | bytes at ($offset)..($offset)) in input binary"
                                }
                            )
                        }
                        return $res
                    },
                    "int" => {
                        let res = $bin | skip $offset | deserialize int $s.size
                        if $res.err != {} {
                            return (
                                $res | upsert err.label.text { |it|
                                    $it.err.label?.text?
                                        | default ""
                                        | $in + $"error at byte (ansi red)($offset + $res.n)(ansi purple) ($bin | bytes at ($offset)..($offset)) in input binary"
                                }
                            )
                        }
                        return $res
                    },
                    $t => {
                        return {
                            deser: null,
                            n: $offset,
                            err: {
                                msg: $"(ansi red_bold)invalid_schema(ansi reset)",
                                label: {
                                    text: "invalid schema type",
                                    span: (metadata $schema).span,
                                },
                                help: $"expected one of (ansi cyan)['vec', 'int'](ansi reset), found (ansi yellow)($t)(ansi reset)"
                            },
                        }
                    },
                }
            },
            "record" => {
                let _schema = $schema | transpose k v
                let res = generate { |it|
                    let curr = $_schema | get $it.0

                    let res = $bin | aux $curr.v $it.1
                    if $res.err != {} {
                        { out: { deser: null, n: $it.1, err: $res.err } }
                    } else {
                        let deser = $it.2 | merge { $curr.k: $res.deser }
                        let offset = $it.1 + $res.n

                        if $it.0 == ($_schema | length) - 1 {
                            { out: { deser: $deser, n: $offset, err: {} } }
                        } else {
                            { next: [ ($it.0 + 1), $offset, $deser ] }
                        }
                    }
                } [0, $offset, {}]

                $res | into record
            },
            $t => {
                return {
                    deser: null,
                    n: $offset,
                    err: {
                        msg: $"(ansi red_bold)invalid_schema(ansi reset)",
                        label: {
                            text: "invalid serde schema",
                            span: (metadata $schema).span,
                        },
                        help: $"type is (ansi purple)($t)(ansi reset), expected one of (ansi cyan)['string', 'record'](ansi reset)"
                    },
                }
            }
        }
    }

    let res = $in | aux $schema 0
    let span = (metadata $in).span
    if $res.err != {} {
        let err = if $res.n == 0 {
            if $res.err.label.span? != null {
                $res.err | update label.span (metadata $schema).span
            } else {
                $res.err
            }
        } else {
            $res.err
        }

        if $err.label.span? == null {
            error make ($err | insert label.span $span)
        } else {
            error make $err
        }
    }
    $res.deser
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
