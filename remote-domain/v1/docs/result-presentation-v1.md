# Captured result presentation v1

Providers may add an optional `presentation` object to a structured A2A response
or MCP `structuredContent`. Its schema is
[`schemas/result-presentation.v1.schema.json`](../schemas/result-presentation.v1.schema.json).
This is a shared data annotation contract. It does not add a UI bundle, profile
registry, transport operation, business verdict or model instruction.

A domain handler supplies these annotations after validating its business result.
Do not ask the model to generate them or change model-authored prose to fit them.
The provider's business schema must explicitly permit the optional object when
that schema is closed. Existing responses without annotations remain valid.

```json
{
  "presentation": {
    "schemaVersion": "astraform.result-presentation.v1",
    "fields": [
      {
        "pointer": "/statement/minimumAmountDue",
        "label": "Minimum payment",
        "format": "currency",
        "currencyPointer": "/statement/currency"
      }
    ]
  }
}
```

## Shape and interpretation

Each of 1–32 fields requires a `pointer` and `label`. The optional `format` is
`text` (default), `currency` or `date`. `currencyPointer` is required exactly when
`format` is `currency`. Extra properties and enum/value label mappings are not
supported. Labels contain 1–120 Unicode scalar values on one line, with no C0/C1
control characters, line/paragraph separators or lone surrogates.

Pointers contain 1–256 Unicode scalar values and use RFC 6901: `/` starts a path,
`~0` escapes `~` and `~1` escapes `/`. The empty root pointer, malformed escapes,
lone surrogates and the `/presentation` subtree are invalid. Resolve only own
properties in the **same captured result**. No prototype traversal, external
references, URLs or network reads are allowed. A pointer can identify a missing
value; that is shown as unavailable, not filled from expectations or another turn.
Annotations never hide other returned fields or change their original JSON types.

Consumers must enforce two bounds that JSON Schema cannot express here: the
compact UTF-8 JSON serialization of `presentation` is at most 8,192 bytes, and
field pointers are unique by their decoded RFC 6901 path. Reject an invalid block
as a whole and use the generic captured-data view. Keep the original metadata in
source evidence. An unsupported or value-incompatible format falls back to the
unchanged captured value; it must not invalidate the business receipt.

## Formats

- `text`: preserve the captured value and JSON type. In particular, `false`, `0`,
  `null`, an empty string, empty array and empty object remain distinguishable.
- `currency`: resolve `currencyPointer` in the same result to a recognized,
  uppercase ISO 4217 code. Accept finite decimal values only. Decimal strings
  contain an optional leading minus, digits and an optional fractional part;
  grouping separators, exponents, `NaN` and infinity are not decimal strings.
  Preserve the sign and every fractional digit. Do not round to a currency's
  usual number of minor units, convert exchange rates, or infer that a negative
  closing balance is a positive amount due. Use a conservative code-plus-decimal
  display when lossless formatting is unavailable. Unsafe or non-finite numeric
  inputs keep their generic representation.
- `date`: accept a real calendar date in `YYYY-MM-DD`, years 0001–9999, and render
  it without a timezone shift. Invalid dates remain unchanged. `date-time` and
  custom format expressions are outside this version.

## MCP output-schema publication

A provider advertising these annotations in MCP `outputSchema` must supply a
self-contained inline schema. The native MCP descriptor validator rejects both
local and external `$ref` entries. Resolve the canonical presentation schema and
its definitions from an explicitly selected local contract bundle at provider
build or startup, then advertise the resolved schema. Keep one editable canonical
source; generated resolved output is a build artifact. Neither Runtime nor the
browser fetches remote schemas. This document does not add automatic projection
of frozen tool output schemas into historical evidence.

## Evidence and trust

For A2A, the annotations are part of the original normalized JSON receipt text.
For MCP, they are part of the original `structuredContent`. Existing receipt
hashes and exports therefore cover the annotations alongside their values; they
are not looked up from a current manifest or attached retrospectively to old
runs. Pending request views must not retrieve presentation data from private
runtime state or an unrelated receipt.

Presentation is additive data in the recorded reply. Existing customer reply
observations may include it when the coordinator forwards the captured partner
result, so adding annotations does not guarantee identical model input or
subsequent decisions. Configured instructions, completion policy and business
advice text remain unchanged; presentation does not generate model instructions.

Labels are untrusted provider-authored text. Escape them as text, never HTML,
JavaScript, CSS, URLs or templates. A display hint cannot change execution status,
goal evaluation, participant ownership, tool authorization, outcome authority or
a launch/release recommendation. Retain original pointers, types, values and the
complete recorded source for inspection.

The [banking example](../samples/result-presentation-banking.sample.json) preserves
the returned negative closing balance and annotates money/date fields. The
[marketing example](../samples/result-presentation-marketing.sample.json) annotates
plain status, Boolean and count values without rewriting their meaning. These are
illustrative response envelopes, not new canonical banking or marketing business
schemas. Validate each `presentation` object against the shared schema and its
pointers against that example's own captured response.
