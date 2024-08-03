use std repeat

def color [c: string, --next: string = "reset"]: [ any -> string ] {
    $"(ansi $c)($in)(ansi reset)(ansi $next)"
}

def hex []: [ binary -> string ] {
    let bin = $in
    $bin | bytes length | seq 0 ($in - 1) | reduce --fold "0x" { |it, acc|
        let byte = $bin
            | bytes at $it..$it
            | into int
            | fmt
            | get lowerhex
            | str replace "0x" ''
            | fill --alignment "right" --width 2 --character '0'
        $acc + $byte
    }
}

def bin-context [o: int]: [ binary -> string ] {
    let bin = $in

    let context = [
        (if ($o > 0) {
            ($bin | bytes at ([0, ($o - 3)] | math max)..($o - 1) | hex | color yellow)
        }),
        ($bin | bytes at $o..$o | hex | color green_underline),
        (if ($bin | bytes length | $o < $in - 1) {
            ($bin | bytes at ($o + 1)..($o + 3) | hex | color cyan)
        }),
    ]

    $context | compact | str join ' '
}

def "deserialize int" [size: int]: [ binary -> record<deser: int, n: int, err: record> ] {
    if ($in | bytes length) < $size {
        return {
            deser: null,
            n: 0,
            err: {
                msg: ("deser_int::invalid_binary" | color red_bold),
                help: (
                    $"expected at least ($size | color cyan) bytes, found " +
                    $"($in | bytes length | color yellow): ($in | hex | color purple)"
                ),
            },
        }
    }

    { deser: ($in | first $size | into int), n: $size, err: {} }
}

def "serialize int" [size: int]: [ int -> binary ] {
    into binary --compact
        | bytes add --end (0x[00] | repeat $size | bytes build ...$in)
        | bytes at ..<$size
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
                msg: ("deser_vec::invalid_binary" | color red_bold),
                help: (
                    $"expected at least ($nb_elements * $size | color cyan) bytes, found " +
                    $"($elements | bytes length | color yellow): ($elements | hex | color purple)"
                ),
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
                msg: ("ser_vec::invalid_binary" | color red_bold),
                help: $"expected a ('list<binary>' | color cyan), found ($in | describe | color yellow)",
            },
        }
    }

    for el in ($in | enumerate) {
        if ($el.item | bytes length) != $size {
            return {
                ser: null,
                err: {
                    msg: ("ser_vec::invalid_value" | color red_bold),
                    help: (
                        $"expected all items to be ($size | color cyan) bytes long, found " +
                        $"($el.item | bytes length | color yellow) bytes at index ($el.index | color purple)"
                    ),
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
                            msg: ("invalid_schema" | color red_bold),
                            label: {
                                text: "schema is malformed",
                                span: (metadata $schema).span,
                            },
                            help: (
                                $"expected format to be ('{type}:{size}' | color cyan), found " +
                                ($schema | color yellow)
                            ),
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
                            msg: ("invalid_schema" | color red_bold),
                            label: {
                                text: "schema is malformed",
                                span: (metadata $schema).span,
                            },
                            help: (
                                $"expected ('size' | color cyan) in format ('{type}:{size}' | color cyan) " +
                                $"to be an ('int' | color purple), found ($s.size | color yellow)"
                            ),
                        },
                    }
                }

                if $s.size mod 8 != 0 {
                    return {
                        deser: null,
                        n: $offset,
                        err: {
                            msg: ("invalid_schema" | color red_bold),
                            label: {
                                text: "schema is malformed",
                                span: (metadata $schema).span,
                            },
                            help: (
                                $"expected ('size' | color cyan) to be a multiple of " +
                                $"('8' | color purple), found ($s.size | color yellow)"
                            ),
                        },
                    }
                }
                let s = $s | update size { $in / 8 }

                match $s.type {
                    "vec" => {
                        let res = $bin | skip $offset | deserialize vec $s.size
                        if $res.err != {} {
                            let o = $offset + $res.n
                            return (
                                $res | insert err.label {
                                    text: (
                                        $"error at byte ($o | color green_underline --next purple) in input binary\n" +
                                        $"context: ($bin | bin-context $o)"
                                    ),
                                    span: (metadata $schema).span,
                                }
                            )
                        }
                        return $res
                    },
                    "int" => {
                        let res = $bin | skip $offset | deserialize int $s.size
                        if $res.err != {} {
                            let o = $offset + $res.n
                            return (
                                $res | insert err.label {
                                    text: (
                                        $"error at byte ($o | color green_underline --next purple) in input binary\n" +
                                        $"context: ($bin | bin-context $o)"
                                    ),
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
                                msg: ("invalid_schema" | color red_bold),
                                label: {
                                    text: "invalid schema type",
                                    span: (metadata $schema).span,
                                },
                                help: $"expected one of (['vec', 'int'] | color cyan), found ($t | color yellow)"
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
                        msg: ("invalid_schema" | color red_bold),
                        label: {
                            text: "invalid serde schema",
                            span: (metadata $schema).span,
                        },
                        help: $"type is ($t | color purple), expected one of (['string', 'record'] | color cyan)"
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
                            msg: ("invalid_schema" | color red_bold),
                            label: {
                                text: "schema is malformed",
                                span: (metadata $schema).span,
                            },
                            help: (
                                $"expected format to be ('{type}:{size}' | color cyan), found " +
                                ($schema | color yellow)
                            ),
                        },
                    }
                }

                let s = try {
                    $s | into int size
                } catch {
                    return {
                        ser: null,
                        err: {
                            msg: $"('invalid_schema' | color red_bold)",
                            label: {
                                text: "schema is malformed",
                                span: (metadata $schema).span,
                            },
                            help: (
                                $"expected ('size' | color cyan) in format ('{type}:{size}' | color cyan) " +
                                $"to be an ('int' | color purple), found ($s.size | color yellow)"
                            ),
                        },
                    }
                }

                if $s.size mod 8 != 0 {
                    return {
                        ser: null,
                        err: {
                            msg: $"('invalid_schema' | color red_bold)",
                            label: {
                                text: "schema is malformed",
                                span: (metadata $schema).span,
                            },
                            help: (
                                $"expected ('size' | color cyan) to be a multiple of ('8' | color purple), " +
                                $"found ($s.size | color yellow)"
                            ),
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
                                msg: $"('invalid_schema' | color red_bold)",
                                label: {
                                    text: "invalid schema type",
                                    span: (metadata $schema).span,
                                },
                                help: $"expected one of (['vec', 'int'] | color cyan), found ($t | color yellow)"
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
                        msg: $"('invalid_schema' | color red_bold)",
                        label: {
                            text: "invalid serde schema",
                            span: (metadata $schema).span,
                        },
                        help: $"type is ($t | color purple), expected one of (['string', 'record'] | color cyan)"
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
