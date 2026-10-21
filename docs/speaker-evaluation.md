# Noisy-recording speaker evaluation — 2026-10-21

The user supplied a recording with two main participants, background noise and occasional other voices, and authorized local investigation. Used isolated copies under ignored `.build/speaker-evaluation/`, reusing existing models. The source AAC remained byte-identical. Decoded duration was 633.28 seconds (10:33); the ADTS duration estimate from `afinfo` was shorter and was not used as the reference duration.

## Framework settings

Pianissimo produced 1330 timed words. The initial app pipeline saved 191 sections with three assigned speaker labels and nine unassigned sections. SpeakerKit comparisons on the same recognition output tested its default configuration, a fixed count of two, clustering distance thresholds 0.5/0.7 (default 0.6), and a 0.2-second `minActiveOffset` applied to the default result. Subsequent inference/comparison commands ran with network access explicitly denied.

The threshold changes retained three clusters and the same aggregate section counts. Filling short gaps between speaker segments did not resolve the nine unassigned sections. A fixed count produced two clusters but redistributed the third automatic cluster across both remaining labels; this is not foreground/background separation. Consequently no new clustering default or advanced settings UI was adopted.

## Bounded word alignment

Several short recognized words fell just outside a speaker turn, sometimes only 20–130 milliseconds before its onset. The app previously required positive interval overlap and turned these words into isolated Unassigned sections.

For complete, unedited native word evidence, allow a missing-overlap match only for a word lasting at most 0.5 seconds, within 0.15 seconds of exactly one nearby speaker label. Competing labels and larger gaps remain unassigned. Actual overlap retains priority. Zero-duration timing points inside a speaker turn can also match it. No speaker turn is extended, no short known-speaker switch is smoothed, and no wording/punctuation is generated. Coarse or user-edited text keeps its existing conservative assignment path.

Replayed the **same saved turn times and labels** through the revised aligner:

| Speaker settings | Sections before → after | Unassigned before → after | Sections of at most two words before → after |
| --- | ---: | ---: | ---: |
| Automatic | 191 → 185 | 9 → 3 | 60 → 54 |
| Fixed count: 2 | 180 → 173 | 9 → 2 | 51 → 45 |
| Threshold: 0.5 | 191 → 185 | 9 → 3 | 60 → 54 |
| Threshold: 0.7 | 191 → 185 | 9 → 3 | 60 → 54 |
| Automatic with 0.2 s segment gap | 189 → 183 | 9 → 3 | 59 → 53 |

Every replay retained the recognized word sequence and the original alignment data. Diarization turn times/labels were unchanged. These are structural counts, not a speaker error rate or proof that each repaired label is correct. Remaining short sections can be legitimate short replies or speaker changes and were not removed just to reduce the count.

A fresh complete Pianissimo → SpeakerKit run with the fix also saved 185 sections, three speaker labels and three unassigned sections, with network access denied. This validates the complete local pipeline in addition to the fixed-evidence comparison.

Whisper Turbo also completed on the same audio offline, producing 231 sections, three labels and one unassigned section. Its recognized text and segmentation differ from Pianissimo's; these counts do not establish a recognition-quality ranking. The normal Whisper word-attribution path continues to use SpeakerKit's own alignment.

## Limits and reproduction

There is no manually labeled speaker reference or verbatim transcript for this recording. No DER/WER, identity assignment, verified background-speaker classification or model-accuracy ranking is claimed. Forcing two clusters does not prove improved attribution when additional voices are audible. This change targets timing fragmentation, not acoustic separation, denoising or rewritten prose. Existing projects and edits were not modified; the fix applies when rebuilding speaker attribution from intact native word evidence.

Use the commands in README with prepared models and a fresh private output directory. Comparisons write timing evidence plus transcript snapshots; `--reuse-evidence` applies the current aligner to those same turns without loading models or running inference. Keep these files out of Git. The committed report contains aggregate measurements only, without recording text or voice embeddings.
