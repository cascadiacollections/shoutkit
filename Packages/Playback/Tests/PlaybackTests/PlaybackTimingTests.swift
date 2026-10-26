import Testing

/// Real-time playback windows share the main actor. Running these suites
/// together lets unrelated timer deadlines expire before their tasks run on
/// a busy simulator. Serialize the timing suites while keeping other tests
/// parallel and preserving every recovery/cancellation assertion.
@Suite(.serialized)
struct PlaybackTimingTests {}
