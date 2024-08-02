use std repeat

def "deserialize int" [size: int]: [ binary -> record<deser: int, n: int, err: record> ] {
    if ($in | bytes length) < $size {
        return {
            deser: null,
            n: 0,
            err: {
                msg: $"(ansi red_bold)deser_int::invalid_binary(ansi reset)",
                help: $"expected at least (ansi cyan)($size)(ansi reset) bytes, found (ansi yellow)($in | bytes length)(ansi reset): (ansi purple)($in)(ansi reset)",
            },
        }
    }

    { deser: ($in | first $size | into int), n: $size, err: {} }
}

def "serialize int" [size: int]: [ int -> binary ] {
    $in | into binary --compact | bytes add --end (0x[00] | repeat $size | bytes build ...$in) | bytes at ..<$size
}

def "deserialize vec" [size: int]: [ binary -> record<deser: list<binary>, n: int, err: record> ] {
    let res = $in | bytes at ..<8 | deserialize int 8
    if $res.err != {} {
        return $res
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

def "serialize vec" [size: int]: [ list<binary> -> record<ser: binary, err: record> ] {
    if ($in | describe) != "list<binary>" {
        return {
            ser: null,
            err: {
                msg: $"(ansi red_bold)ser_vec::invalid_value(ansi reset)",
                help: $"expected a (ansi cyan)list<binary>(ansi reset), found (ansi yellow)($in | describe)(ansi reset)",
            },
        }
    }

    for el in ($in | enumerate) {
        if ($el.item | bytes length) != $size {
            return {
                ser: null,
                err: {
                    msg: $"(ansi red_bold)ser_vec::invalid_value(ansi reset)",
                    help: $"expected all items to be (ansi cyan)($size)(ansi reset) bytes long, found (ansi yellow)($el.item | bytes length)(ansi reset) bytes at index (ansi purple)($el.index)(ansi reset)",
                },
            }
        }
    }

    let nb_elements = $in | length | serialize int 8

    {
        ser: ($in | prepend $nb_elements | bytes build ...$in),
        err: {},
    }
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
                                $res | insert err.label {
                                    text: $"error at byte (ansi red)($offset + $res.n)(ansi purple) ($bin | bytes at ($offset)..($offset)) in input binary",
                                    span: (metadata $schema).span,
                                }
                            )
                        }
                        return $res
                    },
                    "int" => {
                        let res = $bin | skip $offset | deserialize int $s.size
                        if $res.err != {} {
                            return (
                                $res | insert err.label {
                                    text: $"error at byte (ansi red)($offset + $res.n)(ansi purple) ($bin | bytes at ($offset)..($offset)) in input binary"
                                    span: (metadata $schema).span,
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
    if $res.err != {} {
        # NOTE: sometimes the span is just messed up...
        let err = if ($res.err.label.span | view span $in.start $in.end | $in == '$schema') {
            $res.err | update label.span (metadata $schema).span
        } else {
            $res.err
        }

        error make $err
    }
    $res.deser
}

export def "serialize" [schema]: [ any -> binary ] {
    def aux [schema]: [ any -> record<ser: binary, err: record> ] {
        let data = $in

        match ($schema | describe | str replace --regex '<.*' '') {
            "string" => {
                let s = $schema | parse "{type}:{size}" | into record
                if $s == {} {
                    return {
                        ser: null,
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
                        ser: null,
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
                        ser: null,
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
                        let res = $data | serialize vec $s.size
                        if $res.err != {} {
                            return (
                                $res | insert err.label {
                                    text: $"some error",
                                    span: (metadata $schema).span,
                                }
                            )
                        }
                        return $res
                    },
                    "int" => { return { ser: ($data | serialize int $s.size), err: {} } },
                    $t => {
                        return {
                            ser: null,
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
                let res = $schema | items { |k, v| $data | get $k | aux $v }

                for row in $res {
                    if $row.err? != null and $row.err != {} {
                        return $row
                    }
                }

                {
                    ser: ($res.ser | bytes build ...$in),
                    err: {},
                }
            },
            $t => {
                return {
                    ser: null,
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

    let res = $in | aux $schema
    if $res.err != {} {
        # NOTE: sometimes the span is just messed up...
        let err = if ($res.err.label.span | view span $in.start $in.end | $in == '$schema') {
            $res.err | update label.span (metadata $schema).span
        } else {
            $res.err
        }

        error make $err
    }
    $res.ser
}
