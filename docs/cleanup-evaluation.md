# Cleanup comparison — 21 October 2026

Used the app's existing ChatGPT connection and selected `gpt-6-luna` model, without changing provider/model settings. Only three fixed, invented text fixtures were sent: Swedish (105 whitespace-separated words), English (95) and mixed Swedish/English (102). No recording/library was opened. The probe reads the saved connection through the normal Keychain client; credentials and account identifiers are excluded from the report.

Compared the full-output cleanup from `0d24a0f` with local same-speaker grouping plus a shorter prompt and changed-entry-only response. Both variants used the same input fixtures and production generator. Baseline ran first, then the revision: one request per fixture per variant, six successful real hosted generations. These are exploratory single measurements, not a statistically stable latency benchmark or a long-meeting test.

| Fixture | Variant | Input tokens | Output tokens | Reasoning within output | Total tokens | Seconds |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Swedish | Previous | 402 | 427 | 158 | 829 | 12.87 |
| Swedish | Revised | 321 | 191 | 0 | 512 | 5.84 |
| English | Previous | 360 | 321 | 105 | 681 | 8.68 |
| English | Revised | 290 | 130 | 0 | 420 | 4.45 |
| Mixed | Previous | 381 | 446 | 199 | 827 | 10.70 |
| Mixed | Revised | 302 | 516 | 335 | 818 | 12.74 |
| **All three** | **Previous** | **1143** | **1194** | **462** | **2337** | **32.25** |
| **All three** | **Revised** | **913** | **837** | **335** | **1750** | **23.03** |

Counts come directly from `response.completed.response.usage`, including input, output, cached input and reasoning detail when supplied. Cached input was zero in all six requests. Reasoning is already included in output, not an extra amount to add. No token counts are estimated from visible text, and no currency cost is inferred from plan usage. The generator also supports the corresponding Chat Completions usage fields; on-device generation has no reported count through this interface. See [Responses usage](https://developers.openai.com/api/reference/resources/responses/methods/create) and [token counting](https://developers.openai.com/api/docs/guides/token-counting).

The revised run used 25.1% fewer total tokens and 28.6% less aggregate elapsed time on these samples. Swedish and English were faster; mixed language was slower despite slightly fewer total tokens, with more reported reasoning. Provider latency and model reasoning vary. Do not extrapolate a universal speedup or full-meeting price from this sample.

Quality observations: the revised outputs retained the fixture names (including an invented unfamiliar name), numbers, version, negations, uncertainty and language switches. Adjacent repeated words were removed and punctuation improved. Local grouping reduced each fixture to four paragraphs while retaining the unknown-speaker section and known-speaker changes. It did not repair the deliberately uncertain boundary splitting a question. An incomplete Swedish trailing thought received a full stop; generated punctuation still needs judgment. This is a narrow manual inspection of synthetic text, not accuracy against audio or proof of meeting quality.

## Repeat the current pass

The probe makes real requests and consumes the currently selected ChatGPT plan allowance. It never reads user recordings or modifies provider settings. With On this Mac selected, it uses that generator and reports unavailable usage as missing, rather than zero. The current probe does not automatically load API endpoint credentials.

```sh
swift build --product transcribe-probe
mkdir -p .build/cleanup-eval
cp .build/debug/transcribe-probe .build/cleanup-eval/probe-current
IFS= read -r cleanup_signing_identity < .signing-identity
codesign --force --sign "$cleanup_signing_identity" \
  --identifier se.marcusliback.Transcribe --timestamp=none \
  --options runtime --entitlements resources/entitlements.plist \
  .build/cleanup-eval/probe-current
.build/cleanup-eval/probe-current --cleanup-demo \
  --output .build/cleanup-eval/current.json
```

Signing uses the configured app certificate and normal app identity for its existing Keychain connection. It does not alter credential access rules. The comparison's signed binaries, source snapshot, synthetic outputs and per-call reports are retained locally under ignored `.build/cleanup-eval/` (`baseline.json`, `revised.json`). They are not committed. Reports contain generated fixture text; use the fixed synthetic probe rather than redirecting private recordings into it.
