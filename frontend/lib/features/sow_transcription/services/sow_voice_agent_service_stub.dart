import 'sow_voice_agent_service_base.dart';

SowVoiceAgentService createSowVoiceAgentService() {
  throw UnsupportedError(
    'The voice assistant is currently supported on web only. '
    'Mobile support requires a PCM audio playback package.',
  );
}
